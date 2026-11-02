import Foundation

/// System-wide now playing info (every app and browser) through MediaRemote.
/// Since macOS 15.4 MediaRemote only answers Apple-signed processes, so Notchy runs the
/// bundled NotchyMediaAdapter.dylib inside /usr/bin/perl and talks to it over pipes:
/// JSON lines on stdout, commands on stdin.
@MainActor
final class MediaAdapterSource: NowPlayingSource {
    var onChange: ((NowPlayingTrack?) -> Void)?
    var onArtwork: ((Data?) -> Void)?

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var lastArtworkID: Int = -1
    private var restartDelay: TimeInterval = 1

    func start() {
        guard let resources = Bundle.main.resourceURL?.appendingPathComponent("MediaAdapter"),
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("NotchyMediaAdapter.dylib").path) else {
            NSLog("Notchy: media adapter missing from the bundle")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [resources.appendingPathComponent("run.pl").path,
                             resources.appendingPathComponent("NotchyMediaAdapter.dylib").path]
        let stdout = Pipe(), stdin = Pipe()
        process.standardOutput = stdout
        process.standardInput = stdin
        process.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async { self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.restart() }
        }
        do {
            try process.run()
            self.process = process
            input = stdin.fileHandleForWriting
        } catch {
            NSLog("Notchy: could not start the media adapter: \(error)")
        }
    }

    func stop() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    func send(_ command: MediaCommand) {
        write(command.rawValue)
    }

    func seek(to time: TimeInterval) {
        write("seek \(time)")
    }

    private func write(_ line: String) {
        try? input?.write(contentsOf: Data((line + "\n").utf8))
    }

    private func restart() {
        process = nil
        input = nil
        buffer.removeAll()
        lastArtworkID = -1
        // Back off if the adapter keeps crashing (e.g. a future macOS blocks it).
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay) { [weak self] in self?.start() }
        restartDelay = min(restartDelay * 2, 60)
    }

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                handle(json)
            }
        }
    }

    private func handle(_ json: [String: Any]) {
        guard json["type"] as? String == "state" else {
            if json["type"] as? String == "ready" { restartDelay = 1 }
            return
        }
        guard let title = json["title"] as? String, !title.isEmpty else {
            onChange?(nil)
            return
        }
        let timestamp = (json["timestamp"] as? Double).map(Date.init(timeIntervalSince1970:)) ?? .now
        let track = NowPlayingTrack(
            title: title,
            artist: json["artist"] as? String ?? "",
            album: json["album"] as? String ?? "",
            duration: json["duration"] as? Double ?? 0,
            elapsed: json["elapsed"] as? Double ?? 0,
            elapsedAt: timestamp,
            isPlaying: (json["playing"] as? NSNumber)?.boolValue ?? false,
            // Safari plays through a WebKit helper; its parent is the browser.
            bundleID: json["parentBundleID"] as? String ?? json["bundleID"] as? String,
            domain: nil
        )
        // Artwork first, so the service sees it when it publishes the track.
        let artworkID = (json["artworkID"] as? NSNumber)?.intValue ?? 0
        if artworkID != lastArtworkID {
            if artworkID == 0 {
                lastArtworkID = 0
                onArtwork?(nil)
            } else if let base64 = json["artwork"] as? String, let data = Data(base64Encoded: base64) {
                lastArtworkID = artworkID
                onArtwork?(data)
            }
        }
        onChange?(track)
    }
}
