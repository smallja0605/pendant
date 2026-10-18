import Foundation

/// Pure rate limiter: allows an event only if enough time passed since it last fired.
struct HapticThrottle: Sendable {
    private var lastFired: [HapticEvent: TimeInterval] = [:]

    mutating func shouldFire(_ event: HapticEvent, at time: TimeInterval) -> Bool {
        if let last = lastFired[event], time - last < event.minimumInterval { return false }
        lastFired[event] = time
        return true
    }

    mutating func reset() { lastFired.removeAll() }
}

/// Fires once each time a continuous value crosses a unit boundary (not on every change).
struct StepTracker: Sendable {
    let unit: Double
    private var lastStep: Int?

    init(unit: Double) {
        precondition(unit > 0, "unit must be positive")
        self.unit = unit
    }

    /// Returns true when `value` is in a different step than the previous call.
    /// The first value only establishes the starting step.
    mutating func crossedBoundary(at value: Double) -> Bool {
        let step = Int((value / unit).rounded(.down))
        defer { lastStep = step }
        guard let lastStep else { return false }
        return step != lastStep
    }

    mutating func reset() { lastStep = nil }
}
