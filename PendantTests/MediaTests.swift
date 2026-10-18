import Foundation
import Testing
@testable import Pendant

struct MediaNotificationParserTests {
    @Test func parsesAppleMusicPlaying() {
        let info: [AnyHashable: Any] = [
            "Player State": "Playing", "Name": "Song", "Artist": "Band", "Album": "Record",
            "Total Time": NSNumber(value: 202_000), "PersistentID": "ABC123",
        ]
        let snapshot = MediaNotificationParser.parse(source: .appleMusic, userInfo: info)
        #expect(snapshot?.state == .playing)
        #expect(snapshot?.title == "Song")
        #expect(snapshot?.duration == 202)
        #expect(snapshot?.position == nil)
        #expect(snapshot?.trackKey == "ABC123")
    }

    @Test func parsesSpotifyWithPosition() {
        let info: [AnyHashable: Any] = [
            "Player State": "Paused", "Name": "Song", "Artist": "Band", "Album": "Record",
            "Duration": NSNumber(value: 180_000), "Playback Position": NSNumber(value: 42.5),
            "Track ID": "spotify:track:xyz",
        ]
        let snapshot = MediaNotificationParser.parse(source: .spotify, userInfo: info)
        #expect(snapshot?.state == .paused)
        #expect(snapshot?.position == 42.5)
        #expect(snapshot?.duration == 180)
        #expect(snapshot?.trackKey == "spotify:track:xyz")
    }

    @Test func stoppedClearsAllTrackInformation() {
        let info: [AnyHashable: Any] = ["Player State": "Stopped", "Name": "Leftover", "Artist": "Leftover"]
        let snapshot = MediaNotificationParser.parse(source: .spotify, userInfo: info)
        #expect(snapshot?.state == .stopped)
        #expect(snapshot?.title.isEmpty == true)
        #expect(snapshot?.artist.isEmpty == true)
    }

    @Test func unknownStateIsTreatedAsStopped() {
        #expect(MediaNotificationParser.parseState("Fast Forwarding") == .stopped)
        #expect(MediaNotificationParser.parseState(nil) == .stopped)
    }

    @Test func missingUserInfoYieldsNil() {
        #expect(MediaNotificationParser.parse(source: .appleMusic, userInfo: nil) == nil)
    }
}

