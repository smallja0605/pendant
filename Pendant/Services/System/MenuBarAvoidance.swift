import AppKit
import ApplicationServices

/// 3.5.8 ⑥ (experimental): reads the frontmost app's menu bar items through the Accessibility API so the islands
/// can stay clear of them. Needs the Accessibility permission; without it (or on any failure) it returns nil and the
/// manual offsets (⑤) apply.
enum MenuBarAvoidance {
    /// Right edge (screen x) of the frontmost app's menu items, plus a little room; nil if unavailable.
    static func appMenusRightEdge() -> CGFloat? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &bar) == .success,
              let barRef = bar, CFGetTypeID(barRef) == AXUIElementGetTypeID() else { return nil }
        var children: CFTypeRef?
        // swiftlint:disable:next force_cast
        guard AXUIElementCopyAttributeValue(barRef as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return nil }
        var maxX: CGFloat = 0
        for item in items {
            var position: CFTypeRef?
            var size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success,
                  let positionValue = position, let sizeValue = size else { continue }
            var origin = CGPoint.zero
            var extent = CGSize.zero
        // swiftlint:disable:next force_cast
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin)
        // swiftlint:disable:next force_cast
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &extent)
            maxX = max(maxX, origin.x + extent.width)
        }
        return maxX > 0 ? maxX + 8 : nil
    }
}
