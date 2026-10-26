import AppKit
import Foundation
import Security

/// One place the lyrics can come from. The settings keep an ordered list of these: the store asks them in order, skipping disabled ones.
struct LyricsSourceItem: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case player, lrclib, netease, musixmatch, custom }
    /// How a custom source answers: the body is the lyrics (LRC with time tags, or plain text), or JSON holding them at `jsonPath`.
    enum Format: String, Codable, CaseIterable, Sendable { case text, json }

    var id: String
    var kind: Kind
    var name: String
    var enabled: Bool
    /// Custom sources only: an https address with `{title}` `{artist}` `{album}` `{duration}` (seconds) in it.
    var urlTemplate = ""
    var format = Format.text
    /// Dotted path into the JSON answer (`data.lyrics.lrc`, a number picks from a list: `result.0.lyric`).
    var jsonPath = ""

    var isNetwork: Bool { kind != .player }
    /// Needs something typed in before it can work (an API key, an address).
    var needsSetup: Bool { kind == .musixmatch || kind == .custom }

    /// Changes when anything that affects the lookup changes (the store looks again then).
    var signature: String { "\(id):\(urlTemplate):\(format.rawValue):\(jsonPath)" }

    static let defaults: [LyricsSourceItem] = [
        .init(id: "lrclib", kind: .lrclib, name: "lrclib.net", enabled: true),
        .init(id: "player", kind: .player, name: "Apple Music", enabled: true),
        .init(id: "netease", kind: .netease, name: "網易雲音樂", enabled: false),
        .init(id: "musixmatch", kind: .musixmatch, name: "Musixmatch", enabled: false),
    ]

    /// What the stored list becomes after an update: sources added in newer versions appear at the end, unknown built-ins are dropped.
    static func merged(_ stored: [LyricsSourceItem]) -> [LyricsSourceItem] {
        let builtinIDs = Set(defaults.map(\.id))
        var result = stored.filter { $0.kind == .custom || builtinIDs.contains($0.id) }
        for item in defaults where !result.contains(where: { $0.id == item.id }) { result.append(item) }
        return result
    }
}

/// The lookups themselves. Every one returns `.none` for "nothing found" and never throws.
enum LyricsFetcher {
    typealias State = LyricsStore.State

    static func fetch(_ source: LyricsSourceItem, snapshot: PlaybackSnapshot) async -> State {
        guard !snapshot.title.isEmpty else { return .none }
        switch source.kind {
        case .player: return await playerLyrics(snapshot).map { .plain($0) } ?? .none
        case .lrclib: return await lrclib(snapshot)
        case .netease: return await netease(snapshot)
        case .musixmatch: return await musixmatch(snapshot)
        case .custom: return await custom(source, snapshot)
        }
    }

    // MARK: Player

    /// The lyrics Apple Music itself holds for the current track (plain text, no timing), if it is running and has some.
    private static func playerLyrics(_ snapshot: PlaybackSnapshot) async -> [String]? {
        guard snapshot.source == .appleMusic else { return nil }
        let musicApps = NSRunningApplication.runningApplications(withBundleIdentifier: MediaSourceID.appleMusic.bundleIdentifier)
        guard !musicApps.isEmpty else { return nil }
        let result = await AppleScriptRunner.shared.run("tell application \"Music\" to return lyrics of current track")
        guard case let .success(value) = result, let text = value.asString else { return nil }
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.contains { !$0.isEmpty } ? lines : nil
    }

    // MARK: lrclib.net

