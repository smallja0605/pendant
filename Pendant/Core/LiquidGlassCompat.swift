import SwiftUI

/// Every macOS 26-only visual API is isolated here (requirements 2.1); the rest of the code never calls
/// them directly, so older systems degrade to standard materials automatically.
enum LiquidGlass {
    /// Liquid Glass exists only on macOS 26+; the "Liquid" settings tab is hidden elsewhere.
    static var isAvailable: Bool {
        if #available(macOS 26, *) { true } else { false }
    }

    /// Respect Reduce Transparency: glass is switched off when the system asks for less transparency.
    static var isEnabled: Bool {
        isAvailable && AppSettings.shared.liquidGlassEnabled
    }
}

extension View {
    /// Glass for interactive controls on macOS 26+, a thin material elsewhere.
    @ViewBuilder func pendantControlBackground(cornerRadius: CGFloat = 10) -> some View {
        if #available(macOS 26, *), LiquidGlass.isEnabled {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
