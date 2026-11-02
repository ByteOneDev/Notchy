import AppKit

/// Spotify or Apple Music, followed through the notifications they broadcast and driven with
/// AppleScript. These public interfaces keep working whatever Apple does to MediaRemote.
@MainActor
final class ScriptableAppSource: NowPlayingSource {
    struct App {
        let bundleID: String
        let scriptName: String
        let notification: String
        /// Duration unit in the notification payload / AppleScript (Spotify and Music use milliseconds / seconds).
        let notificationDurationInMs: Bool
    }

    static let spotify = App(bundleID: "com.spotify.client", scriptName: "Spotify",
                             notification: "com.spotify.client.PlaybackStateChanged", notificationDurationInMs: true)
    static let music = App(bundleID: "com.apple.Music", scriptName: "Music",
                           notification: "com.apple.Music.playerInfo", notificationDurationInMs: true)

    var onChange: ((NowPlayingTrack?) -> Void)?
    var onArtwork: ((Data?) -> Void)?

    let app: App
    private(set) var track: NowPlayingTrack?
    private var artworkKey = ""

    init(app: App) { self.app = app }

    func start() {
        DistributedNotificationCenter.default().addObserver(forName: .init(app.notification), object: nil, queue: .main) { [weak self] note in
            let info = note.userInfo ?? [:]
            MainActor.assumeIsolated { self?.handle(notification: info) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, bundleID == self.app.bundleID else { return }
                self.track = nil
                self.onChange?(nil)
            }
        }
        Task { await poll() }
    }

    func send(_ command: MediaCommand) {
        guard Script.isRunning(app.bundleID) else { return }
        let verb = switch command {
        case .toggle: "playpause"
        case .play: "play"
        case .pause: "pause"
        case .next: "next track"
        case .previous: "previous track"
        }
        // Optimistic update so the UI reacts instantly.
        if var track, command == .toggle || command == .play || command == .pause {
            track.elapsed = track.position()
            track.elapsedAt = .now
            track.isPlaying = command == .toggle ? !track.isPlaying : command == .play
            self.track = track
            onChange?(track)
        }
        Task {
            _ = await Script.run("tell application id \"\(app.bundleID)\" to \(verb)")
            try? await Task.sleep(for: .milliseconds(350))
            await poll()
        }
    }

    func seek(to time: TimeInterval) {
        guard Script.isRunning(app.bundleID) else { return }
        if var track {
            track.elapsed = time
            track.elapsedAt = .now
            self.track = track
            onChange?(track)
        }
        Task { _ = await Script.run("tell application id \"\(app.bundleID)\" to set player position to \(time)") }
    }

    private func handle(notification info: [AnyHashable: Any]) {
        let state = info["Player State"] as? String ?? ""
        guard state != "Stopped", let title = info["Name"] as? String else {
            track = nil
            onChange?(nil)
            return
        }
        let rawDuration = (info["Duration"] as? Double) ?? (info["Total Time"] as? Double) ?? 0
        let duration = app.notificationDurationInMs ? rawDuration / 1000 : rawDuration
        let position = info["Playback Position"] as? Double
        var track = NowPlayingTrack(
            title: title,
            artist: info["Artist"] as? String ?? "",
            album: info["Album"] as? String ?? "",
            duration: duration,
            elapsed: position ?? self.track?.position() ?? 0,
            elapsedAt: .now,
            isPlaying: state == "Playing",
            bundleID: app.bundleID,
            domain: nil
        )
        if let previous = self.track, previous.identity != track.identity, position == nil {
            track.elapsed = 0
        }
        self.track = track
        onChange?(track)
        // Music does not send the position; ask for it, and refresh the artwork if needed.
        Task { await poll() }
    }

    /// Reads the whole player state through AppleScript.
    private func poll() async {
        guard Script.isRunning(app.bundleID) else { return }
        let separator = "‖"
        let script = """
        tell application id "\(app.bundleID)"
            if player state is stopped then return "stopped"
            set t to current track
            return (name of t) & "\(separator)" & (artist of t) & "\(separator)" & (album of t) & "\(separator)" & ((duration of t) as text) & "\(separator)" & ((player position) as text) & "\(separator)" & ((player state) as text)
        end tell
        """
        guard let output = await Script.run(script) else { return }
        if output == "stopped" {
            track = nil
            onChange?(nil)
            return
        }
        let parts = output.components(separatedBy: separator)
        guard parts.count == 6 else { return }
        let number = { (text: String) in Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        // Spotify reports the duration in ms through AppleScript too, Music in seconds.
        let rawDuration = number(parts[3])
        let duration = app.bundleID == Self.spotify.bundleID ? rawDuration / 1000 : rawDuration
        let track = NowPlayingTrack(
            title: parts[0], artist: parts[1], album: parts[2],
            duration: duration, elapsed: number(parts[4]), elapsedAt: .now,
            isPlaying: parts[5] == "playing", bundleID: app.bundleID, domain: nil
        )
        self.track = track
        onChange?(track)
        await loadArtworkIfNeeded(for: track)
    }

    private func loadArtworkIfNeeded(for track: NowPlayingTrack) async {
        let key = "\(track.title)|\(track.album)"
        guard key != artworkKey else { return }
        artworkKey = key
        if app.bundleID == Self.spotify.bundleID {
            guard let urlText = await Script.run("tell application id \"\(app.bundleID)\" to artwork url of current track"),
                  let url = URL(string: urlText),
                  let (data, _) = try? await URLSession.shared.data(from: url) else { onArtwork?(nil); return }
            onArtwork?(data)
        } else {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("notchy-artwork-\(UUID().uuidString)")
            let script = """
            tell application id "\(app.bundleID)"
                if (count of artworks of current track) is 0 then return "none"
                set d to raw data of artwork 1 of current track
            end tell
            set f to open for access (POSIX file "\(file.path)") with write permission
            set eof f to 0
            write d to f
            close access f
            return "ok"
            """
            let result = await Script.run(script)
            let data = result == "ok" ? try? Data(contentsOf: file) : nil
            try? FileManager.default.removeItem(at: file)
            onArtwork?(data)
        }
    }
}
