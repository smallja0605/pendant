import AppKit

/// Abstraction over the system performer so the service can be unit tested.
@MainActor
protocol HapticPerforming: AnyObject {
    func perform(_ pattern: HapticPattern)
}

@MainActor
final class SystemHapticPerformer: HapticPerforming {
    func perform(_ pattern: HapticPattern) {
        let system: NSHapticFeedbackManager.FeedbackPattern = switch pattern {
        case .alignment: .alignment
        case .generic: .generic
        case .levelChange: .levelChange
        }
        // Silently does nothing without a Force Touch trackpad (e.g. external mouse).
        NSHapticFeedbackManager.defaultPerformer.perform(system, performanceTime: .now)
    }
}

/// Single entry point for all haptics: global switch, throttling, double-tap events.
@MainActor
final class HapticService {
    static let shared = HapticService()
    static let enabledKey = "haptics.enabled"

    private let defaults: UserDefaults
    private let performer: HapticPerforming
    private let clock: () -> TimeInterval
    private var throttle = HapticThrottle()

    /// Global "haptic feedback" switch (7.1). On by default.
    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    init(
        performer: HapticPerforming = SystemHapticPerformer(),
        defaults: UserDefaults = .standard,
        clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.performer = performer
        self.defaults = defaults
        self.clock = clock
    }

    func play(_ event: HapticEvent) {
        guard isEnabled, throttle.shouldFire(event, at: clock()) else { return }
        performer.perform(event.pattern)
        let repeats = event.repeats
        guard repeats.times > 0 else { return }
        Task { [performer, isEnabledNow = { self.isEnabled }] in
            for _ in 0..<repeats.times {
                try? await Task.sleep(for: .seconds(repeats.delay))
                guard isEnabledNow() else { return }
                performer.perform(event.pattern)
            }
        }
    }
}
