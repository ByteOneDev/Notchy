import AppKit
import Combine
import SwiftUI

/// Single source of truth for what is playing, merged from every source and filtered.
@MainActor
final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    /// The artwork is a site or app logo, drawn smaller on a tinted tile.
    @Published private(set) var isLogoArtwork = false
    /// Last time something played; the closed notch keeps showing a paused track for a while.
    @Published private(set) var lastPlayingDate: Date = .distantPast

    private let mediaRemote = MediaAdapterSource()
    private let scriptable = [ScriptableAppSource(app: ScriptableAppSource.spotify), ScriptableAppSource(app: ScriptableAppSource.music)]
    private var candidates: [ObjectIdentifier: NowPlayingTrack] = [:]
    private var artworks: [ObjectIdentifier: NSImage] = [:]
    private var activeSource: NowPlayingSource?
    private var cancellables = Set<AnyCancellable>()

    func start() {
        let sources: [NowPlayingSource] = [mediaRemote] + scriptable
        for source in sources {
            let id = ObjectIdentifier(source)
            source.onChange = { [weak self, weak source] track in
                guard let self, let source else { return }
                self.candidates[id] = track
                self.resolve(preferring: track?.isPlaying == true ? source : nil)
            }
            source.onArtwork = { [weak self] data in
                guard let self else { return }
                self.artworks[id] = data.flatMap(NSImage.init(data:))
                if self.activeSource.map(ObjectIdentifier.init) == id { self.applyArtwork(self.artworks[id]) }
            }
            source.start()
        }
        AppSettings.shared.$allowedApps.map { _ in () }
            .merge(with: AppSettings.shared.$allowedDomains.map { _ in () }, AppSettings.shared.$allAudioSources.map { _ in () })
            .dropFirst(3)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.resolve(preferring: nil) } }
            .store(in: &cancellables)
    }

    /// Show the playing source first, then the most recent paused one.
    private func resolve(preferring preferred: NowPlayingSource?) {
        let sources: [NowPlayingSource] = (preferred.map { [$0] } ?? []) + [mediaRemote] + scriptable
        let ordered = sources.compactMap { source -> (NowPlayingSource, NowPlayingTrack)? in
            guard let track = candidates[ObjectIdentifier(source)] else { return nil }
            return (source, track)
        }
        let pick = ordered.first { $0.1.isPlaying } ?? ordered.first(where: { $0.0 === activeSource }) ?? ordered.first
        guard let (source, track) = pick else {
            publish(nil, from: nil)
            return
        }
        Task {
            let filtered = await SourceFilter.filter(track)
            if filtered == nil, let fallback = ordered.first(where: { $0.0 !== source && $0.1.isPlaying }) {
                publish(await SourceFilter.filter(fallback.1), from: fallback.0)
            } else {
                publish(filtered, from: filtered == nil ? nil : source)
            }
        }
    }

    private func publish(_ newTrack: NowPlayingTrack?, from source: NowPlayingSource?) {
        guard AppSettings.shared.mediaEnabled else {
            track = nil
            return
        }
        let changedTrack = newTrack?.identity != track?.identity
        activeSource = source
        if newTrack?.isPlaying == true || track?.isPlaying == true { lastPlayingDate = .now }
        if track != newTrack {
            withAnimation(.notchActivity) { track = newTrack }
        }
        if changedTrack || artwork == nil {
            applyArtwork(source.flatMap { artworks[ObjectIdentifier($0)] })
        }
        if changedTrack, let newTrack {
            if newTrack.logoOnly { LyricsService.shared.clear() } else { LyricsService.shared.load(for: newTrack) }
        }
    }

    /// Shows the artwork; a source without one (or shown by name only) gets its logo instead,
    /// which also gives the accent color.
    private func applyArtwork(_ image: NSImage?) {
        if let image, track?.logoOnly != true {
            setArtwork(image, isLogo: false)
            return
        }
        guard let track else { return setArtwork(nil, isLogo: false) }
        let identity = track.identity
        Task {
            let logo = await SourceLogos.logo(for: track)
            guard self.track?.identity == identity else { return }
            self.setArtwork(logo, isLogo: logo != nil)
        }
    }

    private func setArtwork(_ image: NSImage?, isLogo: Bool) {
        artwork = image
        isLogoArtwork = isLogo
        withAnimation(.easeInOut(duration: 0.4)) { accent = image?.accentColor ?? .white }
    }

    // MARK: Controls

    func togglePlayPause() { activeSource?.send(.toggle) }
    func next() { activeSource?.send(.next) }
    func previous() { activeSource?.send(.previous) }
    func seek(to time: TimeInterval) { activeSource?.seek(to: time) }

    /// Whether the closed notch should show the media activity.
    var showsInClosedNotch: Bool {
        guard let track else { return false }
        return track.isPlaying || Date.now.timeIntervalSince(lastPlayingDate) < 20
    }

    func openSourceApp() {
        guard let track else { return }
        if let domain = track.domain, let url = URL(string: "https://\(domain)") , track.bundleID == nil {
            NSWorkspace.shared.open(url)
        } else if let bundleID = track.bundleID,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
        }
    }
}

extension NSImage {
    /// Average color, brightened so it stays visible on black.
    var accentColor: Color? {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(s * 1.2, 0.9), brightness: max(b, 0.75))
    }
}
