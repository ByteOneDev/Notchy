import Foundation

/// Synced lyrics from LRCLIB (free, no key).
@MainActor
final class LyricsService: ObservableObject {
    static let shared = LyricsService()

    struct Line: Equatable {
        let time: TimeInterval
        let text: String
    }

    @Published private(set) var lines: [Line] = []
    private var loadedIdentity = ""
    private var task: Task<Void, Never>?

    func load(for track: NowPlayingTrack) {
        guard AppSettings.shared.showLyrics, track.identity != loadedIdentity else { return }
        loadedIdentity = track.identity
        lines = []
        task?.cancel()
        guard !track.artist.isEmpty else { return }
        task = Task {
            var components = URLComponents(string: "https://lrclib.net/api/get")!
            components.queryItems = [
                URLQueryItem(name: "track_name", value: track.title),
                URLQueryItem(name: "artist_name", value: track.artist),
                URLQueryItem(name: "album_name", value: track.album),
                URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))),
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("Notchy (https://github.com/ByteOneDev/Notchy)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let synced = json["syncedLyrics"] as? String,
                  !Task.isCancelled else { return }
            lines = Self.parse(synced)
        }
    }

    func clear() {
        task?.cancel()
        loadedIdentity = ""
        lines = []
    }

    func line(at position: TimeInterval) -> String? {
        guard !lines.isEmpty else { return nil }
        let index = lines.lastIndex { $0.time <= position + 0.3 }
        return index.map { lines[$0].text }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Parses "[mm:ss.xx] text" lines.
    static func parse(_ lrc: String) -> [Line] {
        lrc.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
            let stamp = line[line.index(after: line.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let minutes = Double(stamp[0]), let seconds = Double(stamp[1]) else { return nil }
            let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            return Line(time: minutes * 60 + seconds, text: text)
        }
    }
}
