import AppKit

/// Menu bar icon with: open settings, pause, quit.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let pauseItem = NSMenuItem()
    /// "有新版本 vX.Y.Z" (hidden until the updater finds one); opens the About tab.
    private let updateItem = NSMenuItem()
    var onOpenAbout: (() -> Void)?

    var onPauseChanged: ((Bool) -> Void)?

    /// Show / hide the menu bar icon (setting). The notch context menu remains available either way.
    var isIconVisible: Bool {
        get { statusItem.isVisible }
        set { statusItem.isVisible = newValue }
    }
    var onToggleDebugActivity: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenTuning: (() -> Void)?
    var onMenuTracking: ((Bool) -> Void)?

    private(set) var isPaused = false {
        didSet {
            updatePauseTitle()
            onPauseChanged?(isPaused)
        }
    }

    override init() {
        super.init()
        configureButton()
        statusItem.menu = makeMenu()
        updatePauseTitle()
    }

    private func configureButton() {
        let image = NSImage(systemSymbolName: "lamp.desk.fill", accessibilityDescription: "Pendant")
            ?? NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Pendant")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let settings = NSMenuItem(
            title: String(localized: "menu.settings", defaultValue: "設定⋯"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)
        updateItem.action = #selector(openAbout)
        updateItem.target = self
        updateItem.isHidden = true
        menu.addItem(updateItem)

        // Hidden developer entry: only visible while ⌥ is held (⌥⌘,).
        let developer = NSMenuItem(title: "開發者選項…", action: #selector(openTuning), keyEquivalent: ",")
        developer.keyEquivalentModifierMask = [.command, .option]
        developer.isAlternate = true
        developer.target = self
        menu.addItem(developer)

        pauseItem.action = #selector(togglePause)
        pauseItem.target = self
        menu.addItem(pauseItem)

        #if DEBUG
        let debug = NSMenuItem(title: "切換小膠囊(除錯)", action: #selector(toggleDebugActivity), keyEquivalent: "")
        debug.target = self
        menu.addItem(debug)

        #endif

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: "menu.quit", defaultValue: "結束 Pendant"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func updatePauseTitle() {
        pauseItem.title = isPaused
            ? String(localized: "menu.resume", defaultValue: "繼續")
            : String(localized: "menu.pause", defaultValue: "暫停")
    }

    /// Shows or hides the update notice in the menu.
    func setAvailableUpdate(_ version: String?) {
        updateItem.isHidden = version == nil
        if let version { updateItem.title = tr("有新版本 \(version)⋯") }
    }

    func menuWillOpen(_ menu: NSMenu) {
        onMenuTracking?(true)
    }

    func menuDidClose(_ menu: NSMenu) {
        onMenuTracking?(false)
    }

    @objc private func openAbout() {
        onOpenAbout?()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func togglePause() {
        isPaused.toggle()
    }

    @objc private func openTuning() {
        onOpenTuning?()
    }

    @objc private func toggleDebugActivity() {
        onToggleDebugActivity?()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
