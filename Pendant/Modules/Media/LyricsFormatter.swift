import Foundation

/// What is done to lyrics after they are fetched (and before they are cached): simplified → traditional Chinese, phrases that were
/// run together into one line are split, and lines that are not words (an interlude, "na na na") are marked, so the views can show
/// three counting dots for them.
struct LyricsFormatOptions: Equatable, Sendable {
    var traditional = true
    var fillerDots = true
    var splitLines = true

    var signature: String { "\(traditional)\(fillerDots)\(splitLines)" }
}

enum LyricsFormatter {
    typealias State = LyricsStore.State

    static func process(_ state: State, options: LyricsFormatOptions) -> State {
        switch state {
        case let .synced(lines):
            let convert = options.traditional && !usesJapaneseOrKorean(lines.map(\.text))
            return .synced(lines.map { format($0, options: options, convert: convert) })
        case let .plain(lines):
            let convert = options.traditional && !usesJapaneseOrKorean(lines)
            let converted = lines.map { convert ? toTraditional($0) : $0 }
            return .plain(options.splitLines ? converted.flatMap { parts(of: $0) } : converted)
        default:
            return state
        }
    }

    private static func format(_ line: LyricLine, options: LyricsFormatOptions, convert: Bool) -> LyricLine {
        var result = line
        if convert {
            result = LyricLine(
                id: line.id, time: line.time, text: toTraditional(line.text),
                words: line.words.map { LyricWord(start: $0.start, end: $0.end, text: toTraditional($0.text)) }
            )
        }
        result.isInterlude = isInterlude(result.text, fillers: options.fillerDots)
        if !result.isInterlude, options.splitLines, result.words.isEmpty { result.parts = parts(of: result.text) }
        return result
    }

    // MARK: Traditional Chinese

    /// Character-level conversion (ICU "Hans-Hant"); it does not change Taiwan wording ("软件" becomes 軟件, not 軟體).
    static func toTraditional(_ text: String) -> String {
        text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text
    }

    /// Japanese kanji would be "converted" too (掴 → 摑): a song with kana or hangul is left as it is.
    static func usesJapaneseOrKorean(_ lines: [String]) -> Bool {
        lines.contains { line in
            line.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value) }
        }
    }

    // MARK: Interludes and vocal fillers

    private static let musicSymbols = CharacterSet(charactersIn: "♪♫♬♩🎵🎶·•…-–—~～ ")
        .union(.whitespacesAndNewlines).union(.punctuationCharacters)
    private static let filler = try? NSRegularExpression(
        pattern: #"^(na+|la+|o+h*|oh+|a+h+|uh+|hu+h|hey+|ho+|yeah+|yea+|wo+a?h+|whoa+|woo+|m+h*m*|hm+|doo+|da+|ba+|sha+|ay+|eh+)$"#,
        options: .caseInsensitive
    )
    private static let cjkFiller = CharacterSet(charactersIn: "啦啊噢哦嗯呀嘿喔唉哈呼咿")

    /// Empty, only music notes and dashes, or (with `fillers`) only "na na na" / "ooh" style syllables.
    static func isInterlude(_ text: String, fillers: Bool) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.unicodeScalars.allSatisfy({ musicSymbols.contains($0) }) { return true }
        guard fillers else { return false }
        if trimmed.unicodeScalars.allSatisfy({ cjkFiller.contains($0) || musicSymbols.contains($0) }) { return true }
        let tokens = trimmed.split { !$0.isLetter }.map(String.init)
        guard !tokens.isEmpty, let filler else { return false }
        return tokens.allSatisfy { filler.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
    }

    // MARK: Splitting

    /// The line as separate phrases: Chinese lines split at the spaces that mark pauses, English lines that are long split at a
    /// comma / dash / bracket near the middle (or the word nearest to it). Short lines stay whole.
    static func parts(of text: String) -> [String] {
        let line = text.trimmingCharacters(in: .whitespaces)
        if containsHan(line) {
            let pieces = line.split(whereSeparator: { $0 == " " || $0 == "\u{3000}" }).map(String.init)
            return pieces.count > 1 ? mergeShort(pieces, minimum: 2) : [line]
        }
        guard line.count > 36 else { return [line] }
        return splitLatin(line)
    }

    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    /// A piece shorter than `minimum` characters joins its neighbour (a stray particle is not a line of its own).
    private static func mergeShort(_ pieces: [String], minimum: Int) -> [String] {
        var result: [String] = []
        for piece in pieces {
            if piece.count < minimum, let last = result.popLast() { result.append(last + " " + piece) } else { result.append(piece) }
        }
        if result.count > 1, let first = result.first, first.count < minimum {
            result[1] = first + " " + result[1]
            result.removeFirst()
        }
        return result
    }

    private static func splitLatin(_ line: String) -> [String] {
        let chars = Array(line)
        let middle = chars.count / 2
        let range = 8..<(chars.count - 8)
        // Preferred cut: after a comma / dash, or before an opening bracket, closest to the middle and leaving 8+ characters each side.
        let marks = range.filter { index in
            let afterMark = ",;-–".contains(chars[index]) && chars[index + 1] == " "
            return afterMark || (chars[index] == "(" && chars[index - 1] == " ")
        }
        // No punctuation: the space nearest to the middle.
        let candidates = marks.isEmpty ? range.filter { chars[$0] == " " } : marks
        guard let cut = candidates.min(by: { abs($0 - middle) < abs($1 - middle) }) else { return [line] }
        let breakAfter = chars[cut] != "("
        let head = String(chars[...(breakAfter ? cut : cut - 1)]).trimmingCharacters(in: .whitespaces)
        let tail = String(chars[(breakAfter ? cut + 1 : cut)...]).trimmingCharacters(in: .whitespaces)
        return [head, tail].filter { !$0.isEmpty }
    }
}
