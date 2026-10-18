import AppKit
import SwiftUI

/// The "Pendant" settings window: a glass window with a floating sidebar (no title bar, no toolbar, no seams).
/// Built with AppKit because SwiftUI's `Settings` scene cannot be opened reliably from an agent app.
@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let selection = SettingsSelection()

    /// The settings tab to reopen after an update restarted the app (nil when the window was not open).
    private static let reopenKey = "update.reopenSettingsTab"

    var isVisible: Bool { window?.isVisible == true }

    /// Remembers an open settings window across the update's restart.
    func rememberForRestart() {
        guard isVisible else { return }
        UserDefaults.standard.set(selection.tab.rawValue, forKey: Self.reopenKey)
    }

    /// At launch: brings the settings window back if the app restarted itself while it was open.
    func reopenIfRememberedBeforeRestart() {
        guard let raw = UserDefaults.standard.string(forKey: Self.reopenKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.reopenKey)
        show(tab: SettingsTab(rawValue: raw))
    }

    func show(tab: SettingsTab? = nil) {
        if let tab { selection.tab = tab }
        if window == nil { window = makeWindow() }
        if let window { WindowPresence.opened(window) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let content = SettingsView(
            selection: selection,
            onShowTour: { TourWindowController.shared.show() },
            onWindowAction: { [weak self] action in self?.perform(action) }
        )
        #if DEBUG
        // PENDANT_DEBUG_SETTINGS_SCALE=0.6: lays the page out at full size but shows it shrunk, so a long page fits one screenshot.
        let debugScale = ProcessInfo.processInfo.environment["PENDANT_DEBUG_SETTINGS_SCALE"].flatMap(Double.init).map { CGFloat($0) }
        let root: AnyView = debugScale.map { scale in
            let height = (NSScreen.main?.visibleFrame.height ?? 900) - 10
            return AnyView(content.frame(width: 900, height: height / scale).scaleEffect(scale, anchor: .topLeading)
                .frame(width: 900 * scale, height: height, alignment: .topLeading))
        } ?? AnyView(content)
        let hosting = NSHostingController(rootView: root)
        #else
        let hosting = NSHostingController(rootView: content)
        #endif
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Pendant"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentMinSize = NSSize(width: 820, height: 600)
        window.setContentSize(NSSize(width: 900, height: 820))
        #if DEBUG
        if let scale = ProcessInfo.processInfo.environment["PENDANT_DEBUG_SETTINGS_SCALE"].flatMap(Double.init) {
            window.contentMinSize = .zero
            window.setContentSize(NSSize(width: 900 * scale, height: (NSScreen.main?.visibleFrame.height ?? 900) - 10))
        }
        #endif
        window.isReleasedWhenClosed = false
        // The sidebar draws its own traffic lights: the system's sit across the sidebar's edge.
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(kind)?.isHidden = true
        }
        window.center()
        return window
    }

    private func perform(_ action: SettingsWindowAction) {
        switch action {
        case .close: window?.performClose(nil)
        case .minimize: window?.miniaturize(nil)
        case .zoom: window?.zoom(nil)
        }
    }
}
