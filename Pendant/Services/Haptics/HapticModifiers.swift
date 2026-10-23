import AppKit
import SwiftUI

extension View {
    /// The pointing hand over an actionable control (no haptic: hovering does not buzz).
    func hapticOnHover() -> some View {
        modifier(HoverHapticModifier())
    }
}

private struct HoverHapticModifier: ViewModifier {
    @State private var isInside = false

    func body(content: Content) -> some View {
        content.onActiveHover { location in
            let inside = location != nil
            // Clickable things show the pointing hand (a text field next to them would otherwise keep the I-beam).
            if inside { NSCursor.pointingHand.set() } else if isInside { NSCursor.arrow.set() }
            isInside = inside
        }
    }
}