    private static func lrclib(_ snapshot: PlaybackSnapshot) async -> State {
        let (title, artist, duration) = (snapshot.title, snapshot.artist, snapshot.duration)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "lrclib.net"
        components.path = "/api/get"
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: snapshot.album),
        ]
        if duration > 0 { components.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        // An exact match may hold only plain text: keep it, but look for a synchronised version of the same track first.
        var plain: State?
        if let found = await requestJSON(components.url) as? [String: Any], let state = parse(found) {
            if case .synced = state { return state }
            plain = state
        }
        var search = URLComponents()
        search.scheme = "https"
        search.host = "lrclib.net"
        search.path = "/api/search"
        search.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if let list = await requestJSON(search.url) as? [[String: Any]] {
            // The synchronised hit whose length is closest to the track's (a different cut of the song would drift).
            let candidates = list.filter { ($0["syncedLyrics"] as? String)?.isEmpty == false }
            let best = candidates.min { lhs, rhs in
                abs((lhs["duration"] as? Double ?? 0) - duration) < abs((rhs["duration"] as? Double ?? 0) - duration)
            }
            if let best, duration <= 0 || abs((best["duration"] as? Double ?? 0) - duration) <= 5, let state = parse(best) { return state }
            if plain == nil { for item in list { if let state = parse(item) { plain = state; break } } }
        }
        return plain ?? .none
    }

    private static func parse(_ item: [String: Any]) -> State? {
        if let synced = item["syncedLyrics"] as? String {
            let lines = LyricsStore.parseLRC(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = item["plainLyrics"] as? String { return state(fromText: plain) }
        return nil
    }

    // MARK: NetEase Cloud Music

    /// The public search and lyric endpoints of music.163.com (no key). Picks the hit whose length is closest to the track's.
    private static func netease(_ snapshot: PlaybackSnapshot) async -> State {
        var search = URLComponents(string: "https://music.163.com/api/search/get/web")
        search?.queryItems = [
            URLQueryItem(name: "s", value: "\(snapshot.title) \(snapshot.artist)"), URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"), URLQueryItem(name: "limit", value: "8"),
        ]
        guard let root = await requestJSON(search?.url) as? [String: Any],
              let songs = (root["result"] as? [String: Any])?["songs"] as? [[String: Any]], !songs.isEmpty else { return .none }
        let target = snapshot.duration * 1000
        let best = target > 0
            ? songs.min { abs(($0["duration"] as? Double ?? 0) - target) < abs(($1["duration"] as? Double ?? 0) - target) }
            : songs.first
        if let best, target > 0, abs((best["duration"] as? Double ?? 0) - target) > 6000 { return .none }
        guard let id = best?["id"] as? Int else { return .none }
        var lyric = URLComponents(string: "https://music.163.com/api/song/lyric")
        lyric?.queryItems = [
            URLQueryItem(name: "id", value: String(id)), URLQueryItem(name: "lv", value: "1"),
            URLQueryItem(name: "kv", value: "0"), URLQueryItem(name: "tv", value: "0"),
        ]
        guard let answer = await requestJSON(lyric?.url) as? [String: Any],
              let text = (answer["lrc"] as? [String: Any])?["lyric"] as? String else { return .none }
        return state(fromText: text)
    }

    // MARK: Musixmatch

    /// Musixmatch's official API: needs the user's own key (in the Keychain). The free plan returns only part of a song, as plain text.
    private static func musixmatch(_ snapshot: PlaybackSnapshot) async -> State {
        guard let key = LyricsKeychain.read(account: "musixmatch"), !key.isEmpty else { return .none }
        if let timed = await musixmatchRichsync(snapshot, key: key) { return timed }
        var components = URLComponents(string: "https://api.musixmatch.com/ws/1.1/matcher.lyrics.get")
        components?.queryItems = [
            URLQueryItem(name: "q_track", value: snapshot.title), URLQueryItem(name: "q_artist", value: snapshot.artist),
            URLQueryItem(name: "apikey", value: key),
        ]
        guard let root = await requestJSON(components?.url) as? [String: Any],
              let body = (root["message"] as? [String: Any])?["body"] as? [String: Any],
              var text = (body["lyrics"] as? [String: Any])?["lyrics_body"] as? String else { return .none }
        // The answer ends with a licence line after a row of stars.
        if let stars = text.range(of: "*******") { text = String(text[..<stars.lowerBound]) }
        return state(fromText: text)
    }

    /// Word-timed lyrics (Musixmatch "richsync"): only plans that include it answer; any other answer falls back to the plain lyrics.
    private static func musixmatchRichsync(_ snapshot: PlaybackSnapshot, key: String) async -> State? {
        var components = URLComponents(string: "https://api.musixmatch.com/ws/1.1/track.richsync.get")
        var query = [
            URLQueryItem(name: "q_track", value: snapshot.title), URLQueryItem(name: "q_artist", value: snapshot.artist),
            URLQueryItem(name: "apikey", value: key),
        ]
        if snapshot.duration > 0 { query.append(URLQueryItem(name: "f_richsync_length", value: String(Int(snapshot.duration.rounded())))) }
        components?.queryItems = query
        guard let root = await requestJSON(components?.url) as? [String: Any],
              let body = (root["message"] as? [String: Any])?["body"] as? [String: Any],
              let richsync = (body["richsync"] as? [String: Any])?["richsync_body"] as? String,
              let data = richsync.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        let lines = parseRichsync(items)
        return lines.count >= 2 ? .synced(lines) : nil
    }

    /// `[{ts, te, x: "line", l: [{c: "word", o: offset}]}]`, seconds.
    static func parseRichsync(_ items: [[String: Any]]) -> [LyricLine] {
        var lines: [LyricLine] = []
        for item in items {
            guard let start = item["ts"] as? Double, let end = item["te"] as? Double,
                  let parts = item["l"] as? [[String: Any]] else { continue }
            var words: [LyricWord] = []
            for (index, part) in parts.enumerated() {
                guard let text = part["c"] as? String, let offset = part["o"] as? Double else { continue }
                let next = index + 1 < parts.count ? (parts[index + 1]["o"] as? Double).map { start + $0 } : nil
                words.append(LyricWord(start: start + offset, end: next ?? end, text: text))
            }
            let line = (item["x"] as? String) ?? words.map(\.text).joined()
            lines.append(LyricLine(id: lines.count, time: start, text: line.trimmingCharacters(in: .whitespaces), words: words))
        }
        return lines
    }

    // MARK: Custom

    private static func custom(_ source: LyricsSourceItem, _ snapshot: PlaybackSnapshot) async -> State {
        guard let url = expand(source.urlTemplate, snapshot), url.scheme == "https" else { return .none }
        guard let data = await requestData(url) else { return .none }
        switch source.format {
        case .text:
            guard let text = String(bytes: data, encoding: .utf8) else { return .none }
            return state(fromText: text)
        case .json:
            guard let root = try? JSONSerialization.jsonObject(with: data),
                  let text = value(in: root, path: source.jsonPath) as? String else { return .none }
            return state(fromText: text)
        }
    }

    /// The template with the track's details put in (percent-encoded).
    static func expand(_ template: String, _ snapshot: PlaybackSnapshot) -> URL? {
        func encoded(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? "" }
        let filled = template
            .replacingOccurrences(of: "{title}", with: encoded(snapshot.title))
            .replacingOccurrences(of: "{artist}", with: encoded(snapshot.artist))
            .replacingOccurrences(of: "{album}", with: encoded(snapshot.album))
            .replacingOccurrences(of: "{duration}", with: String(Int(snapshot.duration.rounded())))
        return URL(string: filled)
    }

    /// `a.b.0.c`: keys of objects, positions in lists.
    static func value(in root: Any, path: String) -> Any? {
        var current: Any? = root
        for part in path.split(separator: ".").map(String.init) {
            if let object = current as? [String: Any] {
                current = object[part]
            } else if let list = current as? [Any], let index = Int(part), list.indices.contains(index) {
                current = list[index]
            } else {
                return nil
            }
        }
        return current
    }

    // MARK: Shared

    /// Text that holds time tags is synchronised lyrics, anything else plain lines.
    static func state(fromText text: String) -> State {
        if text.range(of: #"^\[\d+,\d+\]\("#, options: .regularExpression) != nil
            || text.range(of: #"\n\[\d+,\d+\]\("#, options: .regularExpression) != nil {
            let timed = LyricsStore.parseYRC(text)
            if timed.count >= 2 { return .synced(timed) }
        }
        let lines = LyricsStore.parseLRC(text)
        if lines.count >= 2 { return .synced(lines) }
        let plain = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return plain.contains { !$0.isEmpty } ? .plain(plain) : .none
    }

    /// The most a lyrics answer may weigh: a source that sends more (by mistake or to exhaust memory) counts as nothing.
    static let maxAnswerBytes = 2 * 1024 * 1024

    private static func requestData(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Pendant (https://github.com/smallja0605/pendant)", forHTTPHeaderField: "User-Agent")
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              response.expectedContentLength <= Int64(maxAnswerBytes) else { return nil }
        // The declared length can be missing or wrong: the body is read with the same cap.
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxAnswerBytes { return nil }
            }
        } catch {
            return nil
        }
        return data
    }

    private static func requestJSON(_ url: URL?) async -> Any? {
        guard let data = await requestData(url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+#?/")
        return set
    }()
}

/// API keys typed into the settings live in the Keychain, never in the preferences file or the code.
enum LyricsKeychain {
    private static let service = "com.smallja.pendant.lyrics"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
