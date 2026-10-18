import AppKit
import SwiftUI

/// The app's windows. Their content sits in a plain container (see `hosting`); the system keeps them reachable (a title bar cannot
/// be dragged behind the menu bar) because nothing here overrides how a frame is constrained.
final class FreeWindow: NSWindow {
    // Borderless windows (the settings) would otherwise never become the key window.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// For a window without a title bar: decides from where the mouse went down (in the content view's coordinates, y from the top)
    /// and the view under it whether the press drags the window (SwiftUI content never lets the system drag by its background).
    var dragsWindow: ((_ point: NSPoint, _ hit: NSView?) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let dragsWindow, let content = contentView {
            let point = content.convert(event.locationInWindow, from: nil)
            let top = NSPoint(x: point.x, y: content.bounds.height - point.y)
            if dragsWindow(top, content.hitTest(point)) {
                performDrag(with: event)
                return
            }
        }
        super.sendEvent(event)
    }
}

extension FreeWindow {
    /// A window showing `view` as a plain subview of a container instead of being the window's own content view. As the content view,
    /// SwiftUI's hosting view resizes the window from its layout pass (`updateAnimatedWindowSize`) with a stale origin, which fought
    /// a drag across displays: the window lagged behind or jumped away from the pointer. Callers set the style and size afterwards.
    static func hosting<Content: View>(_ view: Content) -> FreeWindow {
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = []
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 100 || size.height < 100 { size = NSSize(width: 400, height: 300) }
        let window = FreeWindow(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container
        return window
    }
}
