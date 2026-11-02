import AppKit

/// Compares the running version with the latest GitHub release.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    @Published private(set) var statusText = ""
    @Published private(set) var availableURL: URL?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    func check(userInitiated: Bool) {
        statusText = L("update.checking")
        Task {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/ByteOneDev/Notchy/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
                statusText = L("update.failed")
                return
            }
            let latest = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if latest.compare(Self.currentVersion, options: .numeric) == .orderedDescending {
                availableURL = page
                statusText = L("update.available", latest)
                if userInitiated {
                    SettingsWindowController.shared.show(pane: .about)
                }
            } else {
                availableURL = nil
                statusText = L("update.upToDate")
                if userInitiated { SettingsWindowController.shared.show(pane: .about) }
            }
        }
    }
}
