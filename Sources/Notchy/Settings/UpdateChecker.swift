import AppKit
import Security

/// Keeps Notchy up to date from the GitHub releases: checks at launch and every few hours,
/// downloads the new version, makes sure it is signed by the same certificate as the running
/// app, swaps the bundle and relaunches.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var statusText = ""
    @Published private(set) var availableVersion: String?
    @Published private(set) var availableURL: URL?
    @Published private(set) var isInstalling = false

    private var downloadURL: URL?
    private var timer: Timer?
    private static let repo = "ByteOneDev/Notchy"
    private static let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Notchy", isDirectory: true)
    private static let failureMarker = supportDirectory.appendingPathComponent("update-failed")

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Self-update only replaces an app installed in an Applications folder (not a dev build).
    var canSelfUpdate: Bool {
        let path = Bundle.main.bundleURL.deletingLastPathComponent().path
        let applications = ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        return applications.contains(path) && FileManager.default.isWritableFile(atPath: path)
    }

    func start() {
        announceFinishedUpdate()
        guard AppSettings.shared.autoCheckUpdates else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { self.check(userInitiated: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard AppSettings.shared.autoCheckUpdates else { return }
                UpdateChecker.shared.check(userInitiated: false)
            }
        }
    }

    func check(userInitiated: Bool) {
        guard !isInstalling else { return }
        statusText = L("update.checking")
        Task {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
                statusText = L("update.failed")
                if userInitiated { SettingsWindowController.shared.show(pane: .about) }
                return
            }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            guard latest.compare(Self.currentVersion, options: .numeric) == .orderedDescending else {
                availableVersion = nil
                availableURL = nil
                statusText = L("update.upToDate")
                if userInitiated { SettingsWindowController.shared.show(pane: .about) }
                return
            }
            let assets = json["assets"] as? [[String: Any]] ?? []
            downloadURL = assets.first { ($0["name"] as? String)?.hasSuffix(".zip") == true }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
            availableVersion = latest
            availableURL = page
            statusText = L("update.available", latest)
            if canSelfUpdate, downloadURL != nil, AppSettings.shared.autoInstallUpdates || userInitiated {
                install(force: userInitiated)
            } else {
                LiveActivityCenter.shared.show(.update(version: latest, state: .available), duration: 5)
                if userInitiated { SettingsWindowController.shared.show(pane: .about) }
            }
        }
    }

    /// Something the user is in the middle of: an automatic update waits for it to end.
    private var isBusy: Bool {
        Teleprompter.shared.isRunning || !AgentHub.shared.pendingPermissions.isEmpty
            || NotchManager.shared.controllers.values.contains { $0.viewModel.isOpen }
            || PomodoroTimer.shared.isRunning || QuickTimer.shared.isRunning
    }

    func install(force: Bool = false) {
        guard let version = availableVersion, let downloadURL, canSelfUpdate, !isInstalling else { return }
        if !force, isBusy {
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) { self.install() }
            return
        }
        isInstalling = true
        statusText = L("update.installing", version)
        LiveActivityCenter.shared.show(.update(version: version, state: .installing), duration: 120)
        Task {
            do {
                let app = try await Self.download(downloadURL)
                try Self.verify(app, expectedVersion: version)
                try Self.replaceAndRelaunch(with: app)
            } catch {
                NSLog("Notchy: update failed: \(error)")
                isInstalling = false
                statusText = L("update.installFailed")
                LiveActivityCenter.shared.dismiss(group: "update")
            }
        }
    }

    // MARK: Steps

    private struct UpdateError: Error, CustomStringConvertible {
        let description: String
    }

    /// Downloads the release zip and unpacks it; returns the new Notchy.app.
    private static func download(_ url: URL) async throws -> URL {
        let (file, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError(description: "download failed") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchyUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", file.path, folder.path]
        try unzip.run()
        unzip.waitUntilExit()
        let app = folder.appendingPathComponent("Notchy.app")
        guard unzip.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else {
            throw UpdateError(description: "unzip failed")
        }
        return app
    }

    /// The new app must be Notchy, in the announced version, signed like the running app.
    private static func verify(_ app: URL, expectedVersion: String) throws {
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion else {
            throw UpdateError(description: "unexpected bundle")
        }
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
              SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError(description: "cannot read signatures")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw UpdateError(description: "signature does not match the installed app")
        }
    }

    /// A small script waits for Notchy to quit, swaps the bundles (restoring the old one if
    /// anything fails) and opens the result.
    private static func replaceAndRelaunch(with newApp: URL) throws {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let destination = Bundle.main.bundleURL.path
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "$DEST.old"
        if mv "$DEST" "$DEST.old" && ditto "$NEW" "$DEST"; then
          rm -rf "$DEST.old"
        else
          rm -rf "$DEST"; mv "$DEST.old" "$DEST"; touch "$MARKER"
        fi
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        open "$DEST"
        rm -rf "$(dirname "$NEW")"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.environment = ["DEST": destination, "NEW": newApp.path, "MARKER": failureMarker.path,
                               "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        try process.run()
        NSApp.terminate(nil)
    }

    /// After a relaunch: say the update went through, or why it didn't.
    private func announceFinishedUpdate() {
        let defaults = UserDefaults.standard
        if FileManager.default.fileExists(atPath: Self.failureMarker.path) {
            try? FileManager.default.removeItem(at: Self.failureMarker)
            statusText = L("update.permission")
            SettingsWindowController.shared.show(pane: .about)
        }
        let previous = defaults.string(forKey: "lastRunVersion")
        defaults.set(Self.currentVersion, forKey: "lastRunVersion")
        if let previous, previous.compare(Self.currentVersion, options: .numeric) == .orderedAscending {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                LiveActivityCenter.shared.show(.update(version: Self.currentVersion, state: .installed), duration: 4)
            }
        }
    }
}