struct NowPlayingTests {
    private func snapshot(state: PlaybackState, duration: TimeInterval = 200) -> PlaybackSnapshot {
        PlaybackSnapshot(source: .appleMusic, state: state, title: "T", album: "A", artist: "R",
                         duration: duration, position: nil, trackKey: "k", receivedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func positionAdvancesOnlyWhilePlaying() {
        let anchor = Date(timeIntervalSince1970: 100)
        let playing = NowPlaying(snapshot: snapshot(state: .playing), anchorPosition: 10, anchorDate: anchor)
        #expect(playing.position(at: anchor.addingTimeInterval(5)) == 15)
        let paused = NowPlaying(snapshot: snapshot(state: .paused), anchorPosition: 10, anchorDate: anchor)
        #expect(paused.position(at: anchor.addingTimeInterval(5)) == 10)
    }

    @Test func positionClampsToDurationAndHandlesUnknown() {
        let anchor = Date(timeIntervalSince1970: 0)
        let near = NowPlaying(snapshot: snapshot(state: .playing, duration: 20), anchorPosition: 19, anchorDate: anchor)
        #expect(near.position(at: anchor.addingTimeInterval(10)) == 20)
        let unknown = NowPlaying(snapshot: snapshot(state: .playing), anchorPosition: nil, anchorDate: anchor)
        #expect(unknown.position(at: anchor.addingTimeInterval(10)) == 0)
        #expect(!unknown.hasKnownPosition)
    }
}

struct MediaArbiterTests {
    private let now = Date()

    @Test func nothingLiveMeansNil() {
        #expect(MediaArbiter.pick(states: [:], current: nil, lastChange: [:], preference: .auto) == nil)
    }

    @Test func playingWinsOverPaused() {
        let pick = MediaArbiter.pick(
            states: [.appleMusic: .paused, .spotify: .playing], current: .appleMusic,
            lastChange: [.appleMusic: now, .spotify: now.addingTimeInterval(-10)], preference: .auto
        )
        #expect(pick == .spotify)
    }

    @Test func staysOnCurrentWhenNothingElseIsPlaying() {
        let pick = MediaArbiter.pick(
            states: [.appleMusic: .paused, .spotify: .paused], current: .spotify,
            lastChange: [.appleMusic: now, .spotify: now.addingTimeInterval(-10)], preference: .auto
        )
        #expect(pick == .spotify)
    }

    @Test func mostRecentWinsWhenBothPlay() {
        let pick = MediaArbiter.pick(
            states: [.appleMusic: .playing, .spotify: .playing], current: nil,
            lastChange: [.appleMusic: now.addingTimeInterval(-5), .spotify: now], preference: .auto
        )
        #expect(pick == .spotify)
    }

    @Test func fixedPreferenceIgnoresOtherPlayer() {
        let pick = MediaArbiter.pick(
            states: [.appleMusic: .playing, .spotify: .playing], current: nil,
            lastChange: [:], preference: .spotify
        )
        #expect(pick == .spotify)
        let none = MediaArbiter.pick(states: [.appleMusic: .playing], current: nil, lastChange: [:], preference: .spotify)
        #expect(none == nil)
    }
}

struct MediaInteractionMathTests {
    @Test func progressStepIsOnePercentButAtLeastOneSecond() {
        #expect(MediaInteractionMath.progressStepSeconds(duration: 600) == 6)
        #expect(MediaInteractionMath.progressStepSeconds(duration: 30) == 1)
    }

    @Test func volumeIconLevels() {
        #expect(MediaInteractionMath.volumeLevel(0) == .muted)
        #expect(MediaInteractionMath.volumeLevel(0.2) == .low)
        #expect(MediaInteractionMath.volumeLevel(0.5) == .medium)
        #expect(MediaInteractionMath.volumeLevel(0.9) == .high)
    }

    @Test func timeFormatting() {
        #expect(MediaInteractionMath.formatTime(133) == "2:13")
        #expect(MediaInteractionMath.formatTime(3725) == "1:02:05")
        #expect(MediaInteractionMath.formatTime(-4) == "0:00")
    }

    @Test func swipeChangesTheTrackInTheMiddleOfEachCycleAndKeepsSkipping() {
        var swipe = SwipeAccumulator(threshold: 50) // dead zone 20, change 80 after it, cycle 160
        #expect(swipe.add(deltaX: -60) == nil)
        #expect(swipe.add(deltaX: -39) == nil)
        #expect(swipe.add(deltaX: -2) == .next) // 101 ≥ 20 + 80: fingers left = next
        #expect(swipe.add(deltaX: -50) == nil)
        #expect(swipe.add(deltaX: -110) == .next) // 261 ≥ 20 + 80 + 160: one more cycle
        swipe.reset()
        #expect(swipe.add(deltaX: 101) == .previous)
    }

    @Test func nothingShowsInsideTheDeadZone() {
        var swipe = SwipeAccumulator(threshold: 50)
        _ = swipe.add(deltaX: -15)
        #expect(!swipe.isVisible)
        _ = swipe.add(deltaX: -10)
        #expect(swipe.isVisible)
        #expect(swipe.cycleProgress < 0.05)
    }

    @Test func reverseSwapsTheActionsAndTurningAroundStartsOver() {
        var reversed = SwipeAccumulator(threshold: 50, reversed: true)
        #expect(reversed.add(deltaX: -110) == .previous)
        var swipe = SwipeAccumulator(threshold: 50)
        #expect(swipe.add(deltaX: -50) == nil)
        #expect(swipe.add(deltaX: 10) == nil) // turned around: starts from zero
        #expect(swipe.leftwards == false)
        #expect(!swipe.isVisible)
    }

    @Test func cycleProgressRunsFromZeroToOnePerCycle() {
        var swipe = SwipeAccumulator(threshold: 50)
        _ = swipe.add(deltaX: -60) // 40 past the dead zone of 20, cycle 160
        #expect(abs(swipe.cycleProgress - 0.25) < 0.001)
        _ = swipe.add(deltaX: -40)
        #expect(abs(swipe.cycleProgress - 0.5) < 0.001) // the change happens here
        _ = swipe.add(deltaX: -100)
        #expect(abs(swipe.cycleProgress - 0.125) < 0.001) // wrapped into the next cycle
    }
}

struct SwipeSpeedTests {
    @Test func slowSwipesKeepTheirDistanceAndFlicksCountForMore() {
        #expect(SwipeSpeed.gain(speed: 100, fast: 1500, maxGain: 2.5) == 1)
        #expect(SwipeSpeed.gain(speed: 300, fast: 1500, maxGain: 2.5) == 1)
        let medium = SwipeSpeed.gain(speed: 900, fast: 1500, maxGain: 2.5)
        #expect(medium > 1 && medium < 2.5)
        #expect(SwipeSpeed.gain(speed: 1500, fast: 1500, maxGain: 2.5) == 2.5)
        #expect(SwipeSpeed.gain(speed: 9000, fast: 1500, maxGain: 2.5) == 2.5)
    }

    @Test func aBrokenSetupNeverShrinksTheDistance() {
        #expect(SwipeSpeed.gain(speed: 2000, fast: 200, maxGain: 3) == 1)
        #expect(SwipeSpeed.gain(speed: 2000, fast: 1500, maxGain: 0.5) == 1)
    }
}

struct SpotifyArtworkURLTests {
    @Test func onlyHttpsOnSpotifyCdnIsAllowed() {
        #expect(SpotifyArtworkFetcher.isAllowed("https://i.scdn.co/image/abc") != nil)
        #expect(SpotifyArtworkFetcher.isAllowed("http://i.scdn.co/image/abc") == nil)
        #expect(SpotifyArtworkFetcher.isAllowed("https://evil.example.com/image/abc") == nil)
        #expect(SpotifyArtworkFetcher.isAllowed("https://i.scdn.co.evil.com/x") == nil)
        #expect(SpotifyArtworkFetcher.isAllowed("file:///etc/passwd") == nil)
        #expect(SpotifyArtworkFetcher.isAllowed("") == nil)
    }
}

struct AirPlayTargetParserTests {
    @Test func parsesNamesAndFlagsAndKeepsOriginalIndexes() {
        let targets = AirPlayTargetParser.parse(["電腦|true|true", "客廳 HomePod|false|true", "Gone|false|false", "A|B|false|true"])
        #expect(targets.map(\.name) == ["電腦", "客廳 HomePod", "A|B"])
        #expect(targets.map(\.index) == [1, 2, 4])
        #expect(targets.first?.isSelected == true)
    }

    @Test func parsesTrailingVolume() {
        let targets = AirPlayTargetParser.parse(["客廳|true|true|55", "A|B|false|true|130", "電腦|false|true"])
        #expect(targets.map(\.volume) == [55, 100, nil])
        #expect(targets[1].name == "A|B")
    }

    @Test func parsesKindAndVideoFlag() {
        let targets = AirPlayTargetParser.parse(["Mac|true|true|40|computer|false", "客廳|false|true|20|AirPlay device|true", "Buds|false|true|0|Bluetooth device|false"])
        #expect(targets.map(\.kind) == [.computer, .airPlay, .bluetooth])
        #expect(targets[1].supportsVideo && targets[1].symbolName == "appletv.fill")
        #expect(targets[2].symbolName == "earbuds")
        #expect(targets[0].name == "Mac")
    }

    @Test func ignoresMalformedEntries() {
        #expect(AirPlayTargetParser.parse(["broken", "x|true"]).isEmpty)
    }
}
