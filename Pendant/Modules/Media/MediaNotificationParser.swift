import Foundation

/// Turns the `userInfo` of the players' distributed notifications into snapshots.
/// Pure, so it can be tested with fixed dictionaries. Key names are the ones the apps post.
enum MediaNotificationParser {
    static let appleMusicNotification = Notification.Name("com.apple.Music.playerInfo")
    static let spotifyNotification = Notification.Name("com.spotify.client.PlaybackStateChanged")

    static func parse(source: MediaSourceID, userInfo: [AnyHashable: Any]?, now: Date = Date()) -> PlaybackSnapshot? {
        guard let info = userInfo else { return nil }
        let state = parseState(info["Player State"] as? String)
        let title = (info["Name"] as? String) ?? ""
        let album = (info["Album"] as? String) ?? ""
        let artist = (info["Artist"] as? String) ?? ""

        let duration: TimeInterval
        let position: TimeInterval?
        let trackKey: String
        switch source {
        case .appleMusic:
            duration = milliseconds(info["Total Time"])
            position = nil // Apple Music does not report it; fetched through Automation when permitted.
            trackKey = (info["PersistentID"] as? String) ?? (info["Persistent ID"] as? String)
                ?? "\(title)|\(artist)|\(album)"
        case .spotify:
            duration = milliseconds(info["Duration"])
            position = (info["Playback Position"] as? NSNumber)?.doubleValue
            trackKey = (info["Track ID"] as? String) ?? "\(title)|\(artist)|\(album)"
        }
        if state == .stopped {
            return PlaybackSnapshot(source: source, state: .stopped, title: "", album: "", artist: "",
                                    duration: 0, position: nil, trackKey: "", receivedAt: now)
        }
        guard !title.isEmpty || !trackKey.isEmpty else { return nil }
        return PlaybackSnapshot(source: source, state: state, title: title, album: album, artist: artist,
                                duration: duration, position: position, trackKey: trackKey, receivedAt: now)
    }

    static func parseState(_ raw: String?) -> PlaybackState {
        switch raw?.lowercased() {
        case "playing": .playing
        case "paused": .paused
        default: .stopped
        }
    }

    private static func milliseconds(_ value: Any?) -> TimeInterval {
        guard let number = value as? NSNumber else { return 0 }
        return max(number.doubleValue / 1000, 0)
    }
}
