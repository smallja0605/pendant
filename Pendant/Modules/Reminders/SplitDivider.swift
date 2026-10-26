import AppKit
import SwiftUI

/// The line between the list and the new-item box of the detailed reminders page: drag it sideways to change how much room each gets
/// (5 : 5 to start). Like the height, the split goes back when the page is closed (`ModuleRegistry.focusSplit`).
struct SplitDivider: View {
    /// The width the two boxes share (the divider's own width excluded).
    let room: CGFloat
    @State private var registry = ModuleRegistry.shared
    @State private var hovering = false
    @State private var startMouse: CGFloat?
    @State private var startSplit: CGFloat = 0.5

    var body: some View {
        Rectangle()
            .fill(.white.opacity(hovering || startMouse != nil ? 0.4 : 0.18))
            .frame(width: 2)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            // The page moves nothing under the pointer sideways, but the screen position is still the steadiest measure.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        let mouse = NSEvent.mouseLocation.x
                        if startMouse == nil {
                            startMouse = mouse
                            startSplit = registry.focusSplit
                        }
                        let moved = mouse - (startMouse ?? mouse)
                        registry.focusSplit = min(max(startSplit + moved / room, 0.25), 0.75)
                    }
                    .onEnded { _ in startMouse = nil }
            )
    }
}
