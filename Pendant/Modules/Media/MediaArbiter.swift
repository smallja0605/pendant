import Foundation

enum MediaSourcePreference: String, CaseIterable, Sendable {
    case auto, appleMusic, spotify
}

/// Decides which player the capsule shows when several are running. Pure.
enum MediaArbiter {
    /// - Parameters:
    ///   - states: latest non-stopped state per source (stopped / quit sources are absent).
    ///   - current: the source shown right now.
    ///   - lastChange: when each source last reported (used to prefer the most recent).
    static func pick(
        states: [MediaSourceID: PlaybackState],
        current: MediaSourceID?,
        lastChange: [MediaSourceID: Date],
        preference: MediaSourcePreference
    ) -> MediaSourceID? {
        let allowed: [MediaSourceID] = switch preference {
        case .auto: MediaSourceID.allCases
        case .appleMusic: [.appleMusic]
        case .spotify: [.spotify]
        }
        let live = allowed.filter { states[$0] != nil }
        guard !live.isEmpty else { return nil }

        let playing = live.filter { states[$0] == .playing }
        let pool = playing.isEmpty ? live : playing
        if let current, pool.contains(current), playing.count <= 1 || states[current] == .playing { return current }
        return pool.max { (lastChange[$0] ?? .distantPast) < (lastChange[$1] ?? .distantPast) }
    }
}
