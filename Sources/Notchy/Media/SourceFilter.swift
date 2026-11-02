import AppKit

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
    /// Lookups that found no tab, retried after a while instead of on every update.
    private static var missCache: [String: Date] = [:]

    /// Returns the track as it should be shown, or nil when it must not be shown.
    /// Listed apps and sites show everything; any other source, when "all audio sources" is on,
    /// shows only its name and logo (e.g. "archive.org" with the site's icon).
    static func filter(_ track: NowPlayingTrack) async -> NowPlayingTrack? {
        let settings = AppSettings.shared
        guard let bundleID = track.bundleID else { return track }
        let listedApp = settings.allowedApps.contains(bundleID)

        if isBrowser(bundleID) {
            let domain = await domain(for: track, browser: bundleID)
            var result = track
            result.domain = domain
            if listedApp, let domain, isAllowed(domain: domain) { return result }
            return settings.allAudioSources ? logoOnly(result, name: domain ?? appName(bundleID)) : nil
        }
        if listedApp { return track }
        return settings.allAudioSources ? logoOnly(track, name: appName(bundleID)) : nil
    }

    private static func logoOnly(_ track: NowPlayingTrack, name: String) -> NowPlayingTrack {
        var result = track
        result.logoOnly = true
        result.title = name
        result.artist = track.domain != nil ? appName(track.bundleID ?? "") : ""
        result.album = ""
        return result
    }

    static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
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
        if let miss = missCache[key], Date.now.timeIntervalSince(miss) < 20 { return nil }
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
        if found != nil { domainCache[key] = .some(found) } else { missCache[key] = .now }
        if domainCache.count > 200 { domainCache.removeAll() }
        return found
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
