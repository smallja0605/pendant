import AppKit
import SwiftUI

extension View {
    /// Light `.generic` tick when the cursor enters an actionable control (5.1).
    func hapticOnHover() -> some View {
        modifier(HoverHapticModifier())
    }
}

private struct HoverHapticModifier: ViewModifier {
    @State private var isInside = false

    func body(content: Content) -> some View {
        content.onActiveHover { location in
            let inside = location != nil
            if inside, !isInside { HapticService.shared.play(.hoverControl) }
            // Clickable things show the pointing hand (a text field next to them would otherwise keep the I-beam).
            if inside { NSCursor.pointingHand.set() } else if isInside { NSCursor.arrow.set() }
            isInside = inside
        }
    }
}
