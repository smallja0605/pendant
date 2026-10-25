import Foundation
import Testing
@testable import Pendant

struct LyricsWordTests {
    @Test func enhancedLRCGivesWordTiming() {
        let lines = LyricsStore.parseLRC("[00:12.00] <00:12.00>one <00:12.40>two<00:12.90>\n[00:20.00] plain line")
        #expect(lines.count == 2)
        #expect(lines[0].text == "one two")
        #expect(lines[0].words.map(\.text) == ["one ", "two"])
        #expect(lines[0].words[1].start == 12.4)
        #expect(lines[0].words[1].end == 12.9)
        #expect(lines[1].words.isEmpty)
    }

    @Test func neteaseWordFormat() {
        let lines = LyricsStore.parseYRC("[12340,3200](12340,500,0)夢(12840,300,0)を(13140,800,0)掴んで")
        #expect(lines.count == 1)
        #expect(lines[0].time == 12.34)
        #expect(lines[0].words.map(\.text) == ["夢", "を", "掴んで"])
        #expect(lines[0].words[2].end == 13.94)
    }

    @Test func richsyncGivesWordsAndLines() {
        let items: [[String: Any]] = [
            ["ts": 1.0, "te": 3.0, "x": "ab cd", "l": [["c": "ab ", "o": 0.0], ["c": "cd", "o": 1.0]]],
        ]
        let lines = LyricsFetcher.parseRichsync(items)
        #expect(lines.count == 1)
        #expect(lines[0].words[0].end == 2.0)
        #expect(lines[0].words[1].end == 3.0)
    }

    @Test func fillGrowsWithPosition() {
        let word = LyricWord(start: 10, end: 12, text: "x")
        #expect(LyricsLineProgress.value(of: word, at: 9) == 0)
        #expect(LyricsLineProgress.value(of: word, at: 11) == 0.5)
        #expect(LyricsLineProgress.value(of: word, at: 13) == 1)
    }
}
