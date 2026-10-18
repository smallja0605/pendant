import AppKit

/// Borderless, non-activating panel that hosts the capsule. Never takes focus from other apps.
final class NotchPanel: NSPanel {
    /// Becomes key only while the capsule is expanded and the user clicked into it (Esc, text input).
    var allowsKey = false
    var onEscape: (() -> Void)?
    var onRightClick: (() -> Void)?
    /// Keyboard navigation of the open capsule: ←/→ step the tab, ⌘1…⌘9 jump to one.
    var onTabStep: ((Int) -> Void)?
    var onTabNumber: ((Int) -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar + 1
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        // Idle state is click-through; the controller flips this per capsule state.
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .rightMouseDown {
            onRightClick?()
            return
        }
        if event.type == .leftMouseDown, allowsKey, !isKeyWindow { makeKey() }
        super.sendEvent(event)
    }

    /// Only reached when no text field / control in the capsule used the key (so note editing keeps its arrow keys).
    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 123 where flags.isEmpty: onTabStep?(-1) // ←
        case 124 where flags.isEmpty: onTabStep?(1) // →
        default:
            if flags == .command, let digit = event.charactersIgnoringModifiers.flatMap(Int.init), (1...9).contains(digit) {
                onTabNumber?(digit)
            } else {
                super.keyDown(with: event)
            }
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
