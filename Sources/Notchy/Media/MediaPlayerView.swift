import SwiftUI

struct MediaPlayerView: View {
    @ObservedObject private var media = NowPlayingService.shared
    @ObservedObject private var lyrics = LyricsService.shared
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        if let track = media.track {
            player(track)
        } else {
            placeholder
        }
    }

    private func player(_ track: NowPlayingTrack) -> some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                ArtworkView(image: media.artwork, size: 96, radius: 16, isLogo: media.isLogoArtwork, tint: media.accent)
                    .shadow(color: media.accent.opacity(track.isPlaying ? 0.55 : 0.2), radius: 14)
                    .scaleEffect(track.isPlaying ? 1 : 0.92)
                    .animation(.spring(response: 0.4, dampingFraction: 0.6), value: track.isPlaying)
                    .onTapGesture { media.openSourceApp() }
                SourceBadge(track: track)
                    .offset(x: 6, y: 6)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        MarqueeText(text: track.title, font: .system(size: 14, weight: .semibold))
                        Text(track.artist.isEmpty ? track.album : track.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if settings.showVisualizer {
                        AudioVisualizer(color: media.accent, playing: track.isPlaying, bars: 5)
                    }
                }
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let position = track.position(at: context.date)
                    VStack(alignment: .leading, spacing: 6) {
                        if settings.showLyrics, let line = lyrics.line(at: position) {
                            Text(line)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(media.accent)
                                .lineLimit(1)
                                .transition(.push(from: .bottom))
                                .id(line)
                        }
                        Spacer(minLength: 0)
                        Scrubber(position: position, duration: track.duration, color: media.accent) { media.seek(to: $0) }
                    }
                    .animation(.easeOut(duration: 0.25), value: lyrics.line(at: position))
                }
                controls(track)
            }
        }
    }

    private func controls(_ track: NowPlayingTrack) -> some View {
        HStack(spacing: 18) {
            Spacer()
            Button { media.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 15)) }
                .buttonStyle(HoverButtonStyle())
            Button { media.togglePlayPause() } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26)
            }
            .buttonStyle(HoverButtonStyle())
            Button { media.next() } label: { Image(systemName: "forward.fill").font(.system(size: 15)) }
                .buttonStyle(HoverButtonStyle())
            Spacer()
        }
    }

    private var placeholder: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.08))
                Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(.white.opacity(0.4))
            }
            .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("media.nothing")).font(.system(size: 14, weight: .semibold))
                Text(L("media.hint")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// App icon of the source, or the site's logo for web media (YouTube…).
struct SourceBadge: View {
    let track: NowPlayingTrack

    var body: some View {
        Group {
            if let domain = track.domain, domain.contains("youtube") {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.red)
                    Image(systemName: "play.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                }
                .frame(width: 26, height: 19)
            } else if let icon {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 3)
    }

    private var icon: NSImage? {
        guard let bundleID = track.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

struct Scrubber: View {
    let position: TimeInterval
    let duration: TimeInterval
    let color: Color
    let onSeek: (TimeInterval) -> Void
    @State private var dragValue: Double?
    @State private var hovering = false

    var body: some View {
        let progress = dragValue ?? (duration > 0 ? position / duration : 0)
        HStack(spacing: 8) {
            Text((dragValue.map { $0 * duration } ?? position).clock)
                .frame(width: 34, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(color).frame(width: max(0, geo.size.width * min(1, progress)))
                }
                .frame(height: hovering || dragValue != nil ? 7 : 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { dragValue = min(1, max(0, $0.location.x / geo.size.width)) }
                    .onEnded { _ in
                        if let dragValue, duration > 0 { onSeek(dragValue * duration) }
                        dragValue = nil
                    })
            }
            .frame(height: 12)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            Text(duration > 0 ? "-" + max(0, duration - position).clock : "--:--")
                .frame(width: 38, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.55))
        .disabled(duration <= 0)
    }
}

/// Single-line text that scrolls when it does not fit.
struct MarqueeText: View {
    let text: String
    let font: Font
    @State private var textWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let overflow = textWidth - geo.size.width
            TimelineView(.animation(minimumInterval: 1 / 30, paused: overflow <= 0)) { context in
                let cycle = Double(overflow + 40) / 25 + 3
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle * 2)
                let progress = max(0, min(1, (t < cycle ? t - 1.5 : cycle * 2 - t - 1.5) / (cycle - 3)))
                Text(text)
                    .font(font)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
                    .offset(x: overflow > 0 ? -overflow * progress : 0)
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9), .init(color: overflow > 0 ? .clear : .black, location: 1)], startPoint: .leading, endPoint: .trailing))
        }
        .frame(height: 18)
    }
}
