import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    var notchManager: NotchManager?
    /// Held for the app's lifetime: see `applicationDidFinishLaunching`.
    private var latencyActivity: NSObjectProtocol?
    private let hotkey = GlobalHotkey()
    let tuningWindow = TuningWindowController()

    private func applyHotkeySettings() {
        let settings = AppSettings.shared
        if settings.hotkeyEnabled {
            if !hotkey.register(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers) {
                Log.app.error("global hotkey could not be registered")
            }
        } else {
            hotkey.unregister()
        }
    }

    /// The menu-bar menu mentions a newer version as soon as the updater finds one.
    private func observeUpdates(_ status: StatusItemController) {
        withObservationTracking {
            _ = UpdateChecker.shared.state
        } onChange: { [weak self, weak status] in
            Task { @MainActor in
                guard let self, let status else { return }
                status.setAvailableUpdate(UpdateChecker.shared.availableRelease?.version.map { "v\($0)" })
                self.observeUpdates(status)
            }
        }
    }

    private func observeMenuBarIconSetting() {
        withObservationTracking {
            _ = AppSettings.shared.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.statusItemController?.isIconVisible = AppSettings.shared.showMenuBarIcon
                self.observeMenuBarIconSetting()
            }
        }
    }

    private func observeHotkeySettings() {
        withObservationTracking {
            let settings = AppSettings.shared
            _ = (settings.hotkeyEnabled, settings.hotkeyKeyCode, settings.hotkeyModifiers)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyHotkeySettings()
                self?.observeHotkeySettings()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !UninstallService.isUninstalling else { return } // nothing may be written back
        NoteStore.shared.flushSaves()
        ShelfStore.shared.applyAutoClearAtQuit()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyDefaultsMigration.run()
        AppPaths.migrateLegacyFolder() // before anything reads the notes or shelf folders
        // The app is a background (accessory) app, so macOS treats it as App Nap material: timers and event
        // delivery get coalesced and the main thread runs at lower priority. That made hover, clicks and menus
        // feel laggy, and (as seen) fine while the screen was being recorded, which keeps the system awake.
        // This keeps the interaction path at full priority; idle CPU stays ~0 because nothing runs.
        latencyActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Notch capsule hover and click responsiveness"
        )
        let manager = NotchManager()
        notchManager = manager
        // After an update restarted the app, the settings window it was showing comes back; the very first run shows the tour.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            SettingsWindowController.shared.reopenIfRememberedBeforeRestart()
            let debugging = ProcessInfo.processInfo.environment.keys.contains { $0.hasPrefix("PENDANT_DEBUG") }
            if !AppSettings.shared.tourSeen, !debugging { TourWindowController.shared.show() }
        }
        let status = StatusItemController()
        status.onOpenSettings = { SettingsWindowController.shared.show() }
        status.onOpenAbout = { SettingsWindowController.shared.show(tab: .about) }
        observeUpdates(status)
        UpdateChecker.shared.startScheduling()
        status.onMenuTracking = { [weak manager] tracking in manager?.setMenuTracking(tracking) }
        status.onPauseChanged = { [weak manager] paused in manager?.isPaused = paused }
        #if DEBUG
        status.onToggleDebugActivity = { [weak manager] in
            guard let notch = manager?.primary else { return }
            notch.setActivity(notch.model.activity == nil ? .init(symbolName: "music.note") : nil)
        }
        #endif
        statusItemController = status
        status.isIconVisible = AppSettings.shared.showMenuBarIcon
        observeMenuBarIconSetting()
        hotkey.onTrigger = { [weak manager] in manager?.toggleExpanded() }
        applyHotkeySettings()
        observeHotkeySettings()
        status.onOpenTuning = { [weak self] in self?.tuningWindow.show() }
        // Developer options can also be opened at launch: `Pendant --developer` (or PENDANT_DEBUG_TUNING=1 in debug builds).
        if CommandLine.arguments.contains("--developer") { tuningWindow.show() }
        #if DEBUG
        if let notch = manager.primary { installDebugHooks(notch: notch) }
        #endif
        Log.app.info("Pendant launched")
    }
}
