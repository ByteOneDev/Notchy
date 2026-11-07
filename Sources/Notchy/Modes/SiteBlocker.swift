import AppKit
import Combine

/// Keeps distracting sites closed while a mode that lists them is active: browser tabs on
/// those sites are sent to a "blocked" page served by Notchy, which goes back to the site by
/// itself once the mode ends. Works with the browsers that can be scripted (Safari and the
/// Chromium ones); Firefox can't be.
@MainActor
final class SiteBlocker {
    static let shared = SiteBlocker()

    private static let browsers = [
        "com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "company.thebrowser.Browser",
    ]

    /// Blocked domain → name of the mode that blocks it.
    private(set) var blocked: [String: String] = [:]
    private var timer: Timer?
    private var checking = false
    private var cancellables = Set<AnyCancellable>()

    func start() {
        ModeEngine.shared.$active
            .combineLatest(AppSettings.shared.$modes)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }
            .store(in: &cancellables)
    }

    private func update() {
        var blocked: [String: String] = [:]
        for mode in ModeEngine.shared.activeModes {
            for site in mode.blockedSites where blocked[site] == nil { blocked[site] = mode.name }
        }
        self.blocked = blocked
        if blocked.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                MainActor.assumeIsolated { SiteBlocker.shared.check() }
            }
            check()
        }
    }

    /// The domain a host belongs to among the blocked ones ("m.youtube.com" → "youtube.com").
    func blockedDomain(for host: String) -> String? {
        let host = host.lowercased()
        return blocked.keys.first { host == $0 || host.hasSuffix("." + $0) }
    }

    private func check() {
        guard !checking, !blocked.isEmpty else { return }
        let running = Self.browsers.filter(Script.isRunning)
        guard !running.isEmpty else { return }
        checking = true
        Task {
            for browser in running { await check(browser) }
            checking = false
        }
    }

    private func check(_ browser: String) async {
        // Inside the browser's tell block, `tab` means a browser tab: separators are literal.
        let script = """
        set out to ""
        tell application id "\(browser)"
            set wi to 0
            repeat with w in windows
                set wi to wi + 1
                set ti to 0
                try
                    repeat with t in tabs of w
                        set ti to ti + 1
                        try
                            set out to out & wi & "\t" & ti & "\t" & (URL of t) & "\n"
                        end try
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
        guard let output = await Script.run(script) else { return }
        var redirects: [String] = []
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3, let url = URL(string: parts[2]), let host = url.host(),
                  let domain = blockedDomain(for: host), let page = Self.pageURL(site: domain, from: url) else { continue }
            redirects.append("set URL of tab \(parts[1]) of window \(parts[0]) to \"\(page)\"")
        }
        guard !redirects.isEmpty else { return }
        _ = await Script.run("tell application id \"\(browser)\"\n" + redirects.joined(separator: "\n") + "\nend tell")
    }

    private static func pageURL(site: String, from url: URL) -> String? {
        var components = URLComponents(string: "http://127.0.0.1:\(LocalServer.port)/blocked")!
        components.queryItems = [URLQueryItem(name: "site", value: site), URLQueryItem(name: "from", value: url.absoluteString)]
        // Inside an AppleScript string: no quotes or backslashes.
        return components.url?.absoluteString.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\\", with: "%5C")
    }

    // MARK: Blocked page

    /// `/blocked?site=…&from=…` shows the page; `/blocked/state?site=…` tells it whether the
    /// site is still blocked, so it can go back to where it was.
    func response(for path: String) -> LocalServer.Response {
        let components = URLComponents(string: "http://localhost" + path)
        let query = Dictionary((components?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let site = query["site"] ?? ""
        let mode = blocked[site]
        if components?.path == "/blocked/state" {
            return .json(["blocked": mode != nil])
        }
        // Only send the tab back to a web page.
        let fromURL = query["from"].flatMap(URL.init(string:))
        let from = fromURL.map { ["http", "https"].contains($0.scheme) ? $0.absoluteString : "" } ?? ""
        let html = Self.page
            .replacingOccurrences(of: "{{title}}", with: Self.escape(L("blocker.title", site)))
            .replacingOccurrences(of: "{{subtitle}}", with: Self.escape(mode.map { L("blocker.subtitle", $0) } ?? L("blocker.ended")))
            .replacingOccurrences(of: "{{site}}", with: Self.escape(site))
            .replacingOccurrences(of: "{{from}}", with: Self.escape(from))
            .replacingOccurrences(of: "{{lang}}", with: Loc.language.rawValue)
        return LocalServer.Response(contentType: "text/html; charset=utf-8", body: Data(html.utf8))
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static let page = """
    <!doctype html>
    <html lang="{{lang}}"><head><meta charset="utf-8"><title>{{site}}</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      html, body { height: 100%; margin: 0; }
      body { background: #0b0b0f; color: #f2f2f7; font: 15px -apple-system, BlinkMacSystemFont, sans-serif;
             display: flex; align-items: center; justify-content: center; }
      .card { text-align: center; padding: 40px 48px; border-radius: 28px; background: #000;
              box-shadow: 0 0 80px rgba(175, 82, 222, .35); max-width: 440px; }
      .icon { font-size: 44px; margin-bottom: 14px; }
      h1 { font-size: 22px; margin: 0 0 8px; font-weight: 650; }
      p { margin: 0; color: #a1a1aa; line-height: 1.45; }
    </style></head>
    <body><div class="card" data-from="{{from}}" data-site="{{site}}">
      <div class="icon">🌙</div>
      <h1>{{title}}</h1>
      <p>{{subtitle}}</p>
    </div>
    <script>
      // Back to the page once the mode is over.
      const card = document.querySelector('.card');
      async function poll() {
        try {
          const r = await fetch('/blocked/state?site=' + encodeURIComponent(card.dataset.site));
          const s = await r.json();
          if (!s.blocked && card.dataset.from) { location.replace(card.dataset.from); return; }
        } catch (e) {}
        setTimeout(poll, 3000);
      }
      setTimeout(poll, 3000);
    </script></body></html>
    """

    /// "https://www.YouTube.com/watch?v=…, x.com" → ["youtube.com", "x.com"]
    static func parse(_ text: String) -> [String] {
        var result: [String] = []
        for token in text.components(separatedBy: CharacterSet(charactersIn: ", \n\t;")) {
            var site = token.trimmingCharacters(in: .whitespaces).lowercased()
            if let range = site.range(of: "://") { site = String(site[range.upperBound...]) }
            site = String(site.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
            if site.hasPrefix("www.") { site = String(site.dropFirst(4)) }
            guard site.contains("."), !result.contains(site) else { continue }
            result.append(site)
        }
        return result
    }
}
