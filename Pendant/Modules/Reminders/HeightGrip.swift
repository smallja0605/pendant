import AppKit
import SwiftUI

/// The handle at the bottom of the detailed reminders page: drag it up or down to change the capsule's height. The height is not
/// remembered: it goes back when the page is closed (`ModuleRegistry.focusExtraHeight`).
struct HeightGrip: View {
    @State private var registry = ModuleRegistry.shared
    @State private var hovering = false
    @State private var startMouse: CGFloat?
    @State private var startExtra: CGFloat = 0

    var body: some View {
        Capsule()
            .fill(.white.opacity(hovering || startMouse != nil ? 0.55 : 0.22))
            .frame(width: 44, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 16)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            // The capsule's bottom edge moves with the pointer, so the drag is measured on the screen (not in the view's coordinates).
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        let mouse = NSEvent.mouseLocation.y
                        if startMouse == nil {
                            startMouse = mouse
                            startExtra = registry.focusExtraHeight
                            registry.isResizingFocus = true
                        }
                        registry.focusExtraHeight = min(max(startExtra + (startMouse ?? mouse) - mouse, -80), 400)
                    }
                    .onEnded { _ in
                        startMouse = nil
                        registry.isResizingFocus = false
                    }
            )
            .onDisappear { registry.isResizingFocus = false }
            .accessibilityLabel("調整高度")
    }
}
