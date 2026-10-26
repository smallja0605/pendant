import AppKit
import Observation

/// One line of synchronised lyrics.
struct LyricLine: Equatable, Identifiable, Sendable {
    let id: Int
    let time: TimeInterval
    let text: String
    /// Word-by-word timing, when the source has it (empty otherwise).
    var words: [LyricWord] = []
}

/// One word (or character) of a line and when it is sung, in seconds of the song.
struct LyricWord: Equatable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
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
            let lines = (0..<60).map {
                LyricLine(id: $0, time: Double($0) * 5, text: mode == "long" ? "這是一句比較長的歌詞，用來測試膠囊會不會跟著變寬 \($0)" : "第 \($0) 句歌詞")
            }
            if mode == "words" {
                // Word-timed: each line is five words, one every second.
                state = .synced((0..<30).map { index in
                    let start = Double(index) * 5
                    let words = (0..<5).map { LyricWord(start: start + Double($0), end: start + Double($0) + 0.9, text: "詞\($0) ") }
                    return LyricLine(id: index, time: start, text: words.map(\.text).joined(), words: words)
                })
                return
            }
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

    /// "[01:23.45] words" lines; several time tags per line are allowed, empty lines are kept as pauses. Words with their own
    /// tags (`[00:12.00] <00:12.00>one <00:12.40>two <00:12.90>`, "enhanced LRC") also give the line its word timing.
    nonisolated static func parseLRC(_ text: String) -> [LyricLine] {
        let tag = try? NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        var result: [LyricLine] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let range = NSRange(line.startIndex..., in: line)
            let matches = tag?.matches(in: line, range: range) ?? []
            guard let last = matches.last, let lastRange = Range(last.range, in: line) else { continue }
            let body = String(line[lastRange.upperBound...])
            let (words, plain) = parseWordTags(body)
            let spoken = words.isEmpty ? body.trimmingCharacters(in: .whitespaces) : plain
            for match in matches {
                guard let minutes = Range(match.range(at: 1), in: line).flatMap({ Double(line[$0]) }),
                      let seconds = Range(match.range(at: 2), in: line).flatMap({ Double(line[$0]) }) else { continue }
                result.append(LyricLine(id: 0, time: minutes * 60 + seconds, text: spoken, words: words))
            }
        }
        return result.sorted { $0.time < $1.time }.enumerated().map {
            LyricLine(id: $0.offset, time: $0.element.time, text: $0.element.text, words: $0.element.words)
        }
    }

    /// `<00:12.00>one <00:12.40>two <00:12.90>`: each tag is when the text after it starts; the last (empty) one ends the line.
    nonisolated private static func parseWordTags(_ body: String) -> (words: [LyricWord], text: String) {
        guard let tag = try? NSRegularExpression(pattern: #"<(\d+):(\d+(?:\.\d+)?)>"#) else { return ([], body) }
        let all = NSRange(body.startIndex..., in: body)
        let matches = tag.matches(in: body, range: all)
        guard matches.count >= 2 else { return ([], body) }
        var marks: [(time: TimeInterval, text: String)] = []
        for (index, match) in matches.enumerated() {
            guard let minutes = Range(match.range(at: 1), in: body).flatMap({ Double(body[$0]) }),
                  let seconds = Range(match.range(at: 2), in: body).flatMap({ Double(body[$0]) }),
                  let whole = Range(match.range, in: body) else { return ([], body) }
            let end = index + 1 < matches.count ? Range(matches[index + 1].range, in: body)?.lowerBound ?? body.endIndex : body.endIndex
            marks.append((minutes * 60 + seconds, String(body[whole.upperBound..<end])))
        }
        var words: [LyricWord] = []
        for index in marks.indices where !marks[index].text.isEmpty {
            let end = index + 1 < marks.count ? marks[index + 1].time : marks[index].time
            words.append(LyricWord(start: marks[index].time, end: max(end, marks[index].time), text: marks[index].text))
        }
        return (words, words.map(\.text).joined().trimmingCharacters(in: .whitespaces))
    }

    /// NetEase's word-timed format: `[12340,3200](12340,500,0)one(12840,300,0)two` (milliseconds; line start and length, then each word).
    nonisolated static func parseYRC(_ text: String) -> [LyricLine] {
        guard let head = try? NSRegularExpression(pattern: #"^\[(\d+),(\d+)\]"#),
              let word = try? NSRegularExpression(pattern: #"\((\d+),(\d+),\d+\)"#) else { return [] }
        var lines: [LyricLine] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard let first = head.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let start = Range(first.range(at: 1), in: line).flatMap({ Double(line[$0]) }),
                  let headEnd = Range(first.range, in: line)?.upperBound else { continue }
            let rest = String(line[headEnd...])
            let found = word.matches(in: rest, range: NSRange(rest.startIndex..., in: rest))
            var words: [LyricWord] = []
            for (index, match) in found.enumerated() {
                guard let begin = Range(match.range(at: 1), in: rest).flatMap({ Double(rest[$0]) }),
                      let length = Range(match.range(at: 2), in: rest).flatMap({ Double(rest[$0]) }),
                      let whole = Range(match.range, in: rest) else { continue }
                let end = index + 1 < found.count ? Range(found[index + 1].range, in: rest)?.lowerBound ?? rest.endIndex : rest.endIndex
                let spoken = String(rest[whole.upperBound..<end])
                if !spoken.isEmpty { words.append(LyricWord(start: begin / 1000, end: (begin + length) / 1000, text: spoken)) }
            }
            guard !words.isEmpty else { continue }
            lines.append(LyricLine(
                id: lines.count, time: start / 1000, text: words.map(\.text).joined().trimmingCharacters(in: .whitespaces), words: words
            ))
        }
        return lines
    }
}
