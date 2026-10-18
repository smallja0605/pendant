import Foundation
import Observation

/// Collects the live activities (media playing, timer running …) and orders them by level (3.5.2). Pure data: the
/// window controllers turn the ordered list into islands. Modules do not poll; this observes their state.
@MainActor
@Observable
final class ActivityCenter {
    /// How long a finished timer keeps pulsing as an island (3.5.4).
    static let timerAlertDuration: TimeInterval = 10

    private(set) var ordered: [LiveActivity] = []
    private(set) var timerAlertUntil: Date?

    @ObservationIgnored private let media: MediaController
    @ObservationIgnored private var pausedSince: Date?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    private var settings: AppSettings { .shared }

    init(media: MediaController) {
        self.media = media
        observe()
    }

    /// The timer reached zero: keep it on the island row until it is clicked or the alert runs out.
    func timerDidFinish() {
        timerAlertUntil = Date().addingTimeInterval(Self.timerAlertDuration)
        recompute()
    }

    func acknowledgeTimerAlert() {
        guard timerAlertUntil != nil else { return }
        timerAlertUntil = nil
        recompute()
    }

    /// Island widths follow their content (icon, gap, value) plus equal side padding: 9 pt per side.
    private static let sidePadding: CGFloat = 18

    private static func mediaIslandWidth(_ settings: AppSettings) -> CGFloat {
        let first: CGFloat = settings.showCoverInCompact ? 20 : 14
        return sidePadding + first + (settings.showWaveformInCompact ? 9 + 13 : 0)
    }

    private static func timerIslandWidth(_ mode: TimerEngine.Mode = .countdown) -> CGFloat {
        let digits = TimerCompactMetrics.textWidth(TimerCompactMetrics.sampleText(mode))
        let icon: CGFloat = AppSettings.shared.timerRing && mode == .countdown ? 18 : 14
        return sidePadding + icon + 8 + digits
    }

    private func observe() {
        withObservationTracking {
            _ = media.nowPlaying
            _ = TimerController.shared.isRunning
            _ = TimerController.shared.isStopwatchRunning
            _ = ShelfStore.shared.items.count
            _ = settings.activityPriority
            _ = settings.disabledActivities
            _ = settings.mainOnlyActivities
            _ = settings.mediaPauseRetention
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.recompute()
                self?.observe()
            }
        }
        recompute()
    }

    private func recompute() {
        let now = Date()
        let alerting = (timerAlertUntil ?? .distantPast) > now
        if !alerting { timerAlertUntil = nil }

        var live: [String: LiveActivity] = [:]
        if mediaIsLive(now: now) {
            live["media"] = LiveActivity(id: "media", moduleID: "media", symbolName: "music.note",
                                       secondaryWidth: Self.mediaIslandWidth(settings))
        }
        if TimerController.shared.isRunning || alerting {
            live["timer"] = LiveActivity(id: "timer", moduleID: "timer", symbolName: "timer",
                                       secondaryWidth: Self.timerIslandWidth(), isAlerting: alerting)
        }
        if TimerController.shared.isStopwatchRunning {
            live["stopwatch"] = LiveActivity(id: "stopwatch", moduleID: "timer", symbolName: "stopwatch",
                                             secondaryWidth: Self.timerIslandWidth(.stopwatch))
        }
        let shelfCount = ShelfStore.shared.items.count
        if shelfCount > 0 {
            live["shelf"] = LiveActivity(id: "shelf", moduleID: "shelf", symbolName: "tray.and.arrow.down",
                                         secondaryWidth: Self.sidePadding + 12 + 6 + CGFloat(String(shelfCount).count) * 8)
        }
        var result: [LiveActivity] = []
        for id in settings.activityPriority {
            guard var activity = live[id], settings.activityRole(id) != .hidden else { continue }
            activity.canBeSecondary = settings.activityRole(id) == .anyIsland
            result.append(activity)
        }
        // A finished timer takes over the whole island row until it is acknowledged: the other content gives way
        // (it is hidden, not moved to a secondary island) and returns afterwards.
        if alerting, let timer = result.first(where: { $0.id == "timer" }) { result = [timer] }
        if result != ordered { ordered = result }
        scheduleWake(alertEnd: alerting ? timerAlertUntil : nil)
    }

    /// Playing, or paused for less than the retention time (0 = a paused player is not an activity).
    private func mediaIsLive(now: Date) -> Bool {
        guard let playing = media.nowPlaying else {
            pausedSince = nil
            return false
        }
        if playing.isPlaying {
            pausedSince = nil
            return true
        }
        let since = pausedSince ?? now
        pausedSince = since
        return now.timeIntervalSince(since) < settings.mediaPauseRetention
    }

    /// One sleep until the next time-based change (retention running out, alert ending) instead of polling.
    private func scheduleWake(alertEnd: Date?) {
        wakeTask?.cancel()
        var deadlines: [Date] = []
        if let alertEnd { deadlines.append(alertEnd) }
        if let since = pausedSince, media.nowPlaying != nil { deadlines.append(since.addingTimeInterval(settings.mediaPauseRetention)) }
        guard let next = deadlines.min() else { return }
        let delay = max(next.timeIntervalSinceNow, 0) + 0.05
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.recompute()
        }
    }
}
