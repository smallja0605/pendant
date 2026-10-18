import CoreGraphics
import Testing
@testable import Pendant

struct NotchGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)

    @Test func physicalNotchSizeFromAuxiliaryAreas() {
        let geo = NotchGeometry(
            screenFrame: screen, safeAreaTop: 33.5,
            auxLeft: CGRect(x: 0, y: 1073.5, width: 762.5, height: 33.5),
            auxRight: CGRect(x: 947.5, y: 1073.5, width: 762.5, height: 33.5),
            menuBarHeight: 33.5
        )
        #expect(!geo.isVirtual)
        #expect(geo.size == CGSize(width: 185, height: 33.5))
        #expect(geo.notchRect == CGRect(x: 762.5, y: 1073.5, width: 185, height: 33.5))
    }

    @Test func virtualNotchWhenNoSafeArea() {
        let geo = NotchGeometry(
            screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil, menuBarHeight: 24
        )
        #expect(geo.isVirtual)
        #expect(geo.size.height == 24)
        #expect(geo.notchRect.midX == screen.midX)
        #expect(geo.notchRect.maxY == screen.maxY)
    }

    @Test func widthAdjustmentIsAdditiveAndClamped() {
        let wider = NotchGeometry(
            screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil,
            menuBarHeight: 24, widthAdjustment: 10
        )
        #expect(wider.size.width == NotchGeometry.virtualSize.width + 10)
        let tiny = NotchGeometry(
            screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil,
            menuBarHeight: 24, widthAdjustment: -10_000
        )
        #expect(tiny.size.width == 40)
    }

    @Test func offsetScreenOrigin() {
        let external = CGRect(x: 1710, y: -200, width: 1920, height: 1080)
        let geo = NotchGeometry(screenFrame: external, safeAreaTop: 0, auxLeft: nil, auxRight: nil, menuBarHeight: 24)
        #expect(geo.notchRect.maxY == external.maxY)
        #expect(geo.notchRect.midX == external.midX)
    }

    @Test func triggerZoneIsSlightlyLargerThanNotch() {
        let geo = NotchGeometry(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil, menuBarHeight: 24)
        let n = geo.notchRect
        #expect(geo.isInTriggerZone(CGPoint(x: n.midX, y: n.midY)))
        #expect(geo.isInTriggerZone(CGPoint(x: n.minX - 2, y: n.midY)))
        #expect(geo.isInTriggerZone(CGPoint(x: n.midX, y: screen.maxY)))
        #expect(!geo.isInTriggerZone(CGPoint(x: n.minX - 10, y: n.midY)))
        #expect(!geo.isInTriggerZone(CGPoint(x: n.midX, y: n.minY - 10)))
    }

    @Test func panelFrameIncludesEars() {
        let geo = NotchGeometry(screenFrame: screen, safeAreaTop: 0, auxLeft: nil, auxRight: nil, menuBarHeight: 24)
        #expect(geo.panelFrame.width == geo.notchRect.width + 2 * NotchGeometry.earRadius)
        #expect(geo.panelFrame.midX == geo.notchRect.midX)
    }
}

struct PointerEdgeTests {
    @Test func pointerOnTheTopEdgeCountsAsInside() {
        let rect = CGRect(x: 100, y: 1066, width: 288, height: 41) // maxY == screen top (1107)
        #expect(!rect.contains(CGPoint(x: 200, y: 1107)))          // why the plain API was wrong
        #expect(rect.containsPointer(CGPoint(x: 200, y: 1107)))
        #expect(rect.containsPointer(CGPoint(x: 100, y: 1066)))
        #expect(!rect.containsPointer(CGPoint(x: 99.9, y: 1080)))
        #expect(!rect.containsPointer(CGPoint(x: 200, y: 1107.1)))
    }

    @Test func compactHitRectIncludesTheScreenTopEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1107)
        let layout = CapsuleLayout(notch: NotchGeometry(screenFrame: screen, safeAreaTop: 33.5,
                                                        auxLeft: CGRect(x: 0, y: 1073.5, width: 762.5, height: 33.5),
                                                        auxRight: CGRect(x: 947.5, y: 1073.5, width: 762.5, height: 33.5),
                                                        menuBarHeight: 33.5))
        for state in [CapsuleState.idle, .compact, .expanded] {
            #expect(layout.hitRect(for: state).containsPointer(CGPoint(x: screen.midX, y: screen.maxY)))
            #expect(layout.triggerRect(for: state).containsPointer(CGPoint(x: screen.midX, y: screen.maxY)))
        }
    }
}
