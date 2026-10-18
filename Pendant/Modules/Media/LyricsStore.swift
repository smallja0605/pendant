import Foundation
import Observation

/// One line of synchronised lyrics.
struct LyricLine: Equatable, Identifiable, Sendable {
    let id: Int
    let time: TimeInterval
    let text: String
}

/// Lyrics of the current track from lrclib.net (a free, open lyrics service). Only the title, artist, album and length of the
/// track are sent, and only while the detailed media page is open and "online lyrics" is on.
@MainActor
@Observable
final class LyricsStore {
    static let shared = LyricsStore()

    enum State: Equatable {
        case idle
        case loading
        case none
        case plain([String])
        case synced([LyricLine])
    }

    private(set) var state = State.idle
    @ObservationIgnored private var loadedKey = ""
    @ObservationIgnored private var cache: [String: State] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Loads the lyrics for a track (once per track).
    func load(for snapshot: PlaybackSnapshot) {
        guard AppSettings.shared.onlineLyrics else {
            state = .idle
            loadedKey = ""
            return
        }
        guard snapshot.trackKey != loadedKey else { return }
        loadedKey = snapshot.trackKey
        if let cached = cache[snapshot.trackKey] {
            state = cached
            return
        }
        state = .loading
        task?.cancel()
        let key = snapshot.trackKey
        task = Task { [weak self] in
            let result = await Self.fetch(
                title: snapshot.title, artist: snapshot.artist, album: snapshot.album, duration: snapshot.duration
            )
            guard !Task.isCancelled, let self, loadedKey == key else { return }
            cache[key] = result
            state = result
        }
    }

    // MARK: Network

    private static func fetch(title: String, artist: String, album: String, duration: TimeInterval) async -> State {
        guard !title.isEmpty else { return .none }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "lrclib.net"
        components.path = "/api/get"
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
        ]
        if duration > 0 { components.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        if let found = await request(components.url), let state = parse(found) { return state }
        // Not an exact match: take the best hit of a search.
        var search = URLComponents()
        search.scheme = "https"
        search.host = "lrclib.net"
        search.path = "/api/search"
        search.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if let data = await requestData(search.url),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for item in list { if let state = parse(item) { return state } }
        }
        return .none
    }

    private static func requestData(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Pendant (https://github.com/smallja0605/pendant)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private static func request(_ url: URL?) async -> [String: Any]? {
        guard let data = await requestData(url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func parse(_ item: [String: Any]) -> State? {
        if let synced = item["syncedLyrics"] as? String {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = item["plainLyrics"] as? String {
            let lines = plain.split(whereSeparator: \.isNewline).map(String.init)
            if !lines.isEmpty { return .plain(lines) }
        }
        return nil
    }

    /// "[01:23.45] words" lines; several time tags per line are allowed, empty lines are kept as pauses.
    nonisolated static func parseLRC(_ text: String) -> [LyricLine] {
        let tag = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        var result: [(TimeInterval, String)] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let range = NSRange(line.startIndex..., in: line)
            let matches = tag?.matches(in: line, range: range) ?? []
            guard let last = matches.last, let lastRange = Range(last.range, in: line) else { continue }
            let words = line[lastRange.upperBound...].trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Range(match.range(at: 1), in: line).flatMap({ Double(line[$0]) }),
                      let seconds = Range(match.range(at: 2), in: line).flatMap({ Double(line[$0]) }) else { continue }
                result.append((minutes * 60 + seconds, words))
            }
        }
        return result.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
