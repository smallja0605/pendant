import SwiftUI

/// 擠換 (squeeze swap): two pieces of content take each other's place in the same spot, the way the volume / brightness HUD takes the
/// place of the capsule's contents — the one going away blurs, fades and shrinks a little, then the one coming in blurs in, fades in
/// and grows to its size. Put it on both, with opposite `isShown`.
struct SqueezeSwap: ViewModifier {
    let isShown: Bool

    func body(content: Content) -> some View {
        content.modifier(RevealEffect(isVisible: isShown, delay: 0.14, blurOnExit: true))
    }
}
