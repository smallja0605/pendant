import Foundation
import Testing
@testable import Pendant

struct LyricsSourcesTests {
    private let snapshot = PlaybackSnapshot(
        source: .appleMusic, state: .playing, title: "A & B", album: "Album", artist: "Artist", duration: 201.6,
        position: 0, trackKey: "k", receivedAt: Date()
    )

    @Test func templateIsFilledAndEncoded() {
        let url = LyricsFetcher.expand("https://x.test/l?t={title}&a={artist}&d={duration}", snapshot)
        #expect(url?.absoluteString == "https://x.test/l?t=A%20%26%20B&a=Artist&d=202")
    }

    @Test func jsonPathReadsKeysAndPositions() throws {
        let root = try JSONSerialization.jsonObject(with: Data(#"{"a":{"list":[{"x":"no"},{"x":"yes"}]}}"#.utf8))
        #expect(LyricsFetcher.value(in: root, path: "a.list.1.x") as? String == "yes")
        #expect(LyricsFetcher.value(in: root, path: "a.list.5.x") == nil)
        #expect(LyricsFetcher.value(in: root, path: "b") == nil)
    }

    @Test func textWithTimeTagsIsSynced() {
        if case let .synced(lines) = LyricsFetcher.state(fromText: "[00:01.00] one\n[00:03.50] two") {
            #expect(lines.map(\.text) == ["one", "two"])
        } else {
            Issue.record("expected synchronised lyrics")
        }
        #expect(LyricsFetcher.state(fromText: "just\nwords") == .plain(["just", "words"]))
        #expect(LyricsFetcher.state(fromText: "  \n ") == .none)
    }

    @Test func storedListKeepsOrderAndGainsNewBuiltIns() {
        var stored = Array(LyricsSourceItem.defaults.reversed())
        stored.removeAll { $0.id == "netease" }
        stored.insert(LyricsSourceItem(id: "mine", kind: .custom, name: "Mine", enabled: true), at: 1)
        let merged = LyricsSourceItem.merged(stored)
        #expect(merged.map(\.id) == ["musixmatch", "mine", "player", "lrclib", "netease"])
    }
}
