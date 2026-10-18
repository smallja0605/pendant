import AppKit

/// The app is an agent (no Dock icon, not in Cmd-Tab). While one of its windows (settings, developer options)
/// is open it becomes a regular app so the window can be reached with Cmd-Tab; it goes back when the last
/// window closes.
@MainActor
enum WindowPresence {
    private static var open = Set<ObjectIdentifier>()
    private static var observers: [ObjectIdentifier: NSObjectProtocol] = [:]

    static func opened(_ window: NSWindow) {
        let id = ObjectIdentifier(window)
        if observers[id] == nil {
            observers[id] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated { closed(id) }
            }
        }
        open.insert(id)
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    private static func closed(_ id: ObjectIdentifier) {
        open.remove(id)
        if open.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
