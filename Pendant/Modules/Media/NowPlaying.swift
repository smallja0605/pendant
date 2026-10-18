import Foundation

/// Players that are fully supported (state, artwork, control). Other Now Playing sources are not
/// available to third-party apps since macOS 15.4 (see docs/DECISIONS.md).
enum MediaSourceID: String, CaseIterable, Sendable {
    case appleMusic
    case spotify

    var bundleIdentifier: String {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    var displayName: String {
        switch self {
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        }
    }
}

enum PlaybackState: Equatable, Sendable {
    case playing, paused, stopped
}

/// What a player told us about itself at one moment. Never logged (titles are user content).
struct PlaybackSnapshot: Equatable, Sendable {
    var source: MediaSourceID
    var state: PlaybackState
    var title: String
    var album: String
    var artist: String
    /// Seconds; 0 when unknown.
    var duration: TimeInterval
    /// Seconds at `receivedAt`, nil when the player did not report it.
    var position: TimeInterval?
    /// Identity of the track, used to detect track changes (artwork, position resets).
    var trackKey: String
    var receivedAt: Date
}

/// UI-facing state: a snapshot plus an anchor from which the elapsed time is derived without polling.
struct NowPlaying: Equatable, Sendable {
    var snapshot: PlaybackSnapshot
    /// Elapsed seconds at `anchorDate`; nil while unknown (e.g. no Automation permission yet).
    var anchorPosition: TimeInterval?
    var anchorDate: Date

    var source: MediaSourceID { snapshot.source }
    var isPlaying: Bool { snapshot.state == .playing }
    var hasKnownPosition: Bool { anchorPosition != nil }

    func position(at date: Date) -> TimeInterval {
        guard let anchorPosition else { return 0 }
        let elapsed = isPlaying ? max(date.timeIntervalSince(anchorDate), 0) : 0
        let value = anchorPosition + elapsed
        return snapshot.duration > 0 ? min(value, snapshot.duration) : value
    }

    func progress(at date: Date) -> Double {
        guard snapshot.duration > 0 else { return 0 }
        return min(max(position(at: date) / snapshot.duration, 0), 1)
    }
}
