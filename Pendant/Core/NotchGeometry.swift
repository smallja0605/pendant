import CoreGraphics

/// Pure notch-geometry math (no AppKit dependencies) so it can be unit tested.
/// All rects are in global screen coordinates (origin bottom-left, like `NSScreen.frame`).
struct NotchGeometry: Equatable, Sendable {
    /// Notch size used on screens without a physical notch.
    static let virtualSize = CGSize(width: 185, height: 32)
    /// Width of the middle part of a virtual notch that carries content (clock): narrower, there is no physical notch to fit around.
    static let virtualContentWidth: CGFloat = 128
    /// Radius of the reverse (concave) corners where the notch meets the menu bar.
    static let earRadius: CGFloat = 8
    /// Extra tolerance around the notch for hover detection (requirements 3.4: 2–4 pt).
    static let triggerMargin: CGFloat = 3

    var screenFrame: CGRect
    var size: CGSize
    var isVirtual: Bool
    /// Floating capsule (virtual notch only): the gap between the screen's top edge and the capsule.
    var floatGap: CGFloat = 0

    /// - Parameters:
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top` (0 on screens without a notch).
    ///   - auxLeft / auxRight: `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
    ///   - menuBarHeight: fallback height for the virtual notch.
    ///   - widthAdjustment: user fine-tuning added to the detected width.
    init(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxLeft: CGRect?,
        auxRight: CGRect?,
        menuBarHeight: CGFloat,
        widthAdjustment: CGFloat = 0
    ) {
        self.screenFrame = screenFrame
        if safeAreaTop > 0, let left = auxLeft, let right = auxRight {
            let width = max(screenFrame.width - left.width - right.width, 0)
            size = CGSize(width: max(width + widthAdjustment, 40), height: safeAreaTop)
            isVirtual = false
        } else {
            let height = menuBarHeight > 0 ? menuBarHeight : Self.virtualSize.height
            size = CGSize(width: max(Self.virtualSize.width + widthAdjustment, 40), height: height)
            isVirtual = true
        }
    }

    /// The notch body, flush with the top edge of the screen and horizontally centred.
    var notchRect: CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - floatGap - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Frame of the idle panel: the notch plus the reverse-corner ears on both sides.
    var panelFrame: CGRect {
        notchRect.insetBy(dx: -Self.earRadius, dy: 0)
    }

    /// Hover trigger zone: slightly larger than the notch, extending to the screen top edge.
    var triggerRect: CGRect {
        var rect = notchRect.insetBy(dx: -Self.triggerMargin, dy: -Self.triggerMargin)
        rect.size.height += Self.triggerMargin + floatGap // allow the cursor to hit the very top edge
        rect.origin.y = min(rect.origin.y, notchRect.minY - Self.triggerMargin)
        return rect
    }

    func isInTriggerZone(_ point: CGPoint) -> Bool {
        triggerRect.containsPointer(point)
    }
}

extension NotchGeometry {
    /// Used only while no screen is available (the capsule is hidden then).
    static let placeholder = NotchGeometry(screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0,
                                           auxLeft: nil, auxRight: nil, menuBarHeight: 24)
}
