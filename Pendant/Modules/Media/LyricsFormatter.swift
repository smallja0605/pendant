import Foundation

/// What is done to lyrics after they are fetched (and before they are cached): simplified → traditional Chinese, phrases that were
/// run together into one line are split, and lines that are not words (an interlude, "na na na") are marked, so the views can show
/// three counting dots for them.
struct LyricsFormatOptions: Equatable, Sendable {
    var traditional = true
    var fillerDots = true
    var splitLines = true
    var hideRomanization = true

    var signature: String { "\(traditional)\(fillerDots)\(splitLines)\(hideRomanization)" }
}

enum LyricsFormatter {
    typealias State = LyricsStore.State

    static func process(_ state: State, options: LyricsFormatOptions) -> State {
        switch state {
        case let .synced(source):
            let lines = options.hideRomanization ? dropRomanization(source) : source
            guard !lines.isEmpty else { return .none } // it was only romanisation: the next source gets its turn
            let convert = options.traditional && !usesJapaneseOrKorean(lines.map(\.text))
            return .synced(lines.enumerated().map { format($1, id: $0, options: options, convert: convert) })
        case let .plain(source):
            let lines = options.hideRomanization ? source.filter { !isRomanizedLine($0, song: source) } : source
            guard lines.contains(where: { !$0.isEmpty }) else { return .none }
            let convert = options.traditional && !usesJapaneseOrKorean(lines)
            let converted = lines.map { convert ? toTraditional($0) : $0 }
            return .plain(options.splitLines ? converted.flatMap { parts(of: $0) } : converted)
        default:
            return state
        }
    }

    private static func format(_ line: LyricLine, id: Int, options: LyricsFormatOptions, convert: Bool) -> LyricLine {
        var result = line
        if convert {
            result = LyricLine(
                id: id, time: line.time, text: toTraditional(line.text),
                words: line.words.map { LyricWord(start: $0.start, end: $0.end, text: toTraditional($0.text)) }
            )
        }
        result = LyricLine(id: id, time: result.time, text: result.text, words: result.words)
        result.isInterlude = isInterlude(result.text, fillers: options.fillerDots)
        if !result.isInterlude, options.splitLines, result.words.isEmpty { result.parts = parts(of: result.text) }
        return result
    }

    // MARK: Romanisation (rōmaji, pinyin)

    /// Lines that only spell the sound of the words in Latin letters: dropped. A line is one when it is only Latin letters and
    /// (a) another line of the same time holds the words themselves, or (b) in a Japanese song it reads as rōmaji, or (c) in a
    /// Chinese song it reads as pinyin.
    static func dropRomanization(_ lines: [LyricLine]) -> [LyricLine] {
        let texts = lines.map(\.text)
        // A file with only rōmaji (six lines or more, nearly all of them): there is no song text to keep.
        let romaji = texts.filter { matches($0, pattern: romajiSyllables, minimumWords: 2) }.count
        if lines.count >= 6, romaji * 100 >= lines.count * 85 { return [] }
        return lines.filter { line in
            guard isLatinOnly(line.text) else { return true }
            let sameTimeHasWords = lines.contains { $0.id != line.id && abs($0.time - line.time) < 0.35 && !isLatinOnly($0.text) }
            return !(sameTimeHasWords || isRomanizedLine(line.text, song: texts))
        }
    }

    /// Reads as rōmaji (in a song with kana) or pinyin (in a song with Chinese characters but no kana).
    static func isRomanizedLine(_ text: String, song: [String]) -> Bool {
        guard isLatinOnly(text) else { return false }
        let hasKana = song.contains { $0.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) } }
        let hasHan = song.contains(where: containsHan)
        if hasKana { return matches(text, pattern: romajiSyllables, minimumWords: 2) }
        if hasHan { return matches(text, pattern: pinyinSyllables, minimumWords: 3) }
        return false
    }

    private static let romajiSyllables = try? NSRegularExpression(
        pattern: #"^(?:(?:ky|gy|ny|hy|by|py|my|ry|sh|ch|ts|dz|[kgsztdnhbpmrwyfj])?[aiueo]|n(?![aiueoy]))+$"#
    )
    private static let pinyinSyllables = try? NSRegularExpression(
        pattern: #"^(?:zh|ch|sh|[bpmfdtnlgkhjqxrzcsyw])?[aeiouv]+(?:ng|n|r)?$"#
    )

    /// Every word (at least `minimumWords`, 90 % of them) fits the syllable pattern; doubled consonants (natte) count once.
    private static func matches(_ text: String, pattern: NSRegularExpression?, minimumWords: Int) -> Bool {
        guard let pattern else { return false }
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: #"([kstpgdbzjcfhmr])\1"#, with: "$1", options: .regularExpression)
        let words = folded.split { !$0.isLetter }.map(String.init)
        guard words.count >= minimumWords else { return false }
        let fitting = words.filter { pattern.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
        return Double(fitting.count) >= 0.9 * Double(words.count)
    }

    /// Only Latin letters (accents allowed), spaces and punctuation, at least one letter: no kana, no Chinese characters.
    static func isLatinOnly(_ text: String) -> Bool {
        var letters = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            guard scalar.value < 0x250 else { return false }
            letters += 1
        }
        return letters > 0
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
