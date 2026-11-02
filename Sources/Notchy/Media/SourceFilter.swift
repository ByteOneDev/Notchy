import Foundation

/// Decides which media may appear in the notch: listed audio apps, and in browsers only
/// listed sites (YouTube, Spotify web…). Anything else, like niche video sites, is ignored.
@MainActor
enum SourceFilter {
    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]
    static let safari = "com.apple.Safari"
    static let unscriptableBrowsers: Set<String> = ["org.mozilla.firefox", "app.zen-browser.zen"]

    static func isBrowser(_ bundleID: String) -> Bool {
        chromiumBrowsers.contains(bundleID) || bundleID == safari || unscriptableBrowsers.contains(bundleID)
    }

    private static var domainCache: [String: String?] = [:]

    /// Returns the track with its web site filled in, or nil when it must not be shown.
    static func filter(_ track: NowPlayingTrack) async -> NowPlayingTrack? {
        let settings = AppSettings.shared
        guard let bundleID = track.bundleID else { return track }
        guard settings.allowedApps.contains(bundleID) else { return nil }
        guard isBrowser(bundleID) else { return track }

        let domain = await domain(for: track, browser: bundleID)
        guard let domain, isAllowed(domain: domain) else { return nil }
        var filtered = track
        filtered.domain = domain
        return filtered
    }

    static func isAllowed(domain: String) -> Bool {
        AppSettings.shared.allowedDomains.contains { allowed in
            domain == allowed || domain.hasSuffix("." + allowed)
        }
    }

    /// Finds the tab whose title matches the playing title and returns its host.
    private static func domain(for track: NowPlayingTrack, browser: String) async -> String? {
        let key = "\(browser)|\(track.title)"
        if let cached = domainCache[key] { return cached }
        guard !unscriptableBrowsers.contains(browser), Script.isRunning(browser) else { return nil }

        let titleProperty = browser == safari ? "name" : "title"
        let script = """
        set out to ""
        tell application id "\(browser)"
            repeat with w in windows
                repeat with t in tabs of w
                    set out to out & (\(titleProperty) of t) & "\t" & (URL of t) & "\n"
                end repeat
            end repeat
        end tell
        return out
        """
        guard let output = await Script.run(script) else { return nil }
        let wanted = normalize(track.title)
        var found: String?
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2, let host = URL(string: parts[1])?.host() else { continue }
            let tabTitle = normalize(parts[0])
            if !wanted.isEmpty, tabTitle.contains(wanted) || (wanted.contains(tabTitle) && tabTitle.count > 3) {
                found = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                break
            }
        }
        // A cached nil remembers "no allowed tab" too; but retry later, the tab title may lag.
        if found != nil { domainCache[key] = .some(found) }
        if domainCache.count > 200 { domainCache.removeAll() }
        return found
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
