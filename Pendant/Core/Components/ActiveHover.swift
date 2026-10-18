import AppKit
import SwiftUI

/// Hover tracking that also works in the capsule's non-activating, never-key panel, where SwiftUI's
/// own `onHover` does not fire. Reports the pointer position in the view's top-left coordinate space,
/// or nil when it leaves. Never intercepts clicks.
private struct ActiveHoverView: NSViewRepresentable {
    var sampled = false
    var onHover: (CGPoint?) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHover = onHover
        view.sampled = sampled
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onHover = onHover
        view.sampled = sampled
    }

    final class TrackingView: NSView {
        var onHover: ((CGPoint?) -> Void)?
        /// Poll the pointer on every display frame while inside (smooth even if mouse events are sparse).
        var sampled = false
        private var link: CADisplayLink?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) {
            report(event)
            guard sampled, link == nil else { return }
            let link = displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        override func mouseMoved(with event: NSEvent) { if !sampled { report(event) } }

        override func mouseExited(with event: NSEvent) {
            link?.invalidate()
            link = nil
            onHover?(nil)
        }

        @objc private func tick() {
            guard let window else { return }
            let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            if bounds.contains(point) { onHover?(point) }
        }

        private func report(_ event: NSEvent) {
            onHover?(convert(event.locationInWindow, from: nil))
        }
    }
}

extension View {
    /// `location` is nil when the pointer is outside.
    func onActiveHover(sampled: Bool = false, perform action: @escaping (CGPoint?) -> Void) -> some View {
        background(ActiveHoverView(sampled: sampled, onHover: action))
    }
}
