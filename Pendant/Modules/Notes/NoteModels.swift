import Foundation

/// One note: plain text with light Markdown (`**bold**`, `- ` lists, `- [ ]` / `- [x]` to-dos).
struct Note: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var text = ""
    var pinned = false
    var updatedAt = Date()

    /// First non-empty line without Markdown markers: the name shown in the list.
    var title: String { NoteMarkdown.title(of: text) }
}

/// Pure text helpers for notes (no UI, unit-tested).
enum NoteMarkdown {
    static func title(of text: String, limit: Int = 40) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            for prefix in ["- [ ] ", "- [x] ", "- [X] ", "- ", "# "] where trimmed.hasPrefix(prefix) {
                trimmed = String(trimmed.dropFirst(prefix.count))
                break
            }
            trimmed = trimmed.replacingOccurrences(of: "**", with: "")
            if !trimmed.isEmpty { return String(trimmed.prefix(limit)) }
        }
        return ""
    }

    /// Pinned first, then most recently edited.
    static func sorted(_ notes: [Note]) -> [Note] {
        notes.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    // MARK: Lists and to-dos

    /// Prefix a new line should start with after Return on `line` (`- `, `- [ ] `), nil if it is no list line.
    static func continuation(of line: String) -> String? {
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        let body = line.dropFirst(indent.count)
        if body.hasPrefix("- [ ] ") || body.hasPrefix("- [x] ") || body.hasPrefix("- [X] ") { return indent + "- [ ] " }
        if body.hasPrefix("- ") { return indent + "- " }
        return nil
    }

    /// A list line with nothing after its marker: Return on it ends the list instead of continuing it.
    static func isEmptyListLine(_ line: String) -> Bool {
        let body = line.trimmingCharacters(in: .whitespaces)
        return body == "-" || body == "- [ ]" || body == "- [x]" || body == "- [X]"
    }

    /// Range (in UTF-16 offsets of `line`) of the `[ ]` / `[x]` token if the line is a to-do.
    static func checkboxRange(in line: String) -> Range<Int>? {
        let units = Array(line.utf16)
        var index = 0
        while index < units.count, units[index] == 0x20 || units[index] == 0x09 { index += 1 }
        let pattern = Array("- [".utf16)
        guard index + 5 <= units.count, Array(units[index..<index + 3]) == pattern,
              [0x20, 0x78, 0x58].contains(units[index + 3]), units[index + 4] == 0x5D else { return nil }
        return (index + 2)..<(index + 5)
    }

    /// Flips `[ ]` ↔ `[x]` on the line.
    static func togglingCheckbox(in line: String) -> String {
        guard let range = checkboxRange(in: line) else { return line }
        var units = Array(line.utf16)
        units[range.lowerBound + 1] = units[range.lowerBound + 1] == 0x20 ? 0x78 : 0x20
        return String(decoding: units, as: UTF16.self)
    }

    static func isChecked(_ line: String) -> Bool {
        guard let range = checkboxRange(in: line) else { return false }
        let mark = Array(line.utf16)[range.lowerBound + 1]
        return mark == 0x78 || mark == 0x58
    }

    // MARK: Formatting commands

    /// Wraps `selection` in `**`; an already wrapped selection is unwrapped.
    static func toggledBold(_ selection: String) -> String {
        if selection.count >= 4, selection.hasPrefix("**"), selection.hasSuffix("**") { return String(selection.dropFirst(2).dropLast(2)) }
        return "**" + (selection.isEmpty ? "粗體" : selection) + "**"
    }

    /// Adds / removes a line prefix on every line of `text` (list or to-do commands).
    static func togglingPrefix(_ prefix: String, on text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let allHave = lines.allSatisfy { $0.hasPrefix(prefix) }
        return lines.map { allHave ? String($0.dropFirst(prefix.count)) : prefix + $0 }.joined(separator: "\n")
    }
}
