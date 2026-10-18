import Foundation

/// Countdown / stopwatch state, computed from absolute dates so sleep, wake and a stalled app never
/// cause drift (requirements 4.4). Pure value type: no timers inside.
struct TimerEngine: Equatable, Sendable {
    enum Mode: String, Sendable, CaseIterable { case countdown, stopwatch }

    var mode: Mode = .countdown
    /// Countdown length in seconds (only changeable before it starts).
    private(set) var duration: TimeInterval = 300
    private(set) var isRunning = false
    private var startedAt: Date?
    private var accumulated: TimeInterval = 0

    init(mode: Mode = .countdown, duration: TimeInterval = 300) {
        self.mode = mode
        self.duration = max(duration, 0)
    }

    var hasStarted: Bool { isRunning || accumulated > 0 }

    func elapsed(at now: Date) -> TimeInterval {
        guard isRunning, let startedAt else { return accumulated }
        return accumulated + max(now.timeIntervalSince(startedAt), 0)
    }

    func remaining(at now: Date) -> TimeInterval {
        max(duration - elapsed(at: now), 0)
    }

    /// What the big digits show: remaining time (countdown) or elapsed time (stopwatch).
    func displayTime(at now: Date) -> TimeInterval {
        mode == .countdown ? remaining(at: now) : elapsed(at: now)
    }

    /// 0…1 for the progress bar (countdown only).
    func progress(at now: Date) -> Double {
        guard mode == .countdown, duration > 0 else { return 0 }
        return min(max(elapsed(at: now) / duration, 0), 1)
    }

    func isFinished(at now: Date) -> Bool {
        mode == .countdown && duration > 0 && hasStarted && remaining(at: now) <= 0
    }

    /// When a running countdown will reach zero.
    var finishDate: Date? {
        guard mode == .countdown, isRunning, let startedAt else { return nil }
        return startedAt.addingTimeInterval(max(duration - accumulated, 0))
    }

    mutating func start(at now: Date) {
        guard !isRunning, !(mode == .countdown && (duration <= 0 || remaining(at: now) <= 0)) else { return }
        isRunning = true
        startedAt = now
    }

    mutating func pause(at now: Date) {
        guard isRunning else { return }
        accumulated = elapsed(at: now)
        isRunning = false
        startedAt = nil
    }

    /// Countdown reached zero: stop at exactly the duration.
    mutating func finish() {
        guard mode == .countdown else { return }
        accumulated = duration
        isRunning = false
        startedAt = nil
    }

    mutating func reset() {
        isRunning = false
        startedAt = nil
        accumulated = 0
    }

    mutating func setDuration(_ seconds: TimeInterval) {
        guard !hasStarted else { return }
        duration = min(max(seconds, 0), 99 * 3600 + 59 * 60 + 59)
    }

    mutating func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        reset()
        mode = newMode
    }

    // MARK: Formatting

    static func format(_ seconds: TimeInterval, tenths: Bool = false) -> String {
        let total = max(seconds, 0)
        let whole = Int(total)
        let hours = whole / 3600, minutes = (whole % 3600) / 60, secs = whole % 60
        let base = hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
        return tenths ? base + String(format: ".%d", Int((total - Double(whole)) * 10)) : base
    }

    /// Splits a duration into the three wheel values.
    static func components(of seconds: TimeInterval) -> Components {
        let whole = max(Int(seconds.rounded()), 0)
        return Components(hours: min(whole / 3600, 99), minutes: (whole % 3600) / 60, seconds: whole % 60)
    }

    struct Components: Equatable, Sendable {
        let hours: Int
        let minutes: Int
        let seconds: Int
    }
}
