import AppKit
import SwiftUI

/// The app's way to show any pop-up control: a real `NSPopover` under the control, with the system arrow,
/// native animation and material (Liquid Glass on macOS 26+). Being a separate window it may extend
/// below the capsule, so the capsule must stay open while it is shown (`onVisibilityChange`).
@MainActor
@Observable
final class AnchoredPopover: NSObject, NSPopoverDelegate {
    /// Number of popovers currently on screen (any owner); the capsule must not auto-collapse while > 0.
    private(set) static var openCount = 0
    static var isAnyOpen: Bool { openCount > 0 }

    private(set) var isShown = false
    @ObservationIgnored weak var anchor: NSView?
    @ObservationIgnored private var popover: NSPopover?
    @ObservationIgnored private var lastClose = Date.distantPast
    @ObservationIgnored var onVisibilityChange: ((Bool) -> Void)?

    /// Toggles the popover. `content` receives the popover so it can resize itself when its content changes.
    func toggle(size: NSSize, autoSize: Bool = false, edge: NSRectEdge = .minY, content: (AnchoredPopover) -> AnyView) {
        // A transient popover closes on the mouse-down of the very click that then fires the button's action;
        // without this guard that click would immediately reopen it, so the button could never close it.
        if Date().timeIntervalSince(lastClose) < 0.25 { return }
        if isShown { close() } else { show(size: size, autoSize: autoSize, edge: edge, content: content) }
    }

    /// `autoSize`: the popover fits its SwiftUI content instead of using `size`.
    func show(size: NSSize, autoSize: Bool = false, edge: NSRectEdge = .minY, content: (AnchoredPopover) -> AnyView) {
        guard !isShown, let anchor else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .vibrantDark)
        popover.delegate = self
        let hosting = NSHostingController(rootView: content(self))
        if autoSize {
            hosting.sizingOptions = [.preferredContentSize]
        } else {
            popover.contentSize = size
        }
        popover.contentViewController = hosting
        self.popover = popover
        // The anchor view is not flipped, so `.minY` is the edge below the control.
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: edge)
        isShown = true
        Self.openCount += 1
        onVisibilityChange?(true)
    }

    func resize(to size: NSSize) {
        popover?.contentSize = size
    }

    func close() {
        popover?.performClose(nil)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            popover = nil
            isShown = false
            Self.openCount = max(Self.openCount - 1, 0)
            lastClose = Date()
            onVisibilityChange?(false)
        }
    }
}

/// Invisible view that tells an `AnchoredPopover` where its control is.
struct PopoverAnchor: NSViewRepresentable {
    let popover: AnchoredPopover

    func makeNSView(context: Context) -> NSView {
        let view = AnchorView()
        popover.anchor = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        popover.anchor = view
    }

    private final class AnchorView: NSView {
        override var isFlipped: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
