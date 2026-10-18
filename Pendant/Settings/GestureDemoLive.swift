import Observation
import SwiftUI

/// The gesture demo's "try it" mode: while the pointer is over the demo trackpad, the visitor's real two-finger swipe is fed through
/// the same `SwipeAccumulator` the capsule uses (sensitivity, direction and on/off come from the settings) and the demo island
/// answers like the real one: the step icon, the track change with its song line, the capsule's jelly. It also plays the same haptics.
@MainActor
@Observable
final class LiveSwipe {
    var hovering = false

    @ObservationIgnored private var accumulator = SwipeAccumulator()
    @ObservationIgnored private var active = false
    @ObservationIgnored private var onTime = 0.0
    @ObservationIgnored private var offTime: Double?
    @ObservationIgnored private var endedAt = -10.0
    @ObservationIgnored private var endProgress = 0.0
    @ObservationIgnored private var rightSide = true
    @ObservationIgnored private var iconIsNext = true
    @ObservationIgnored private var track = 0
    @ObservationIgnored private var changedAt: Double?
    @ObservationIgnored private var lastEvent: TimeInterval?
    @ObservationIgnored private var speed = 0.0
    @ObservationIgnored private var peakSpeed = 0.0
    @ObservationIgnored private var idleTask: Task<Void, Never>?

    private var now: Double { Date().timeIntervalSinceReferenceDate }

    // MARK: Input

    /// Returns true when the event was used (the page behind does not scroll).
    func scroll(_ deltaX: Double, _ deltaY: Double, _ phase: ScrollPhase) -> Bool {
        let settings = AppSettings.shared
        guard hovering, settings.swipeTracksEnabled else { return false }
        if phase.began { finish() }
        let horizontal = abs(deltaX) > abs(deltaY)
        if phase.momentum { finish(); return horizontal }
        guard horizontal else {
            if phase.ended { finish() }
            return false
        }
        accumulator.threshold = settings.swipeThreshold
        accumulator.reversed = settings.swipeReversed
        track(deltaX)
        if phase.ended { finish() }
        idleTask?.cancel()
        if !phase.ended {
            idleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(phase.hasPhase ? 0.5 : 0.3))
                guard !Task.isCancelled else { return }
                self?.finish()
            }
        }
        return true
    }

    private func track(_ rawDelta: Double) {
        let tuning = Tuning.shared
        let moment = ProcessInfo.processInfo.systemUptime
        let interval = min(max(moment - (lastEvent ?? moment - 0.016), 0.004), 0.1)
        lastEvent = moment
        speed = 0.5 * speed + 0.5 * abs(rawDelta) / interval
        peakSpeed = max(peakSpeed, speed)
        let delta = rawDelta * SwipeSpeed.gain(speed: speed, fast: tuning.swipeFastSpeed, maxGain: tuning.swipeFastGain)
        let wasLeftwards = accumulator.leftwards
        let action = accumulator.add(deltaX: delta)
        if active, accumulator.leftwards != wasLeftwards { finish(keepAccumulator: true) }
        if accumulator.isVisible, !active {
            active = true
            onTime = now
            offTime = nil
            rightSide = accumulator.leftwards
            iconIsNext = accumulator.currentAction == .next
        }
        if action != nil { changeTrack() }
    }

    private func changeTrack() {
        track = (track + 1) % 2 // two alternating placeholder tracks; the direction only matters for the icon
        changedAt = now
        HapticService.shared.play(.swipeCommit)
    }

    /// The fingers lifted (or the pointer left the trackpad).
    func finish(keepAccumulator: Bool = false) {
        defer {
            if !keepAccumulator { accumulator.reset() }
            lastEvent = nil
            speed = 0
            peakSpeed = 0
        }
        guard active else { return }
        active = false
        offTime = now
        endedAt = now
        endProgress = accumulator.cycleProgress
        // A quick flick that was let go before the change point still changes the track.
        if accumulator.cutCount == 0, peakSpeed >= Tuning.shared.swipeFastSpeed * 0.5 {
            changeTrack()
            endProgress = 1
        }
    }

    func release() { finish() }

    // MARK: Output

    /// The island's state at `moment` (the same shape the looping demo produces).
    func state(at moment: Double) -> SwipeState {
        var result = SwipeState()
        result.track = track
        result.changedAt = changedAt
        result.rightSide = rightSide
        result.iconIsNext = iconIsNext
        result.grow = jelly(at: moment, on: onTime, off: offTime ?? .infinity)
        let sinceEnd = moment - endedAt
        if active {
            result.icon = iconIsNext ? .next : .previous
            result.iconProgress = accumulator.cycleProgress
        } else if sinceEnd < 0.6 {
            result.icon = iconIsNext ? .next : .previous
            if endProgress >= 0.5 {
                result.iconProgress = 0.96 + 0.04 * smooth(sinceEnd / 0.25)
            } else {
                result.iconProgress = endProgress
                result.iconFade = 1 - smooth(sinceEnd / 0.2)
            }
        }
        return result
    }
}
