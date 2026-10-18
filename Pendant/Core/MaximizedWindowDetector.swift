import AppKit

/// Is a normal window of another app maximized on a screen (it fills the area between the menu bar and the Dock)? The virtual notch
/// hides itself then (settings › 虛擬瀏海). Reads only window frames and owners; no screen-recording permission is involved.
enum MaximizedWindowDetector {
    /// Whether `window` covers `visible` (both in the same coordinate space), give or take a few points.
    static func covers(window: CGRect, visible: CGRect, tolerance: CGFloat = 6) -> Bool {
        window.minX <= visible.minX + tolerance && window.maxX >= visible.maxX - tolerance
            && window.minY <= visible.minY + tolerance && window.maxY >= visible.maxY - tolerance
    }

    static func isWindowMaximized(on screen: NSScreen) -> Bool {
        #if DEBUG
        // PENDANT_DEBUG_COVERED=1: pretends a window is maximized everywhere (to look at the hidden state).
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_COVERED"] != nil { return true }
        #endif
        guard let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        // Window bounds are in "global display" coordinates (origin top left of the primary screen); AppKit's are bottom left.
        let visibleAppKit = screen.visibleFrame
        let visible = CGRect(x: visibleAppKit.minX, y: primary.frame.height - visibleAppKit.maxY,
                             width: visibleAppKit.width, height: visibleAppKit.height)
        let me = ProcessInfo.processInfo.processIdentifier
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32).map({ $0 != me }) ?? false,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { continue }
            if covers(window: bounds, visible: visible) { return true }
        }
        return false
    }
}
