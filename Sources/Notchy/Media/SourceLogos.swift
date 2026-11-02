import AppKit

/// Logo standing in for the artwork: the site's icon for web audio, the app icon otherwise.
@MainActor
enum SourceLogos {
    private static var cache: [String: NSImage] = [:]

    static func logo(for track: NowPlayingTrack) async -> NSImage? {
        if let domain = track.domain {
            if let site = await siteIcon(domain) { return site }
        }
        guard let bundleID = track.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// The site's own touch icon (large), else its favicon, else DuckDuckGo's icon service.
    private static func siteIcon(_ domain: String) async -> NSImage? {
        if let cached = cache[domain] { return cached }
        let candidates = [
            "https://\(domain)/apple-touch-icon.png",
            "https://www.\(domain)/apple-touch-icon.png",
            "https://\(domain)/favicon.ico",
            "https://icons.duckduckgo.com/ip3/\(domain).ico",
        ]
        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            var request = URLRequest(url: url, timeoutInterval: 4)
            request.setValue("Mozilla/5.0 (Macintosh) Notchy", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data), image.size.width >= 16 else { continue }
            cache[domain] = image
            return image
        }
        return nil
    }
}
