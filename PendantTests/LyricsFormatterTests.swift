import Testing
@testable import Pendant

struct LyricsFormatterTests {
    @Test func simplifiedBecomesTraditional() {
        #expect(LyricsFormatter.toTraditional("后来 我们 软件 里面 发现") == "後來 我們 軟件 裡面 發現")
    }

    @Test func japaneseAndKoreanAreLeftAlone() {
        #expect(LyricsFormatter.usesJapaneseOrKorean(["夢を掴んで離さないで"]))
        #expect(LyricsFormatter.usesJapaneseOrKorean(["사랑해"]))
        #expect(!LyricsFormatter.usesJapaneseOrKorean(["后来 我们"]))
        let state = LyricsFormatter.process(.plain(["夢を掴んで"]), options: LyricsFormatOptions())
        #expect(state == .plain(["夢を掴んで"]))
    }

    @Test func interludesAndFillers() {
        for text in ["", "♪", " ♪ ♫ ", "(Na-na, na, na, na-na, na, na)", "Oh-oh-oh", "Ooh, ooh", "啦啦啦"] {
            #expect(LyricsFormatter.isInterlude(text, fillers: true), "\(text)")
        }
        #expect(!LyricsFormatter.isInterlude("Nana was here", fillers: true))
        #expect(!LyricsFormatter.isInterlude("Oh baby", fillers: true))
        #expect(LyricsFormatter.isInterlude("Oh-oh-oh", fillers: false) == false)
        #expect(LyricsFormatter.isInterlude("♪", fillers: false))
    }

    @Test func chineseSplitsAtSpaces() {
        #expect(LyricsFormatter.parts(of: "春天的風 輕輕吹過窗前") == ["春天的風", "輕輕吹過窗前"])
        #expect(LyricsFormatter.parts(of: "你好") == ["你好"])
        // a one-character piece joins its neighbour
        #expect(LyricsFormatter.parts(of: "我 愛你 很久很久") == ["我 愛你", "很久很久"])
    }

    @Test func longEnglishSplitsNearTheMiddle() {
        let parts = LyricsFormatter.parts(of: "The river runs slowly past the old town, we walk along it until the light is gone")
        #expect(parts == ["The river runs slowly past the old town,", "we walk along it until the light is gone"])
        #expect(LyricsFormatter.parts(of: "A short line, stays whole") == ["A short line, stays whole"])
        let plainLong = LyricsFormatter.parts(of: "this line has no punctuation at all but is really quite long")
        #expect(plainLong.count == 2)
    }
}
