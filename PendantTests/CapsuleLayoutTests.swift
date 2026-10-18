import CoreGraphics
import Testing
@testable import Pendant

struct CapsuleLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    private var layout: CapsuleLayout {
        CapsuleLayout(notch: NotchGeometry(screenFrame: screen, safeAreaTop: 33.5,
            auxLeft: CGRect(x: 0, y: 1073.5, width: 762.5, height: 33.5),
            auxRight: CGRect(x: 947.5, y: 1073.5, width: 762.5, height: 33.5), menuBarHeight: 33.5))
    }

    @Test func statesGrowMonotonically() {
        let idle = layout.bodySize(for: .idle)
        let compact = layout.bodySize(for: .compact)
        let expanded = layout.bodySize(for: .expanded)
        #expect(compact.width > idle.width && compact.height == idle.height)
        #expect(expanded.width > compact.width && expanded.height > compact.height)
    }

    @Test func compactWingIsSquare() {
        let extra = layout.bodySize(for: .compact).width - layout.bodySize(for: .idle).width
        #expect(abs(extra / 2 - layout.notch.size.height) < 0.001)
    }

    @Test func bodyRectsAreTopCentred() {
        for state in [CapsuleState.idle, .compact, .expanded] {
            let rect = layout.bodyRect(for: state)
            #expect(rect.maxY == screen.maxY)
            #expect(abs(rect.midX - screen.midX) < 0.001)
        }
    }

    @Test func swellIsRoughlyEightPercentWideTwentyTwoTall() {
        let base = layout.bodySize(for: .idle)
        let swelled = layout.swelledSize(base, reduceMotion: false)
        #expect(abs(swelled.width / base.width - 1.08) < 0.001)
        #expect(abs(swelled.height / base.height - 1.22) < 0.001)
        let reduced = layout.swelledSize(base, reduceMotion: true)
        #expect(reduced.width < swelled.width && reduced.height < swelled.height)
    }

    @Test func expandedWidthIsClampedToScreen() {
        var narrow = layout
        narrow.notch.screenFrame = CGRect(x: 0, y: 0, width: 300, height: 700)
        #expect(narrow.bodySize(for: .expanded).width <= 300 - 2 * narrow.screenMargin)
    }

    @Test func panelAlwaysContainsSwelledBodyAndStaysOnScreen() {
        for state in [CapsuleState.idle, .compact, .expanded] {
            let panel = layout.panelFrame(for: state)
            let swelled = layout.swelledSize(layout.bodySize(for: state), reduceMotion: false)
            #expect(panel.width >= swelled.width + 2 * NotchGeometry.earRadius)
            #expect(panel.height >= swelled.height)
            #expect(screen.contains(panel))
        }
    }

    @Test func triggerZoneIsLargerThanBody() {
        for state in [CapsuleState.idle, .compact, .expanded] {
            #expect(layout.triggerRect(for: state).contains(layout.bodyRect(for: state)))
        }
    }
}

struct ExpandPolicyTests {
    @Test func offNeverExpands() {
        for state in [CapsuleState.idle, .compact, .expanded] {
            #expect(!ExpandPolicy.shouldAutoExpand(mode: .off, state: state))
        }
    }

    @Test func compactOnlyNeedsCompactCapsule() {
        #expect(!ExpandPolicy.shouldAutoExpand(mode: .compactOnly, state: .idle))
        #expect(ExpandPolicy.shouldAutoExpand(mode: .compactOnly, state: .compact))
    }

    @Test func alwaysExpandsFromIdleAndCompactButNotWhenOpen() {
        #expect(ExpandPolicy.shouldAutoExpand(mode: .always, state: .idle))
        #expect(ExpandPolicy.shouldAutoExpand(mode: .always, state: .compact))
        #expect(!ExpandPolicy.shouldAutoExpand(mode: .always, state: .expanded))
    }

    @Test func restingState() {
        #expect(ExpandPolicy.restingState(hasActivity: true) == .compact)
        #expect(ExpandPolicy.restingState(hasActivity: false) == .idle)
    }
}

struct CompactHoverFrameTests {
    @Test func compactPanelContainsTheSongInfoHoverState() {
        let notch = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1710, height: 1107), safeAreaTop: 33.5,
                                  auxLeft: CGRect(x: 0, y: 1073.5, width: 762.5, height: 33.5),
                                  auxRight: CGRect(x: 947.5, y: 1073.5, width: 762.5, height: 33.5), menuBarHeight: 33.5)
        let layout = CapsuleLayout(notch: notch)
        let compact = layout.bodySize(for: .compact)
        let swollen = layout.swelledSize(compact, reduceMotion: false)
        let panel = layout.panelFrame(for: .compact)
        #expect(panel.height >= swollen.height + CapsuleLayout.compactInfoHeight)
        #expect(panel.width >= swollen.width + 2 * NotchGeometry.earRadius)
    }
}

