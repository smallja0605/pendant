import Foundation
import Testing
@testable import Pendant

struct TimerEngineTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func countdownRunsOnAbsoluteTime() {
        var timer = TimerEngine(duration: 60)
        timer.start(at: t0)
        #expect(timer.remaining(at: t0.addingTimeInterval(10)) == 50)
        #expect(timer.finishDate == t0.addingTimeInterval(60))
        // A long sleep or a stalled app: elapsed time is still exact, remaining clamps at zero.
        #expect(timer.remaining(at: t0.addingTimeInterval(3_600)) == 0)
        #expect(timer.isFinished(at: t0.addingTimeInterval(3_600)))
        #expect(!timer.isFinished(at: t0.addingTimeInterval(59)))
    }

    @Test func pauseAndResumeAccumulate() {
        var timer = TimerEngine(duration: 100)
        timer.start(at: t0)
        timer.pause(at: t0.addingTimeInterval(30))
        #expect(timer.elapsed(at: t0.addingTimeInterval(500)) == 30) // frozen while paused
        timer.start(at: t0.addingTimeInterval(500))
        #expect(timer.elapsed(at: t0.addingTimeInterval(520)) == 50)
        #expect(timer.finishDate == t0.addingTimeInterval(570))
    }

    @Test func finishStopsAtDurationAndCannotRestartUntilReset() {
        var timer = TimerEngine(duration: 10)
        timer.start(at: t0)
        timer.finish()
        #expect(!timer.isRunning)
        #expect(timer.remaining(at: t0.addingTimeInterval(99)) == 0)
        timer.start(at: t0.addingTimeInterval(20))
        #expect(!timer.isRunning)
        timer.reset()
        timer.start(at: t0.addingTimeInterval(30))
        #expect(timer.isRunning)
    }

    @Test func stopwatchCountsUpAndNeverFinishes() {
        var timer = TimerEngine(mode: .stopwatch)
        timer.start(at: t0)
        #expect(timer.displayTime(at: t0.addingTimeInterval(75)) == 75)
        #expect(!timer.isFinished(at: t0.addingTimeInterval(1_000_000)))
        #expect(timer.finishDate == nil)
    }

    @Test func durationOnlyChangesBeforeStartingAndIsClamped() {
        var timer = TimerEngine(duration: 60)
        timer.setDuration(120)
        #expect(timer.duration == 120)
        timer.setDuration(10_000_000)
        #expect(timer.duration == 99 * 3600 + 59 * 60 + 59)
        timer.setDuration(30)
        timer.start(at: t0)
        timer.setDuration(500)
        #expect(timer.duration == 30)
    }

    @Test func zeroDurationCannotStart() {
        var timer = TimerEngine(duration: 0)
        timer.start(at: t0)
        #expect(!timer.isRunning)
    }

    @Test func switchingModeResets() {
        var timer = TimerEngine(duration: 60)
        timer.start(at: t0)
        timer.setMode(.stopwatch)
        #expect(!timer.isRunning)
        #expect(timer.elapsed(at: t0.addingTimeInterval(5)) == 0)
    }

    @Test func formattingAndWheelComponents() {
        #expect(TimerEngine.format(65) == "01:05")
        #expect(TimerEngine.format(3725) == "1:02:05")
        #expect(TimerEngine.format(5.67, tenths: true) == "00:05.6")
        let parts = TimerEngine.components(of: 3725)
        #expect(parts.hours == 1 && parts.minutes == 2 && parts.seconds == 5)
    }

    @Test func progressTracksElapsedFraction() {
        var timer = TimerEngine(duration: 200)
        timer.start(at: t0)
        #expect(timer.progress(at: t0.addingTimeInterval(50)) == 0.25)
        #expect(timer.progress(at: t0.addingTimeInterval(500)) == 1)
    }
}
