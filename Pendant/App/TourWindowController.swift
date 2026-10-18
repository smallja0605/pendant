import AppKit
import SwiftUI

/// The first-run tour: a small glass window with a welcome page, one page per basic feature (picture, what it does, and the
/// switch that matters for it) and a last page. Shown once after the first launch; "重新觀看導覽" in the settings opens it again.
@MainActor
final class TourWindowController: NSObject, NSWindowDelegate {
    static let shared = TourWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        if window == nil { window = makeWindow() }
        guard let window else { return }
        window.center()
        WindowPresence.opened(window)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        AppSettings.shared.tourSeen = true
        window?.close()
    }

    private func makeWindow() -> NSWindow {
        let window = FreeWindow.hosting(TourView(onFinish: { [weak self] in self?.finish() }))
        window.title = "Pendant Tour"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 760, height: 580))
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    /// Closing the window by any means counts as "seen": the tour never nags.
    func windowWillClose(_ notification: Notification) {
        AppSettings.shared.tourSeen = true
    }
}
