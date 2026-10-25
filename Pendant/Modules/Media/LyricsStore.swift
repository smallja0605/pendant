import AppKit
import Observation

/// One line of synchronised lyrics.
struct LyricLine: Equatable, Identifiable, Sendable {
    let id: Int
    let time: TimeInterval
    let text: String
}

/// Lyrics of the current track, asked from the user's list of sources in order (settings › 小工具 › 音樂). Only the title, artist, album
/// and length of the track are sent, and only while the detailed media page is open and "online lyrics" is on.
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

    /// Loads the lyrics for a track (once per track and list of sources).
    func load(for snapshot: PlaybackSnapshot) {
        #if DEBUG
        // PENDANT_DEBUG_LYRICS=1: made-up synchronised lyrics (a line every 5 s) instead of the real lookup.
        if let mode = ProcessInfo.processInfo.environment["PENDANT_DEBUG_LYRICS"] {
            let lines = (0..<60).map { LyricLine(id: $0, time: Double($0) * 5, text: "第 \($0) 句歌詞") }
            state = mode == "plain" ? .plain(lines.map(\.text)) : .synced(lines)
            return
        }
        #endif
        let settings = AppSettings.shared
        let sources = settings.activeLyricsSources(for: snapshot)
        guard !sources.isEmpty else {
            state = .none
            loadedKey = ""
            return
        }
        let key = "\(snapshot.trackKey)|\(sources.map(\.signature).joined(separator: ","))"
        guard key != loadedKey else { return }
        loadedKey = key
        if let cached = cache[key] {
            state = cached
            return
        }
        state = .loading
        task?.cancel()
        task = Task { [weak self] in
            let result = await Self.lookup(sources, snapshot)
            guard !Task.isCancelled, let self, loadedKey == key else { return }
            cache[key] = result
            state = result
        }
    }

    /// The first source with synchronised lyrics wins; with none, the first plain text found (in list order).
    private static func lookup(_ sources: [LyricsSourceItem], _ snapshot: PlaybackSnapshot) async -> State {
        var plain: State?
        for source in sources {
            if Task.isCancelled { return .none }
            let found = await LyricsFetcher.fetch(source, snapshot: snapshot)
            switch found {
            case .synced: return found
            case .plain: if plain == nil { plain = found }
            default: break
            }
        }
        return plain ?? .none
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
