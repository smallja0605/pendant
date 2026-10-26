import Testing
@testable import Pendant

struct LyricsRomanizationTests {
    private func line(_ id: Int, _ time: Double, _ text: String) -> LyricLine { LyricLine(id: id, time: time, text: text) }

    @Test func romajiLinesInAJapaneseSongAreDropped() {
        let lines = [line(0, 10, "春の風が吹く"), line(1, 14, "Haru no kaze ga fuku"), line(2, 18, "星の下で歌う"), line(3, 22, "Hoshi no shita de utau")]
        #expect(LyricsFormatter.dropRomanization(lines).map(\.text) == ["春の風が吹く", "星の下で歌う"])
    }

    @Test func aLineAtTheSameTimeAsTheWordsIsRomanisation() {
        let lines = [line(0, 10, "春天的風"), line(1, 10.1, "Whatever it says"), line(2, 14, "I am here")]
        #expect(LyricsFormatter.dropRomanization(lines).map(\.text) == ["春天的風", "I am here"])
    }

    @Test func pinyinInAChineseSong() {
        let lines = [line(0, 10, "春天的風輕輕吹過"), line(1, 14, "chun tian de feng qing qing chui guo"), line(2, 18, "I can do it all night")]
        #expect(LyricsFormatter.dropRomanization(lines).map(\.text) == ["春天的風輕輕吹過", "I can do it all night"])
    }

    @Test func englishSongsAreUntouched() {
        let lines = [line(0, 10, "We are the one, no more to be"), line(1, 14, "Nobody knows my name")]
        #expect(LyricsFormatter.dropRomanization(lines).count == 2)
    }

    @Test func aFileThatIsOnlyRomajiMeansNoLyrics() {
        let texts = ["Haru no kaze ga fuku", "Hoshi no shita de utau", "Sora wa tooku ni aru", "Kimi no koe ga kikoeru",
                     "Mado no soto de yuki ga furu", "Yume o mite iru"]
        let state = LyricsFormatter.process(.synced(texts.enumerated().map { LyricLine(id: $0.offset, time: Double($0.offset) * 4, text: $0.element) }),
                                            options: LyricsFormatOptions())
        #expect(state == .none)
        // a short English file that happens to read like rōmaji is kept
        let english = LyricsFormatter.process(.synced([line(0, 1, "Nobody knows my name"), line(1, 5, "We are the one")]), options: LyricsFormatOptions())
        #expect(english != .none)
    }

    @Test func idsFollowTheirPlaceAfterDropping() {
        let state = LyricsFormatter.process(.synced([line(0, 10, "春の風が吹く"), line(1, 14, "Haru no kaze ga fuku"), line(2, 18, "星の下で歌う")]),
                                            options: LyricsFormatOptions())
        guard case let .synced(lines) = state else {
            Issue.record("expected synchronised lyrics")
            return
        }
        #expect(lines.map(\.id) == [0, 1])
    }
}