struct HitRectTests {
    private var layout: CapsuleLayout {
        CapsuleLayout(notch: NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1710, height: 1107), safeAreaTop: 33.5,
                                           auxLeft: CGRect(x: 0, y: 1073.5, width: 762.5, height: 33.5),
                                           auxRight: CGRect(x: 947.5, y: 1073.5, width: 762.5, height: 33.5), menuBarHeight: 33.5))
    }

    @Test func compactHitRectCoversTheHoverStatesButNotFarAway() {
        let layout = layout
        let hit = layout.hitRect(for: .compact)
        let body = layout.bodyRect(for: .compact)
        #expect(hit.contains(CGPoint(x: body.midX, y: body.midY)))
        #expect(hit.contains(CGPoint(x: body.minX + 5, y: body.minY - 30))) // inside the song-info area
        #expect(!hit.contains(CGPoint(x: body.maxX + 100, y: body.midY)))   // far to the right: click-through
        #expect(!hit.contains(CGPoint(x: body.midX, y: body.minY - 120)))
    }

    @Test func expandedHitRectMatchesTheBody() {
        let layout = layout
        let body = layout.bodyRect(for: .expanded)
        let hit = layout.hitRect(for: .expanded)
        #expect(hit.contains(CGPoint(x: body.midX, y: body.midY)))
        #expect(!hit.contains(CGPoint(x: body.maxX + 40, y: body.midY)))
    }
}

struct IslandPlannerTests {
    private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    private let main = CGRect(x: 755, y: 1075, width: 200, height: 32)
    private func act(_ id: String, secondary: Bool = true, width: CGFloat = 60) -> LiveActivity {
        LiveActivity(id: id, moduleID: id, symbolName: "circle", canBeSecondary: secondary, secondaryWidth: width)
    }
    private func plan(_ activities: [LiveActivity], _ settings: IslandSettings = IslandSettings()) -> [IslandPlacement] {
        IslandPlanner.plan(mainRect: main, ear: 8, screenFrame: screen, menuBarHeight: 32, activities: activities, settings: settings)
    }

    @Test func noActivityNoIslands() { #expect(plan([]).isEmpty) }

    @Test func singleActivityIsOnlyTheMainIsland() {
        let result = plan([act("media")])
        #expect(result.count == 1 && result[0].role == .main && result[0].rect == main)
    }

    @Test func mainPlusOneSecondaryGoesToPrioritySide() {
        let result = plan([act("media"), act("timer")])
        #expect(result.count == 2 && result[1].side == .right)
        #expect(result[1].rect.minX > main.maxX)
        var left = IslandSettings()
        left.prioritySide = .left
        #expect(plan([act("media"), act("timer")], left)[1].side == .left)
    }

    @Test func twoSecondariesBothSides() {
        let result = plan([act("media"), act("timer"), act("reminders")])
        #expect(result.count == 3)
        #expect(result[1].side == .right && result[2].side == .left)
    }

    @Test func oneSideOnlyStacksByLevelNearestFirst() {
        var settings = IslandSettings()
        settings.leftEnabled = false
        let result = plan([act("media"), act("timer"), act("reminders")], settings)
        #expect(result.count == 3 && result[1].side == .right && result[2].side == .right)
        #expect(result[1].rect.maxX <= result[2].rect.minX)
    }

    @Test func prioritySideDisabledFallsToOtherSide() {
        var settings = IslandSettings()
        settings.rightEnabled = false
        #expect(plan([act("media"), act("timer")], settings)[1].side == .left)
    }

    @Test func bothSidesOffMeansMainOnly() {
        var settings = IslandSettings()
        settings.leftEnabled = false
        settings.rightEnabled = false
        #expect(plan([act("media"), act("timer")], settings).count == 1)
    }

    @Test func mainOnlyActivitiesNeverBecomeSecondary() {
        #expect(plan([act("media"), act("timer", secondary: false)]).count == 1)
    }

    @Test func lowestLevelDropsWhenSpaceRunsOut() {
        var settings = IslandSettings()
        settings.maxSpanFraction = 0.15 // 256 pt: main 200 + 16 ears is already most of it
        #expect(plan([act("media"), act("timer"), act("reminders")], settings).count == 1)
        settings.maxSpanFraction = 0.2 // 342 pt: fits one 60 pt island but not two
        let result = plan([act("media"), act("timer"), act("reminders")], settings)
        #expect(result.count == 2 && result[1].id == "timer")
    }

    @Test func sinkingMovesIslandsBelowTheMenuBar() {
        var settings = IslandSettings()
        settings.sinking = true
        #expect(plan([act("media"), act("timer")], settings)[1].rect.maxY == screen.maxY - 32)
    }

    @Test func manualOffsetAndBoundsApply() {
        var settings = IslandSettings()
        settings.rightOffset = 10
        let base = plan([act("media"), act("timer")])[1].rect.minX
        #expect(plan([act("media"), act("timer")], settings)[1].rect.minX == base + 10)
        settings.leftBound = 700
        settings.prioritySide = .left
        #expect(plan([act("media"), act("timer")], settings).count == 1)
    }

    @Test func menuWindowDetection() {
        let layer = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let bounds = CGRect(x: 400, y: 32, width: 200, height: 300)
        #expect(MenuBarMenuDetector.isMenuWindow(layer: layer, bounds: bounds, screenTop: 0, menuBarHeight: 32, xRange: 0...1710))
        #expect(!MenuBarMenuDetector.isMenuWindow(layer: 0, bounds: bounds, screenTop: 0, menuBarHeight: 32, xRange: 0...1710))
        #expect(!MenuBarMenuDetector.isMenuWindow(layer: layer, bounds: bounds.offsetBy(dx: 0, dy: 300), screenTop: 0, menuBarHeight: 32, xRange: 0...1710))
    }
}
