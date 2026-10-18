import Testing
@testable import Pendant

struct LyricsParseTests {
    @Test func parsesTimedLinesInOrder() {
        let lines = LyricsStore.parseLRC("[00:12.50] second\n[00:01.00] first\n[01:02.25] third")
        #expect(lines.map(\.text) == ["first", "second", "third"])
        #expect(lines.map(\.time) == [1.0, 12.5, 62.25])
        #expect(lines.map(\.id) == [0, 1, 2])
    }

    @Test func severalTagsShareTheirWords() {
        let lines = LyricsStore.parseLRC("[00:10.00][00:40.00] chorus")
        #expect(lines.map(\.time) == [10, 40])
        #expect(lines.allSatisfy { $0.text == "chorus" })
    }

    @Test func ignoresLinesWithoutTimeTags() {
        #expect(LyricsStore.parseLRC("[ar: someone]\njust words").isEmpty)
    }
}
