// swiftlint:disable file_length
import AppKit
import SwiftUI

/// Owns the notch panel and capsule model: positions the panel on the right screen, keeps it
/// in sync with screen changes, and resizes it to match the capsule state.
@MainActor
final class NotchWindowController { // swiftlint:disable:this type_body_length
    /// Which screen this controller's notch lives on.
    enum ScreenTarget: Equatable {
        /// The "show on" setting decides: main screen or the screen under the cursor.
        case followSetting
        /// Always this display (used when the notch is shown on every screen).
        case display(CGDirectDisplayID)
    }

    let model = CapsuleModel()
    let media: MediaController
    let registry: ModuleRegistry
    let center: ActivityCenter
    let target: ScreenTarget
    private var isShutDown = false
    private let panel = NotchPanel()
    private var interaction: CapsuleInteractionController!
    private var shrinkTask: Task<Void, Never>?
    private var hostingView: NSView?
    /// Observers live as long as the controller (the app's lifetime), so no removal is needed.
    private var observers: [NSObjectProtocol] = []
    private(set) var geometry: NotchGeometry?
    private var islandWatch: Task<Void, Never>?
    /// Polls (only while a virtual notch is on screen and the setting is on) whether an app is full screen on this screen.
    private var fullscreenWatch: Task<Void, Never>?
    private var appFullscreen = false
    private var timerPulsed = false
    private var alertFlashTask: Task<Void, Never>?
    private var collapsedFromExpanded = false
    private lazy var hud = NotchHUDController(model: model)
    private lazy var toast = NotchToastController(model: model)

    private var settings: AppSettings { .shared }
    var isPaused = false {
        didSet {
            interaction.isActive = !isPaused
            if isPaused { interaction.collapse() }
            reposition()
        }
    }

