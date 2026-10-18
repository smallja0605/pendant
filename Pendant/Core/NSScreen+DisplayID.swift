import AppKit

extension NSScreen {
    /// Stable identifier of the physical display, used to keep one notch per screen.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
