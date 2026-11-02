import Foundation

/// System-wide now playing info through the private MediaRemote framework.
/// Since macOS 15.4 Apple only answers Apple-signed processes, so on recent systems this
/// usually stays silent and the scriptable app sources take over.
@MainActor
final class MediaRemoteSource: NowPlayingSource {
    var onChange: ((NowPlayingTrack?) -> Void)?
    var onArtwork: ((Data?) -> Void)?

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]?) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias GetClientFn = @convention(c) (DispatchQueue, @escaping (AnyObject?) -> Void) -> Void
    private typealias ClientStringFn = @convention(c) (AnyObject) -> Unmanaged<CFString>?
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    private typealias SendCommandFn = @convention(c) (Int32, CFDictionary?) -> Bool
    private typealias SetElapsedFn = @convention(c) (Double) -> Void

    private var getInfo: GetInfoFn?
    private var getIsPlaying: GetIsPlayingFn?
    private var getClient: GetClientFn?
    private var clientBundleID: ClientStringFn?
    private var clientParentBundleID: ClientStringFn?
    private var sendCommand: SendCommandFn?
    private var setElapsed: SetElapsedFn?
    private var lastArtworkLength = -1
    private var timer: Timer?
    private(set) var isAnswering = false

    func start() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW) else { return }
        func load<T>(_ name: String, _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        getInfo = load("MRMediaRemoteGetNowPlayingInfo", GetInfoFn.self)
        getIsPlaying = load("MRMediaRemoteGetNowPlayingApplicationIsPlaying", GetIsPlayingFn.self)
        getClient = load("MRMediaRemoteGetNowPlayingClient", GetClientFn.self)
        clientBundleID = load("MRNowPlayingClientGetBundleIdentifier", ClientStringFn.self)
        clientParentBundleID = load("MRNowPlayingClientGetParentAppBundleIdentifier", ClientStringFn.self)
        sendCommand = load("MRMediaRemoteSendCommand", SendCommandFn.self)
        setElapsed = load("MRMediaRemoteSetElapsedTime", SetElapsedFn.self)
        load("MRMediaRemoteRegisterForNowPlayingNotifications", RegisterFn.self)?(.main)

        for name in ["kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                     "kMRMediaRemoteNowPlayingApplicationDidChangeNotification"] {
            NotificationCenter.default.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func send(_ command: MediaCommand) {
        let code: Int32 = switch command {
        case .play: 0
        case .pause: 1
        case .toggle: 2
        case .next: 4
        case .previous: 5
        }
        _ = sendCommand?(code, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refresh() }
    }

    func seek(to time: TimeInterval) {
        setElapsed?(time)
    }

    private func refresh() {
        guard let getInfo, let getIsPlaying, let getClient else { return }
        getClient(.main) { [weak self] client in
            MainActor.assumeIsolated {
                guard let self else { return }
                let bundleID = client.flatMap { c in self.clientBundleID?(c)?.takeUnretainedValue() as String? }
                let parentID = client.flatMap { c in self.clientParentBundleID?(c)?.takeUnretainedValue() as String? }
                getIsPlaying(.main) { playing in
                    getInfo(.main) { info in
                        MainActor.assumeIsolated {
                            self.handle(info: info, playing: playing, bundleID: parentID ?? bundleID)
                        }
                    }
                }
            }
        }
    }

    private func handle(info: [String: Any]?, playing: Bool, bundleID: String?) {
        guard let info, let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty else {
            if isAnswering { onChange?(nil) }
            return
        }
        isAnswering = true
        let elapsed = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0
        let timestamp = info["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date ?? .now
        let track = NowPlayingTrack(
            title: title,
            artist: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
            album: info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String ?? "",
            duration: info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0,
            elapsed: elapsed,
            elapsedAt: timestamp,
            isPlaying: playing,
            bundleID: bundleID,
            domain: nil
        )
        onChange?(track)
        let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
        if (artwork?.count ?? 0) != lastArtworkLength {
            lastArtworkLength = artwork?.count ?? 0
            onArtwork?(artwork)
        }
    }
}