    // swiftlint:disable:next function_body_length
    init(media: MediaController, registry: ModuleRegistry, center: ActivityCenter, target: ScreenTarget) {
        self.media = media
        self.registry = registry
        self.center = center
        self.target = target
        interaction = CapsuleInteractionController(model: model)
        interaction.onInteractivityChange = { [weak self] on in self?.panel.ignoresMouseEvents = !on }
        model.media = media
        // The capsule's contents tuck away while the HUD or a system card is out over it.
        hud.onVisibilityChange = { [weak self] showing in self?.model.setHUDShowing(showing || self?.toast.isShowing == true) }
        hud.updatePanel = { [weak self] in
            guard let self else { return }
            applyPanel(for: model.state, shrinkImmediately: false)
        }
        toast.updatePanel = { [weak self] in
            guard let self else { return }
            applyPanel(for: model.state, shrinkImmediately: false)
        }
        toast.onVisibilityChange = { [weak self] showing in self?.model.setHUDShowing(showing || self?.hud.isShowing == true) }
        model.keepsOpen = { [weak self] in
            AnchoredPopover.isAnyOpen || (self?.registry.focusedModuleID != nil && !AppSettings.shared.focusCollapsesOnLeave)
        }
        let hosting = NSHostingView(rootView: CapsuleView(
            model: model,
            registry: registry,
            onPointer: { [weak self] inside in self?.interaction.capsulePointer(inside: inside) },
            onTap: { [weak self] in self?.interaction.handleCapsuleTap() },
            onIslandPointer: { [weak self] id, inside in self?.islandPointer(id, inside: inside) },
            onIslandTap: { [weak self] id in self?.islandTapped(id) }
        ))
        // The window frame is managed here, not by SwiftUI. Hosting the SwiftUI view as a plain
        // subview (not the window's contentView) stops NSHostingView from adjusting the window's
        // size limits mid-layout, which raised an AppKit constraint-update exception.
        hosting.sizingOptions = []
        let container = NSView()
        self.hostingView = hosting
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        panel.onEscape = { [weak self] in self?.interaction.collapse() }
        panel.onRightClick = { [weak self] in self?.showContextMenu() }
        panel.onTabStep = { [weak self] delta in self?.registry.stepTab(by: delta) }
        panel.onTabNumber = { [weak self] number in self?.registry.selectTab(number: number) }
        interaction.onContextMenu = { [weak self] in self?.showContextMenu() }
        interaction.onIslandClick = { [weak self] id in self?.islandTapped(id) }
        interaction.onMainClick = { [weak self] in self?.mainIslandTapped() }
        model.willChangeState = { [weak self] state in self?.stateWillChange(to: state) }
        model.didSettle = { [weak self] state in
            // Collapsing from the open capsule buzzes the moment it starts closing, not when the spring has settled.
            guard state != .expanded else { return }
            if self?.collapsedFromExpanded == true { self?.collapsedFromExpanded = false } else { HapticService.shared.play(.stateSettled) }
        }

        // A longer / shorter lyric line in the virtual notch's middle part widens / narrows the capsule.
        observers.append(NotificationCenter.default.addObserver(
            forName: VirtualLyricWidth.changed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition(animated: true, delayedShrink: true) }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        })
        // Fullscreen apps / Space switches change the menu bar visibility.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        })
        // 3.5.8 ⑥: the frontmost app decides how much of the menu bar is free.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.settings.islandSmartAvoid else { return }
                self.reposition()
            }
        })
        reposition()
        observeMedia()
        observeLayoutInputs()
    }

    /// Anything that changes the capsule's geometry or contents (tuning, settings, module list): rebuild.
    private func observeLayoutInputs() {
        withObservationTracking {
            _ = Tuning.shared.layoutSignature
            _ = AppSettings.shared.geometrySignature
            _ = registry.layoutSignature
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isShutDown else { return }
                self.reposition()
                self.observeLayoutInputs()
            }
        }
    }

    /// The island row follows the activity center: highest level = main island, the rest = secondary islands.
    private func observeMedia() {
        withObservationTracking {
            _ = center.ordered
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isShutDown else { return }
                self.syncActivities()
                self.observeMedia()
            }
        }
        syncActivities()
    }

    private func syncActivities() {
        let ordered = center.ordered
        let main = ordered.first.map { CapsuleModel.Activity(symbolName: $0.symbolName, kind: $0.kind ?? .media) }
        let hadActivity = model.activity != nil
        let secondariesBefore = model.secondaryActivities.map(\.id)
        if main != nil {
            // The layout (timer width, secondary islands) is ready before the capsule opens or swaps its content.
            reposition(animated: hadActivity, delayedShrink: true)
            model.setActivity(main)
        } else {
            model.setActivity(nil)
            reposition(delayedShrink: true)
        }
        if model.secondaryActivities.map(\.id) != secondariesBefore, settings.islandDisplayMode == .brief,
           !model.secondaryActivities.isEmpty {
            model.pulseSecondaries()
        }
        syncAlert(center.ordered.first?.isAlerting == true)
        updateIslandWatch()
    }

    // MARK: Secondary islands

    /// Runs only while secondary islands exist: hides them while a menu is open (②) and, in "brief" mode, shows them
    /// again when a timer gets down to its last minute.
    private func updateIslandWatch() {
        let wanted = !model.secondaryActivities.isEmpty && (settings.islandHideDuringMenus || settings.islandDisplayMode == .brief)
        if !wanted {
            islandWatch?.cancel()
            islandWatch = nil
            model.setMenuSuppressed(false)
            return
        }
        guard islandWatch == nil else { return }
        islandWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled, let self else { return }
                checkIslands()
            }
        }
    }

    private func checkIslands() {
        if settings.islandHideDuringMenus, let geometry, model.state == .compact {
            let open = MenuBarMenuDetector.isMenuOpen(on: geometry.screenFrame, menuBarHeight: geometry.size.height)
            model.setMenuSuppressed(open)
        } else {
            model.setMenuSuppressed(false)
        }
        guard settings.islandDisplayMode == .brief, model.secondaryActivities.contains(where: { $0.id == "timer" }) else {
            timerPulsed = false
            return
        }
        let engine = TimerController.shared.engine
        let low = engine.mode == .countdown && engine.remaining(at: Date()) <= 60
        if low, !timerPulsed { model.pulseSecondaries() }
        timerPulsed = low
    }

    private func islandPointer(_ id: String, inside: Bool) {
        // The tracking area reports "entered" again whenever the view re-renders under a resting pointer (the hover
        // scale itself does that), so only a real change counts: otherwise it buzzed continuously.
        if inside {
            guard model.hoveredIsland != id else { return }
        } else if interaction.islandID(at: NSEvent.mouseLocation) == id {
            return
        }
        model.setHoveredIsland(inside ? id : nil)
        interaction.islandPointer(inside: inside)
    }

    /// Click on an island: open the capsule on that activity's page.
    func islandTapped(_ id: String) {
        guard model.state != .expanded else { return }
        if id == "timer" { center.acknowledgeTimerAlert() }
        showTimerView(for: id)
        showPage(of: center.ordered.first { $0.id == id }?.moduleID ?? id)
        interaction.expand(feelsClick: true)
    }

    /// Click on the main island opens the page of its activity.
    func mainIslandTapped() {
        guard let first = center.ordered.first else { return }
        showTimerView(for: first.id)
        // The shelf capsule shows info about the newest file under it: clicking anywhere but its icon (the left wing) just
        // opens the capsule on the page that was open, it does not jump to the shelf.
        if first.kind != .shelf || pointerIsOnMainIcon() { showPage(of: first.moduleID) }
        if first.isAlerting { center.acknowledgeTimerAlert() }
    }

    /// The pointer is over the compact capsule's left wing (its icon).
    private func pointerIsOnMainIcon() -> Bool {
        guard let layout = model.layout else { return true }
        let body = layout.bodyRect(for: .compact)
        let wing = max((body.width - layout.notch.size.width) / 2, layout.notch.size.height)
        let point = NSEvent.mouseLocation
        return point.x >= body.minX - NotchGeometry.earRadius && point.x <= body.minX + wing
    }

    /// Opening from a timer island shows that timer (countdown / stopwatch) on the page.
    private func showTimerView(for activityID: String) {
        if let mode = ActivityKind(rawValue: activityID)?.timerMode { TimerController.shared.viewMode = mode }
    }

    private func showPage(of moduleID: String) {
        if let tab = registry.tabID(containing: moduleID) { registry.setTab(tab) }
    }

    /// The menu-bar menu is open: stop observing the mouse so the menu is not slowed down.
    func setMenuTracking(_ tracking: Bool) {
        interaction.setMonitorsSuspended(tracking)
    }

    /// Right-click on the notch / capsule: open settings or quit.
    private func showContextMenu() {
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: String(localized: "menu.settings", defaultValue: "設定⋯"),
                                      action: #selector(ContextMenuActions.openSettings), keyEquivalent: "")
        let quitItem = NSMenuItem(title: String(localized: "menu.quit", defaultValue: "結束 Pendant"),
                                  action: #selector(ContextMenuActions.quit), keyEquivalent: "")
        for item in [settingsItem, quitItem] { item.target = ContextMenuActions.shared }
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        // The menu blocks until dismissed; keep the event monitors out of its way meanwhile.
        interaction.setMonitorsSuspended(true)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        interaction.setMonitorsSuspended(false)
    }

    /// A countdown ended. The compact capsule shows it (the timer takes over the main island, see `ActivityCenter`);
    /// an open capsule just pulses its outline.
    func timerFinished() {
        if model.state == .expanded { model.flash() }
    }

    /// While the timer-end notice is up the main island's outline keeps pulsing.
    private func syncAlert(_ alerting: Bool) {
        model.setAlerting(alerting)
        guard alerting else {
            alertFlashTask?.cancel()
            alertFlashTask = nil
            return
        }
        guard alertFlashTask == nil else { return }
        alertFlashTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.model.flash()
                try? await Task.sleep(for: .milliseconds(1600))
            }
        }
    }

    // MARK: Drag to the notch (shelf)

    private var dragWatchTask: Task<Void, Never>?

    /// Pointer within `distance` of the notch (the drag-to-shelf trigger zone).
    func isNearNotch(_ point: CGPoint, distance: CGFloat) -> Bool {
        guard let geometry, !isPaused else { return false }
        let zone = geometry.notchRect.insetBy(dx: -distance, dy: -distance)
        return CGRect(x: zone.minX, y: zone.minY, width: zone.width, height: zone.height + distance).containsPointer(point)
    }

    /// Opens the capsule on the shelf for a file drag; closes again if the drag ends without a drop.
    func openShelfForDrag() {
        guard model.state != .expanded, dragWatchTask == nil else { return }
        showPage(of: "shelf")
        interaction.expand(feelsClick: false)
        dragWatchTask = Task { [weak self] in
            // Wait for the mouse button to go up (drop or cancel)…
            while !Task.isCancelled, NSEvent.pressedMouseButtons & 1 != 0 { try? await Task.sleep(for: .milliseconds(80)) }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled, let self else { return }
            dragWatchTask = nil
            // …and close it unless something was dropped or the pointer is resting on the capsule.
            let dropped = Date().timeIntervalSince(ShelfStore.shared.lastDropAt) < 3
            let onCapsule = model.layout?.triggerRect(for: .expanded).containsPointer(NSEvent.mouseLocation) == true
            if !dropped, !onCapsule { interaction.collapse() }
        }
    }

    /// Volume / brightness changed: the notch grows its HUD wings (not while the capsule is open: the page is in use).
    func showHUD(_ level: SystemLevel) {
        guard !isPaused, model.state != .expanded, let notch = model.layout?.notch else { return }
        toast.hideNow()
        hud.show(level, notch: notch.notchRect)
    }

    /// A system event (charging, low battery, a Bluetooth device): a card grows out of the notch. `seconds` = nil: until it is hidden.
    func showToast(_ card: SystemToast, seconds: Double?) {
        guard !isPaused, model.state != .expanded, let notch = model.layout?.notch else { return }
        hud.hideNow()
        toast.show(card, seconds: seconds)
    }

    func hideToast() { toast.fold() }

    /// Global shortcut. When it opens the capsule, the panel takes keyboard focus (it never activates the app), so the
    /// arrow keys, ⌘1…⌘9 and Esc work right away without touching the mouse.
    func toggleExpanded() {
        interaction.toggleExpanded()
        guard model.state == .expanded else { return }
        panel.allowsKey = true
        // Keys go to the active app; without this ⌘1…⌘9 would still reach the window behind.
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Debug / future-module hook: show or clear a compact live activity.
    func setActivity(_ activity: CapsuleModel.Activity?) {
        model.setActivity(activity)
    }

    #if DEBUG
    func debugExpand() { interaction.expand() }
    /// One line describing whether the panel currently swallows the mouse (for hunting stuck-interactive bugs).
    func debugPanelState() -> String {
        let frame = panel.frame.integral
        return "state=\(model.state) ignoresMouse=\(panel.ignoresMouseEvents) frame=\(frame) swelled=\(model.isSwelled)"
    }
    func debugCollapse() { interaction.collapse() }
    /// A swipe that stops short of the change: the icon fades where it is.
    func debugStepCancel() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            model.stepBegan(leftwards: true, forward: true)
            for step in 0...10 {
                model.stepMoved(to: Double(step) / 30)
                try? await Task.sleep(for: .milliseconds(30))
            }
            model.stepEnded(at: 0.33)
        }
    }

    /// Swipes back and forth inside the first stage (the icon swings between the two sides).
    func debugStepFlip() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            for round in 0..<4 {
                let leftwards = round % 2 == 0
                model.stepBegan(leftwards: leftwards, forward: !leftwards)
                for step in 0...8 {
                    model.stepMoved(to: Double(step) / 30)
                    try? await Task.sleep(for: .milliseconds(40))
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            model.stepEnded(at: 0.1)
        }
    }

    /// Plays two swipe cycles (a swipe that keeps going) like a finger would.
    func debugStep(forward: Bool, leftwards: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            model.stepBegan(leftwards: leftwards, forward: forward)
            for cycle in 0..<2 {
                for step in 0...30 {
                    model.stepMoved(to: min(Double(step) / 30, 0.999))
                    try? await Task.sleep(for: .milliseconds(30))
                }
                if cycle == 0 { model.stepMoved(to: 0) }
            }
            model.stepEnded(at: 0.999)
        }
    }
    func debugTrackInfo() { model.noteTrackChange() }
    func debugCompactHover(artwork: Bool = true, controls: Bool = false) {
        model.setSwelled(true)
        if artwork { model.setCompactHover(.artwork) }
        if controls {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(700))
                self?.model.setCompactHover(.controls)
            }
        }
    }
    /// Swell and un-swell every 0.45 s (to catch tick / animation overlaps in recordings).
    func debugPulseSwell() {
        Task { @MainActor [weak self] in
            for index in 0..<14 {
                try? await Task.sleep(for: .milliseconds(450))
                self?.model.setSwelled(index % 2 == 0)
            }
        }
    }
    func debugMedia(playing: Bool) { media.debugInject(playing: playing) }
    #endif

    /// Closes the panel and stops listening; the controller is not used afterwards.
    func shutdown() {
        isShutDown = true
        interaction.shutdown()
        shrinkTask?.cancel()
        islandWatch?.cancel()
        fullscreenWatch?.cancel()
        alertFlashTask?.cancel()
        hud.hideNow()
        toast.hideNow()
        panel.orderOut(nil)
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    /// Screen under the pointer (hotkey target).
    var isPointerOnMyScreen: Bool {
        guard let frame = geometry?.screenFrame else { return false }
        return frame.containsPointer(NSEvent.mouseLocation)
    }

    /// Whether `point` is on the screen this controller's notch sits on.
    func isOnMyScreen(_ point: CGPoint) -> Bool {
        geometry?.screenFrame.containsPointer(point) ?? false
    }

    private func targetScreen() -> NSScreen? {
        if case let .display(id) = target {
            return NSScreen.screens.first { $0.displayID == id }
        }
        switch settings.screenChoice {
        case .all, .main:
            return NSScreen.screens.first ?? NSScreen.main
        case .underCursor:
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.screens.first
        }
    }

    /// The screen's notch height (0 = no notch). PENDANT_DEBUG_VIRTUAL=1 makes every screen count as one without (debug builds).
    private func effectiveSafeAreaTop(of screen: NSScreen) -> CGFloat {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_VIRTUAL"] != nil { return 0 }
        #endif
        return screen.safeAreaInsets.top
    }

    /// The notch of a screen; a virtual one that carries content (clock, battery) is narrower than the empty placeholder.
    private func makeGeometry(for screen: NSScreen, menuBarHeight: CGFloat) -> NotchGeometry {
        func geometry(adjustment: CGFloat, safeAreaTop: CGFloat) -> NotchGeometry {
            NotchGeometry(
                screenFrame: screen.frame, safeAreaTop: safeAreaTop, auxLeft: screen.auxiliaryTopLeftArea,
                auxRight: screen.auxiliaryTopRightArea, menuBarHeight: menuBarHeight, widthAdjustment: adjustment
            )
        }
        let plain = geometry(adjustment: settings.notchWidthAdjust, safeAreaTop: effectiveSafeAreaTop(of: screen))
        guard plain.isVirtual, settings.virtualNotchEnabled else { return plain }
        let narrower = NotchGeometry.virtualContentWidth - NotchGeometry.virtualSize.width
        var virtual = geometry(adjustment: settings.notchWidthAdjust + narrower, safeAreaTop: 0)
        if settings.virtualFloating { virtual.floatGap = CGFloat(settings.virtualFloatGap) }
        return virtual
    }

    func reposition(animated: Bool = false, delayedShrink: Bool = false) {
        guard !isPaused, let screen = targetScreen() else {
            panel.orderOut(nil)
            geometry = nil
            model.updateLayout(nil)
            return
        }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let geometry = makeGeometry(for: screen, menuBarHeight: menuBarHeight)
        let virtualContent = geometry.isVirtual && settings.virtualNotchEnabled
        self.geometry = geometry
        var layout = CapsuleLayout(notch: geometry)
        layout.virtualContent = virtualContent
        if virtualContent, settings.virtualMiddle == .lyrics {
            layout.virtualMiddleExtra = VirtualLyricWidth.shared.extra
            layout.virtualLyricReserve = VirtualLyricWidth.maxExtra
        }
        let activities = center.ordered
        layout.reservesModeSwitcher = registry.availableTabs.count > 1
        layout.compactActivityExtra = 0
        if let mode = activities.first?.kind?.timerMode {
            layout.compactActivityExtra = TimerCompactMetrics.extraWing(standardWing: layout.compactWing, mode: mode)
        }
        var islands = settings.islandSettings
        if settings.islandSmartAvoid { islands.leftBound = MenuBarAvoidance.appMenusRightEdge() }
        let placements = IslandPlanner.plan(
            mainRect: layout.bodyRect(for: .compact), ear: layout.isFloating ? 0 : NotchGeometry.earRadius,
            screenFrame: geometry.screenFrame.offsetBy(dx: 0, dy: -geometry.floatGap),
            menuBarHeight: max(menuBarHeight, geometry.size.height), activities: activities, settings: islands
        )
        layout.secondaries = placements.filter { $0.side != nil }
        let secondaryIDs = layout.secondaries.map(\.id)
        model.setSecondaries(secondaryIDs.compactMap { id in activities.first { $0.id == id } })
        layout.expandedCells = registry.currentPageIDs.map(registry.displayCells(for:))
        if model.state == .expanded, let old = model.layout,
           old.bodySize(for: .expanded).width != layout.bodySize(for: .expanded).width {
            interaction.disarmCollapse()
        }
        // A layout that is about to grow gets its window first: updating the model first drew the growing capsule in the old, narrower
        // window for a frame (it jumped sideways when the window followed).
        if animated, model.state != .expanded { setPanelFrame(panel.frame.union(layout.panelFrame(for: model.state))) }
        model.updateLayout(layout, animated: animated)

        // A real notch is always on screen; a virtual one hides while an app is full screen on this screen (settings › 虛擬瀏海).
        updateFullscreenWatch(on: screen)
        if geometry.isVirtual, settings.virtualHideInFullscreen, appFullscreen, model.state != .expanded {
            panel.orderOut(nil)
            return
        }
        applyPanel(for: model.state, shrinkImmediately: model.state != .expanded && !delayedShrink)
        panel.orderFrontRegardless()
        updateIslandWatch()
    }

    // MARK: Full screen

    private func updateFullscreenWatch(on screen: NSScreen) {
        let wanted = geometry?.isVirtual == true && settings.virtualHideInFullscreen
        guard wanted else {
            fullscreenWatch?.cancel()
            fullscreenWatch = nil
            appFullscreen = false
            return
        }
        guard fullscreenWatch == nil else { return }
        appFullscreen = FullscreenDetector.isFullscreen(on: screen)
        fullscreenWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self, let screen = targetScreen() else { return }
                let fullscreen = FullscreenDetector.isFullscreen(on: screen)
                if fullscreen != appFullscreen {
                    appFullscreen = fullscreen
                    reposition()
                }
            }
        }
    }

    // MARK: Panel sizing

    /// Resizes the panel and lays the SwiftUI content out for the new size immediately. Without the
    /// synchronous layout, one frame is drawn with the capsule at its old offset (a visible glitch).
    private func setPanelFrame(_ frame: CGRect) {
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: false)
        panel.contentView?.layoutSubtreeIfNeeded()
        hostingView?.layoutSubtreeIfNeeded()
    }

    private func stateWillChange(to state: CapsuleState) {
        // Feedback for opening is immediate (stage 2 of the hover flow); closing is felt when it settles.
        interaction.refreshInteractivity(for: state)
        if state != .expanded { registry.unfocus() } // a closed capsule shows the whole tab again
        if state == .expanded {
            if !model.suppressExpandHaptic { HapticService.shared.play(.expandStarted) }
            model.suppressExpandHaptic = false
            media.refresh()
        } else if model.state == .expanded {
            HapticService.shared.play(.stateSettled)
            collapsedFromExpanded = true
        }
        // Grow before the animation starts; shrink only after it has settled, so the
        // SwiftUI morph never gets clipped by the window.
        applyPanel(for: state, shrinkImmediately: false)
    }

    private func applyPanel(for state: CapsuleState, shrinkImmediately: Bool) {
        guard let layout = model.layout else { return }
        shrinkTask?.cancel()
        panel.allowsKey = state == .expanded
        if state != .expanded, panel.isKeyWindow { panel.resignKey() }

        var target = layout.panelFrame(for: state)
        if state != .expanded {
            // Room for the shape the capsule widens into: the volume / brightness HUD, a system-event card.
            if model.levelHUDWanted { target = target.union(layout.hudPanelFrame()) }
            if model.toastWanted { target = target.union(layout.toastPanelFrame()) }
        }
        if shrinkImmediately {
            setPanelFrame(target)
            return
        }
        // Laying out right away also keeps the upcoming animation from animating the capsule's origin
        // (which made it grow sideways).
        let union = panel.frame.union(target)
        setPanelFrame(union)
        guard union != target else { return }
        // Target is smaller than the current frame: wait for the collapse animation to finish.
        shrinkTask = Task { [weak self, weak panel] in
            try? await Task.sleep(for: .seconds(0.7))
            guard !Task.isCancelled, panel != nil, let self else { return }
            setPanelFrame(target)
        }
    }
}

/// Targets for the notch context menu items.
@MainActor
final class ContextMenuActions: NSObject {
    static let shared = ContextMenuActions()

    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }
}
