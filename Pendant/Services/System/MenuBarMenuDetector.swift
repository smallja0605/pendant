import AppKit
import CoreGraphics

/// Detects an open menu under the menu bar (3.5.8 ②) from the window list. Only layer and bounds are read, which
/// needs no screen-recording permission.
enum MenuBarMenuDetector {
    /// Pure test: does a window of a menu level reach up to the menu bar of the given screen band?
    /// Everything is in CoreGraphics display coordinates (origin top-left, y grows downward).
    static func isMenuWindow(layer: Int, bounds: CGRect, screenTop: CGFloat, menuBarHeight: CGFloat, xRange: ClosedRange<CGFloat>) -> Bool {
        guard layer == Int(CGWindowLevelForKey(.popUpMenuWindow)) else { return false }
        guard bounds.maxX >= xRange.lowerBound, bounds.minX <= xRange.upperBound else { return false }
        // A drop-down menu starts right under the menu bar.
        return bounds.minY <= screenTop + menuBarHeight + 6 && bounds.minY >= screenTop - 2 && bounds.height > 8
    }

    /// `screenFrame` is the AppKit frame of the screen the islands are on.
    static func isMenuOpen(on screenFrame: CGRect, menuBarHeight: CGFloat) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        // AppKit y (up) → CoreGraphics y (down), relative to the primary display's top edge.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let screenTop = primaryHeight - screenFrame.maxY
        let range = screenFrame.minX...screenFrame.maxX
        for window in info {
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { continue }
            if isMenuWindow(layer: layer, bounds: bounds, screenTop: screenTop, menuBarHeight: menuBarHeight, xRange: range) {
                return true
            }
        }
        return false
    }
}
