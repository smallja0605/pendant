import AppKit
import SwiftUI

/// Delivers trackpad / mouse-wheel scrolling that happens over the modified view.
/// `deltaX`/`deltaY` follow the content direction the user sees (natural scrolling already applied),
/// in points. Events handled here are consumed so they do not scroll anything underneath.
private struct ScrollWheelCapture: NSViewRepresentable {
    /// Return true to consume the event (it then does not scroll anything underneath).
    var onScroll: (_ deltaX: Double, _ deltaY: Double) -> Bool
    /// Points one wheel notch is worth for this view (a mouse wheel; a trackpad reports points itself), before the user's sensitivity.
    var wheelUnit = 10.0
    /// A wheel turned without shift still drives a sideways view: its vertical turns count as horizontal ones.
    var wheelIsHorizontal = false
    /// Phase-aware handler (replaces `onScroll` when set).
    var onPhased: ((_ deltaX: Double, _ deltaY: Double, _ phase: ScrollPhase) -> Bool)?

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onScroll = onScroll
        view.onPhased = onPhased
        view.wheelUnit = wheelUnit
        view.wheelIsHorizontal = wheelIsHorizontal
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onScroll = onScroll
        view.onPhased = onPhased
        view.wheelUnit = wheelUnit
        view.wheelIsHorizontal = wheelIsHorizontal
    }

    final class CaptureView: NSView {
        var onScroll: ((Double, Double) -> Bool)?
        var onPhased: ((Double, Double, ScrollPhase) -> Bool)?
        var wheelUnit = 10.0
        var wheelIsHorizontal = false
        private var monitor: Any?

        // Never intercept clicks / drags: SwiftUI gestures underneath keep working.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Leaving the window (view removed) also lands here with `window == nil`, which removes the monitor.
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window, event.window === window else { return event }
                let point = convert(event.locationInWindow, from: nil)
                guard bounds.contains(point) else { return event }
                Log.trace("scroll in view dx=\(event.scrollingDeltaX) dy=\(event.scrollingDeltaY)")
                let (deltaX, deltaY) = scaledDeltas(of: event)
                let consumed: Bool
                if let onPhased {
                    var phase = ScrollPhase(event)
                    phase.location = CGPoint(x: point.x, y: bounds.height - point.y)
                    consumed = onPhased(deltaX, deltaY, phase)
                } else {
                    consumed = onScroll?(deltaX, deltaY) ?? false
                }
                return consumed ? nil : event
            }
        }

        /// A trackpad reports points. A wheel reports lines (one notch is one line, more when it spins fast): each line is
        /// `wheelUnit` points times the sensitivity setting, so one notch moves exactly one step of the view.
        private func scaledDeltas(of event: NSEvent) -> (Double, Double) {
            if event.hasPreciseScrollingDeltas { return (event.scrollingDeltaX, event.scrollingDeltaY) }
            var lineX = event.scrollingDeltaX, lineY = event.scrollingDeltaY
            if wheelIsHorizontal, abs(lineX) < abs(lineY) { (lineX, lineY) = (lineY, 0) }
            let points = wheelUnit * MainActor.assumeIsolated { AppSettings.shared.wheelSensitivity }
            return (lineX * points, lineY * points)
        }
    }
}

/// Where an event is in a trackpad gesture. A mouse wheel has no phases (`hasPhase == false`).
struct ScrollPhase: Sendable {
    var hasPhase: Bool
    /// First event of a gesture (fingers just started scrolling).
    var began: Bool
    /// Fingers lifted (or the gesture was cancelled); momentum events may still follow.
    var ended: Bool
    /// Inertia after the fingers lifted.
    var momentum: Bool
    /// Pointer position inside the capture view (top-left origin).
    var location = CGPoint.zero

    init(_ event: NSEvent) {
        hasPhase = event.phase != [] || event.momentumPhase != []
        began = event.phase.contains(.began) || event.phase.contains(.mayBegin)
        ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        momentum = event.momentumPhase != []
    }
}

extension View {
    /// Phase-aware variant: the handler sees gesture start / end and momentum, and decides per event whether it consumes it.
    func onScrollWheelPhased(_ action: @escaping (_ deltaX: Double, _ deltaY: Double, _ phase: ScrollPhase) -> Bool) -> some View {
        background(ScrollWheelCapture(onScroll: { _, _ in false }, onPhased: action))
    }

    /// Observe two-finger trackpad scrolling (or wheel) over this view.
    /// `wheelUnit`: points one mouse-wheel notch is worth here (the view's size of one step); `wheelIsHorizontal`: a sideways view.
    func onScrollWheel(wheelUnit: Double = 10, wheelIsHorizontal: Bool = false,
                       perform action: @escaping (_ deltaX: Double, _ deltaY: Double) -> Void) -> some View {
        background(ScrollWheelCapture(onScroll: { deltaX, deltaY in
            action(deltaX, deltaY)
            return true
        }, wheelUnit: wheelUnit, wheelIsHorizontal: wheelIsHorizontal))
    }

    /// Like `onScrollWheel(perform:)` but the handler decides per event whether it consumes it.
    func onScrollWheelConsuming(wheelUnit: Double = 10, wheelIsHorizontal: Bool = false,
                                _ action: @escaping (_ deltaX: Double, _ deltaY: Double) -> Bool) -> some View {
        background(ScrollWheelCapture(onScroll: action, wheelUnit: wheelUnit, wheelIsHorizontal: wheelIsHorizontal))
    }
}
