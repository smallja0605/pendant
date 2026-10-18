import AppKit
import Observation
import UserNotifications

/// Runs the timer state machine and everything around it: finish detection without a high-frequency
/// timer (one sleep until the finish date, re-checked after system wake), sound, haptics, notification.
@MainActor
@Observable
final class TimerController {
    static let shared = TimerController()
    private static let notificationID = "pendant.timer.finished"

    /// The countdown. (`engine` always has `.countdown` mode; the stopwatch is its own engine and runs independently.)
    private(set) var engine: TimerEngine
    /// The stopwatch, running at the same time as the countdown if wanted.
    private(set) var stopwatch = TimerEngine(mode: .stopwatch)
    /// Which of the two the timer page shows (both keep running either way).
    var viewMode: TimerEngine.Mode = .countdown
    /// True from the moment a countdown ends until the user resets / restarts it.
    private(set) var justFinished = false
    /// Called when a countdown ends (the window controller opens the capsule and flashes it).
    @ObservationIgnored var onFinished: (() -> Void)?

    @ObservationIgnored private var finishTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var askedForNotifications = false

    init() {
        engine = TimerEngine(duration: AppSettings.shared.timerLastDuration)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
    }

    /// The countdown is running.
    var isRunning: Bool { engine.isRunning }
    var isStopwatchRunning: Bool { stopwatch.isRunning }

    func engine(for mode: TimerEngine.Mode) -> TimerEngine { mode == .countdown ? engine : stopwatch }

    // MARK: Controls

    func toggle(_ mode: TimerEngine.Mode) {
        if mode == .countdown {
            toggle()
        } else if stopwatch.isRunning {
            stopwatch.pause(at: Date())
        } else {
            stopwatch.start(at: Date())
        }
    }

    func reset(_ mode: TimerEngine.Mode) {
        if mode == .countdown { reset() } else { stopwatch.reset() }
    }

    func setDuration(_ seconds: TimeInterval) {
        engine.setDuration(seconds)
        AppSettings.shared.timerLastDuration = engine.duration
    }

    func start() {
        justFinished = false
        engine.start(at: Date())
        scheduleFinish()
    }

    func pause() {
        engine.pause(at: Date())
        cancelPending()
    }

    func toggle() {
        if engine.isRunning { pause() } else { start() }
    }

    func reset() {
        engine.reset()
        justFinished = false
        cancelPending()
    }

    // MARK: Finishing

    private func scheduleFinish() {
        finishTask?.cancel()
        guard let finishDate = engine.finishDate else { return }
        scheduleNotification(at: finishDate)
        finishTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(finishDate.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    /// Completes the countdown if its time is up (also called after wake-from-sleep).
    func evaluate(now: Date = Date()) {
        guard engine.isRunning, engine.isFinished(at: now) else { return }
        engine.finish()
        justFinished = true
        finishTask?.cancel()
        HapticService.shared.play(.timerFinished)
        if AppSettings.shared.timerSound { NSSound(named: "Glass")?.play() }
        onFinished?()
    }

    private func cancelPending() {
        finishTask?.cancel()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationID])
    }

    private func scheduleNotification(at date: Date) {
        guard AppSettings.shared.timerNotification else { return }
        let center = UNUserNotificationCenter.current()
        if !askedForNotifications {
            askedForNotifications = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "timer.finished", defaultValue: "計時結束")
        content.sound = AppSettings.shared.timerSound ? .default : nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(date.timeIntervalSinceNow, 1), repeats: false)
        center.add(UNNotificationRequest(identifier: Self.notificationID, content: content, trigger: trigger))
    }
}
