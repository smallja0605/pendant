import Foundation
import Testing
@testable import Pendant

struct HapticThrottleTests {
    @Test func blocksEventsInsideMinimumInterval() {
        var throttle = HapticThrottle()
        let r1 = throttle.shouldFire(.dragStep, at: 0)
        #expect(r1)
        let r2 = throttle.shouldFire(.dragStep, at: 0.02)
        #expect(!r2)
        let r3 = throttle.shouldFire(.dragStep, at: 0.05)
        #expect(r3)
    }

    @Test func notchEnterNeedsFullHundredFiftyMilliseconds() {
        var throttle = HapticThrottle()
        let r4 = throttle.shouldFire(.notchEnter, at: 1)
        #expect(r4)
        let r5 = throttle.shouldFire(.notchEnter, at: 1.1)
        #expect(!r5)
        let r6 = throttle.shouldFire(.notchEnter, at: 1.16)
        #expect(r6)
    }

    @Test func eventsAreThrottledIndependently() {
        var throttle = HapticThrottle()
        let r7 = throttle.shouldFire(.dragStep, at: 0)
        #expect(r7)
        let r8 = throttle.shouldFire(.dateChanged, at: 0.001)
        #expect(r8)
    }
}

struct StepTrackerTests {
    @Test func firesOnlyWhenCrossingBoundaries() {
        var tracker = StepTracker(unit: 5)
        let r9 = tracker.crossedBoundary(at: 1)
        #expect(!r9)   // establishes start
        let r10 = tracker.crossedBoundary(at: 4.9)
        #expect(!r10)
        let r11 = tracker.crossedBoundary(at: 5.1)
        #expect(r11)
        let r12 = tracker.crossedBoundary(at: 9.9)
        #expect(!r12)
        let r13 = tracker.crossedBoundary(at: 4.0)
        #expect(r13)  // backwards also counts
    }

    @Test func skippingSeveralUnitsFiresOnce() {
        var tracker = StepTracker(unit: 1)
        _ = tracker.crossedBoundary(at: 0)
        let r14 = tracker.crossedBoundary(at: 7.5)
        #expect(r14)
        let r15 = tracker.crossedBoundary(at: 7.9)
        #expect(!r15)
    }
}

@MainActor
private final class RecordingPerformer: HapticPerforming {
    var performed: [HapticPattern] = []
    func perform(_ pattern: HapticPattern) { performed.append(pattern) }
}

@MainActor
struct HapticServiceTests {
    private func makeService(performer: RecordingPerformer, time: @escaping () -> TimeInterval) -> HapticService {
        let defaults = UserDefaults(suiteName: "haptic-tests-\(UUID().uuidString)")!
        return HapticService(performer: performer, defaults: defaults, clock: time)
    }

    @Test func disabledSwitchSilencesEverything() {
        let performer = RecordingPerformer()
        var now: TimeInterval = 0
        let service = makeService(performer: performer) { now }
        service.isEnabled = false
        for event in HapticEvent.allCases { now += 1; service.play(event) }
        #expect(performer.performed.isEmpty)
    }

    @Test func enabledPlaysMappedPatterns() {
        let performer = RecordingPerformer()
        var now: TimeInterval = 0
        let service = makeService(performer: performer) { now }
        now = 1; service.play(.notchEnter)
        now = 2; service.play(.hoverControl)
        now = 3; service.play(.stateSettled)
        #expect(performer.performed == [.generic, .generic, .levelChange])
    }

    @Test func rapidRepeatsAreThrottled() {
        let performer = RecordingPerformer()
        var now: TimeInterval = 1
        let service = makeService(performer: performer) { now }
        service.play(.notchEnter)
        now = 1.05; service.play(.notchEnter)
        #expect(performer.performed.count == 1)
    }

    @Test func eventTableMatchesRequirements() {
        #expect(HapticEvent.notchEnter.pattern == .generic)
        #expect(HapticEvent.hoverControl.pattern == .generic)
        #expect(HapticEvent.expandStarted.pattern == .levelChange)
        #expect(HapticEvent.stateSettled.pattern == .levelChange)
        #expect(HapticEvent.dragStep.pattern == .alignment)
        #expect(HapticEvent.dateChanged.pattern == .alignment)
        #expect(HapticEvent.timerFinished.pattern == .levelChange)
        #expect(HapticEvent.timerFinished.repeats.times == 1)
    }

    @Test func theTrackChangeIsOneBigHaptic() {
        #expect(HapticEvent.swipeCommit.pattern == .levelChange)
        #expect(HapticEvent.swipeCommit.repeats.times == 0) // one single big haptic
        #expect(HapticEvent.swipeCommit.minimumInterval == 0)
    }
}
