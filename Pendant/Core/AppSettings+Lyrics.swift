import Foundation

extension AppSettings {
    /// The sources that can be asked for this track, in order: network ones need "online lyrics", the player's own needs Apple Music,
    /// the ones that need a key or an address need it filled in.
    func activeLyricsSources(for snapshot: PlaybackSnapshot) -> [LyricsSourceItem] {
        lyricsSources.filter { item in
            guard item.enabled else { return false }
            if item.isNetwork && !onlineLyrics { return false }
            switch item.kind {
            case .player: return snapshot.source == .appleMusic
            case .musixmatch: return LyricsKeychain.read(account: "musixmatch")?.isEmpty == false
            case .custom: return !item.urlTemplate.isEmpty
            default: return true
            }
        }
    }

    /// Whether any lyrics source is switched on (the page says "已關閉" when none is).
    var lyricsAvailable: Bool { lyricsSources.contains { $0.enabled && (!$0.isNetwork || onlineLyrics) } }

    /// Changes whenever the list (order, switches, addresses) changes, so the lyrics are looked up again.
    var lyricsSourcesSignature: String {
        lyricsSources.map { "\($0.signature)\($0.enabled)" }.joined() + "|\(onlineLyrics)"
    }
}
