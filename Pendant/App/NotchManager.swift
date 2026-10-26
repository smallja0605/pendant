import AppKit

/// Owns the shared services (media, module registry, timer hook) and one `NotchWindowController` per screen
/// that should show a notch: a single one following the "show on" setting, or one per display.
@MainActor
final class NotchManager {
    let media: MediaController
    let registry: ModuleRegistry
    let center: ActivityCenter
    private(set) var controllers: [NotchWindowController] = []
    private var observers: [NSObjectProtocol] = []
    private let dragWatcher = ShelfDragWatcher()
    private let levelMonitor = SystemLevelMonitor()
    private let keyInterceptor = MediaKeyInterceptor()
    private let systemEvents = SystemEventMonitor()
    private let bluetooth = BluetoothMonitor()
    private var keyWatch: Task<Void, Never>?

    var isPaused = false {
        didSet { controllers.forEach { $0.isPaused = isPaused } }
    }

    /// First controller: used by debug hooks and single-screen conveniences.
    var primary: NotchWindowController? { controllers.first }

    init() {
        media = MediaController(sources: MediaSourceID.allCases.map { ScriptablePlayerSource(id: $0) })
        registry = .shared
        center = ActivityCenter(media: media)
        let placeholders = ModuleDescriptor.all.filter { !$0.implemented }.map { PlaceholderModule(descriptor: $0) }
        let modules: [any PendantModule] = [
            MediaModule(controller: media), NotesModule(), CalendarModule(), TimerModule(), RemindersModule(),
            ShortcutsModule(), MirrorModule(), ShelfModule(),
        ]
        registry.register(modules + placeholders)
        TimerController.shared.onFinished = { [weak self] in
            self?.center.timerDidFinish()
            self?.controllers.forEach { $0.timerFinished() }
        }
        rebuild()
        syncMediaRunning()
        levelMonitor.onChange = { [weak self] level in self?.showHUD(level) }
        keyInterceptor.onKey = { [weak self] key, fine in self?.mediaKey(key, fine: fine) ?? false }
        syncLevelMonitor()
        BatteryMonitor.shared.start()
        systemEvents.onToast = { [weak self] toast, seconds in self?.controllers.forEach { $0.showToast(toast, seconds: seconds) } }
        systemEvents.onDismiss = { [weak self] in self?.controllers.forEach { $0.hideToast() } }
        systemEvents.start()
        bluetooth.onConnect = { [weak self] device in self?.bluetoothConnected(device) }
        syncBluetooth()
        observeSettings()
        dragWatcher.onFileDrag = { [weak self] point, origin in self?.fileDragMoved(to: point, from: origin) }
        dragWatcher.start()
        ShelfStore.shared.cleanDragCopies()
        ShelfStore.shared.applyAutoClearAtLaunch()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        })
    }

    // MARK: Controllers

    /// Creates / removes controllers so that they match the setting and the connected displays.
    func rebuild() {
        let wanted: [NotchWindowController.ScreenTarget] = AppSettings.shared.screenChoice == .all
            ? NSScreen.screens.map { .display($0.displayID) }
            : [.followSetting]
        var kept: [NotchWindowController] = []
        for target in wanted {
            if let existing = controllers.first(where: { $0.target == target }) {
                kept.append(existing)
            } else {
                let controller = NotchWindowController(media: media, registry: registry, center: center, target: target)
                controller.isPaused = isPaused
                kept.append(controller)
            }
        }
        for controller in controllers where !kept.contains(where: { $0 === controller }) { controller.shutdown() }
        controllers = kept
    }

    /// Global shortcut: toggles the notch on the screen the pointer is on (or the first one).
    func toggleExpanded() {
        (controllers.first { $0.isPointerOnMyScreen } ?? primary)?.toggleExpanded()
    }

    /// A file is being dragged: near the notch, the capsule opens on the shelf (if the shelf is on and the option is set).
    private func fileDragMoved(to point: CGPoint, from origin: CGPoint) {
        let settings = AppSettings.shared
        guard settings.dragOpensShelf, registry.isEnabled("shelf"), !isPaused else { return }
        guard let controller = controllers.first(where: { $0.isNearNotch(point, distance: settings.dragProximity) }) else { return }
        // A drag that began on another screen is on its way across, not to the shelf (settings › 檔案中轉站).
        if settings.dragIgnoresOtherScreens, !controller.isOnMyScreen(origin) { return }
        controller.openShelfForDrag()
    }

    func setMenuTracking(_ tracking: Bool) {
        controllers.forEach { $0.setMenuTracking(tracking) }
    }

    // MARK: Shared behaviour

    /// Player monitoring runs while the media page or the media live activity is wanted.
    /// Volume / brightness HUD: listen only to what is switched on (brightness is polled, so it costs nothing when off).
    private func syncLevelMonitor() {
        let settings = AppSettings.shared
        levelMonitor.start(volume: settings.hudVolume, brightness: settings.hudBrightness)
        syncKeyInterceptor()
    }

    /// With "hide the system pop-up" on and the Accessibility permission granted, the keys are taken (see `MediaKeyInterceptor`);
    /// otherwise the pop-up helper is only stopped after the fact (`SystemHUDBlocker`). Without the permission this re-checks
    /// every two seconds, so granting it takes effect without a restart.
    private func syncKeyInterceptor() {
        let settings = AppSettings.shared
        let wanted = settings.hudHideSystem && (settings.hudVolume || settings.hudBrightness)
        keyInterceptor.interceptsVolume = settings.hudVolume
        keyInterceptor.interceptsBrightness = settings.hudBrightness
        keyWatch?.cancel()
        keyWatch = nil
        guard wanted else { keyInterceptor.stop(); return }
        if keyInterceptor.start() { return }
        keyWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                if keyInterceptor.start() { keyWatch = nil; return }
            }
        }
    }

    /// A media key was taken: the level changes here instead of in the system, and the HUD shows it.
    private func mediaKey(_ key: MediaKeyInterceptor.Key, fine: Bool) -> Bool {
        let step = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case .volumeUp, .volumeDown:
            // A device without a settable volume (some HDMI / Bluetooth outputs): the key goes on to the system.
            guard let current = levelMonitor.currentVolume() else { return false }
            let muted = levelMonitor.currentlyMuted()
            let target = min(max(current + (key == .volumeUp ? step : -step), 0), 1)
            if muted, key == .volumeUp { levelMonitor.setMuted(false) }
            levelMonitor.setVolume(target)
            showHUD(.volume(level: target, muted: key == .volumeUp ? false : muted))
        case .mute:
            guard let current = levelMonitor.currentVolume() else { return false }
            let muted = !levelMonitor.currentlyMuted()
            levelMonitor.setMuted(muted)
            showHUD(.volume(level: current, muted: muted))
        case .brightnessUp, .brightnessDown:
            guard let current = levelMonitor.currentBrightness() else { return false }
            let target = min(max(current + (key == .brightnessUp ? step : -step), 0), 1)
            levelMonitor.setBrightness(target)
            showHUD(.brightness(level: target))
        }
        return true
    }

    private func showHUD(_ level: SystemLevel) {
        let settings = AppSettings.shared
        switch level {
        case .volume: guard settings.hudVolume else { return }
        case .brightness: guard settings.hudBrightness else { return }
        }
        // The keys are taken when the permission allows; otherwise the system pop-up is stopped after the fact.
        if settings.hudHideSystem, !keyInterceptor.isRunning { SystemHUDBlocker.suppress() }
        controllers.forEach { $0.showHUD(level) }
    }

    /// The Bluetooth listener runs only while its card is switched on (listening is what asks for the permission).
    private func syncBluetooth() {
        if AppSettings.shared.bluetoothToast { bluetooth.start() } else { bluetooth.stop() }
    }

    private func bluetoothConnected(_ device: BluetoothConnection) {
        let settings = AppSettings.shared
        guard settings.bluetoothToast else { return }
        let subtitle = device.battery.map { tr("已連接 · \($0)%") } ?? tr("已連接")
        let toast = SystemToast(title: device.name, subtitle: subtitle, progress: Double(device.battery ?? 100) / 100, tint: .blue,
                                ringSymbol: "bluetooth", trailing: .symbol(device.symbol))
        controllers.forEach { $0.showToast(toast, seconds: settings.bluetoothToastSeconds) }
    }

    func hideToasts() { controllers.forEach { $0.hideToast() } }

    /// Shows a made-up system card (the simulation panel, PENDANT_DEBUG_TOAST).
    func simulateToast(_ toast: SystemToast, seconds: Double?) { controllers.forEach { $0.showToast(toast, seconds: seconds) } }

    /// PENDANT_DEBUG_HUD hook: shows the HUD with a made-up level.
    func debugHUD(_ level: SystemLevel) { controllers.forEach { $0.showHUD(level) } }

    private func syncMediaRunning() {
        let wanted = registry.isEnabled("media") || !AppSettings.shared.disabledActivities.contains("media")
        if wanted { media.start() } else { media.stop() }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = AppSettings.shared.screenChoice
            _ = AppSettings.shared.disabledActivities
            _ = AppSettings.shared.mediaSourcePreference
            _ = AppSettings.shared.hudVolume
            _ = AppSettings.shared.bluetoothToast
            _ = AppSettings.shared.hudBrightness
            _ = AppSettings.shared.hudHideSystem
            _ = registry.activeIDs
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.rebuild()
                self.syncMediaRunning()
                self.syncBluetooth()
                self.syncLevelMonitor()
                self.media.settingsChanged()
                self.observeSettings()
            }
        }
    }
}
