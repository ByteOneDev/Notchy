import AppKit

struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    /// Elapsed time measured at `elapsedAt`; the live position is extrapolated from it.
    var elapsed: TimeInterval
    var elapsedAt: Date
    var isPlaying: Bool
    /// App that plays the media (for a browser: the browser itself).
    var bundleID: String?
    /// Web site playing the media when the source is a browser.
    var domain: String?
    /// Source outside the allowed lists: only its name and logo are shown, not what it plays.
    var logoOnly = false

    var identity: String { "\(bundleID ?? "")|\(title)|\(artist)" }

    func position(at date: Date = .now) -> TimeInterval {
        guard isPlaying else { return elapsed }
        let position = elapsed + date.timeIntervalSince(elapsedAt)
        return duration > 0 ? min(position, duration) : position
    }
}

enum MediaCommand: String {
    case toggle, play, pause, next, previous
}

/// Something that knows what is playing: MediaRemote, or an app driven by AppleScript.
@MainActor
protocol NowPlayingSource: AnyObject {
    var onChange: ((NowPlayingTrack?) -> Void)? { get set }
    var onArtwork: ((Data?) -> Void)? { get set }
    func start()
    func send(_ command: MediaCommand)
    func seek(to time: TimeInterval)
}

enum Script {
    /// Runs AppleScript through osascript off the main thread. Returns stdout, trimmed.
    static func run(_ source: String, timeout: TimeInterval = 4) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", source]
                let out = Pipe()
                process.standardOutput = out
                process.standardError = Pipe()
                do { try process.run() } catch {
                    continuation.resume(returning: nil); return
                }
                let deadline = DispatchTime.now() + timeout
                DispatchQueue.global().asyncAfter(deadline: deadline) { if process.isRunning { process.terminate() } }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { continuation.resume(returning: nil); return }
                let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text)
            }
        }
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
