import Foundation

/// Pure helpers for the media UI so the behaviour is testable.
enum MediaInteractionMath {
    /// Haptic step for the progress bar: 1 % of the track, but never finer than one second.
    static func progressStepSeconds(duration: TimeInterval) -> Double {
        max(1, duration / 100)
    }

    /// Volume haptic step (percent).
    static let volumeStepPercent = 1.0

    enum VolumeLevel: Equatable { case muted, low, medium, high }

    static func volumeLevel(_ volume: Double) -> VolumeLevel {
        switch volume {
        case ..<0.005: .muted
        case ..<0.34: .low
        case ..<0.67: .medium
        default: .high
        }
    }

    static func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}

/// Turns a horizontal two-finger swipe into track changes. The swipe is a track: nothing shows for the first `deadZone`
/// points (a light touch or a scroll that is not meant as a swipe), then cycles begin — the icon appears, the track changes
/// `changeDistance` later (in the middle of the cycle), the icon disappears — and a swipe that keeps going repeats them.
/// Fingers moving left mean "next", right "previous" (`reversed` swaps them).
struct SwipeAccumulator: Sendable {
    enum Action: Equatable, Sendable { case next, previous }

    var threshold: Double
    var reversed = false
    private var sum = 0.0
    private var cuts = 0

    init(threshold: Double = 60, reversed: Bool = false) {
        self.threshold = threshold
        self.reversed = reversed
    }

    /// Distance before the icon appears.
    var deadZone: Double { max(threshold, 1) * 0.4 }
    /// Distance from the icon appearing to the track changing.
    var changeDistance: Double { max(threshold, 1) * 1.6 }
    /// Length of one appear → change → disappear cycle.
    var cycle: Double { changeDistance * 2 }
    /// True while the fingers move left.
    var leftwards: Bool { sum < 0 }
    /// The swipe has gone past the dead zone: the icon shows.
    var isVisible: Bool { abs(sum) >= deadZone }
    /// How far the swipe has gone past the dead zone.
    var visibleDistance: Double { max(abs(sum) - deadZone, 0) }
    /// Position in the current cycle, 0…<1 (0.5 is where the track changes).
    var cycleProgress: Double { visibleDistance.truncatingRemainder(dividingBy: cycle) / cycle }
    /// How many times the track has changed in this swipe.
    var cutCount: Int { cuts }
    /// The action the swipe's current direction stands for.
    var currentAction: Action { (leftwards != reversed) ? .next : .previous }

    /// `deltaX` follows the content direction (negative = fingers moved left).
    mutating func add(deltaX: Double) -> Action? {
        // Turning around starts a new swipe.
        if sum != 0, deltaX != 0, (sum < 0) != (deltaX < 0) { reset() }
        sum += deltaX
        let reached = visibleDistance >= changeDistance ? Int((visibleDistance - changeDistance) / cycle) + 1 : 0
        guard reached > cuts else { return nil }
        cuts = reached
        return currentAction
    }

    /// Call when the gesture is finished (fingers lifted, or a pause long enough).
    mutating func reset() {
        sum = 0
        cuts = 0
    }
}

/// A quick flick should not need as much travel as a slow, deliberate swipe: the faster the fingers move, the more every
/// point of movement counts.
enum SwipeSpeed {
    /// Below this speed (points per second) a swipe counts as slow: gain 1.
    static let slow = 300.0

    /// 1 for slow swipes, rising smoothly to `maxGain` at `fast` points per second and beyond.
    static func gain(speed: Double, fast: Double, maxGain: Double) -> Double {
        guard fast > slow, maxGain > 1 else { return 1 }
        let ratio = min(max((speed - slow) / (fast - slow), 0), 1)
        return 1 + (maxGain - 1) * ratio * ratio * (3 - 2 * ratio)
    }
}
