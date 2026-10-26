import SwiftUI

extension CapsuleView {
    /// Which half of the compact capsule the pointer is over, from its position over the whole body (one tracking area
    /// instead of one per icon: those could miss the pointer crossing from one to the other).
    @MainActor func updateCompactHover(at location: CGPoint?, bodyWidth: CGFloat) {
        guard model.state == .compact else { return }
        guard let location else {
            model.setCompactHover(nil)
            return
        }
        let notch = model.layout?.notch.size ?? .zero
        let middle = notch.width + (model.layout?.virtualMiddleExtra ?? 0) // a long lyric line widens the middle, not the wings
        let wing = max((bodyWidth - middle) / 2, notch.height)
        model.setCompactHover(location.x < wing ? .artwork : (location.x > bodyWidth - wing ? .controls : nil))
    }
}
