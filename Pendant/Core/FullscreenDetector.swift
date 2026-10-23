import AppKit

/// Is an app full screen on a screen (the green button: the window has a Space of its own and covers the whole screen, menu bar
/// included)? The virtual notch hides itself then (settings › 虛擬瀏海). Reads only window frames and owners; no screen-recording
/// permission is involved. A window merely maximized (zoomed) starts below the menu bar and does not count.
enum FullscreenDetector {
    /// Whether the frontmost window that takes up a real part of the screen covers all of it, give or take a point or two.
    static func topWindowIsFullscreen(frames: [CGRect], screen: CGRect, tolerance: CGFloat = 2) -> Bool {
        let minimumShare: CGFloat = 0.3
        for frame in frames {
            let overlap = frame.intersection(screen)
            guard !overlap.isNull, overlap.width * overlap.height >= screen.width * screen.height * minimumShare else { continue }
            return frame.minX <= screen.minX + tolerance && frame.maxX >= screen.maxX - tolerance
                && frame.minY <= screen.minY + tolerance && frame.maxY >= screen.maxY - tolerance
        }
        return false
    }

    static func isFullscreen(on screen: NSScreen) -> Bool {
        #if DEBUG
        // PENDANT_DEBUG_COVERED=1: pretends an app is full screen everywhere (to look at the hidden state).
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_COVERED"] != nil { return true }
        #endif
        guard let primary = NSScreen.screens.first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        // Window bounds are in "global display" coordinates (origin top left of the primary screen); AppKit's are bottom left.
        let frame = CGRect(x: screen.frame.minX, y: primary.frame.height - screen.frame.maxY,
                           width: screen.frame.width, height: screen.frame.height)
        let me = ProcessInfo.processInfo.processIdentifier
        var frames: [CGRect] = [] // front to back
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32).map({ $0 != me }) ?? false,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo)
            else { continue }
            frames.append(bounds)
        }
        return topWindowIsFullscreen(frames: frames, screen: frame)
    }
}
