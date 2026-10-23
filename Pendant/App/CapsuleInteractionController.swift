// swiftlint:disable file_length
import AppKit

/// Turns raw mouse / key / app-focus events into capsule state changes:
/// notch hover swell, hover-to-expand with delay, click to expand, and the collapse rules.
@MainActor
final class CapsuleInteractionController { // swiftlint:disable:this type_body_length
    private let model: CapsuleModel
    private var monitorsInstalled = false
    private var observers: [NSObjectProtocol] = []

    private var isHovering = false
    private var expandTask: Task<Void, Never>?
    private var unswellTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    var isActive = true {
        didSet { if !isActive { cancelAll(); isHovering = false; model.setSwelled(false) } }
    }

    init(model: CapsuleModel) {
        self.model = model
        #if DEBUG
        // A/B switch for diagnosing menu-bar hover glitches: PENDANT_DEBUG_NO_MONITORS=1 disables all event monitors.
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_NO_MONITORS"] == nil { installMonitors() }
        #else
        installMonitors()
        #endif
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Switching to another app collapses the capsule (3.2).
            MainActor.assumeIsolated {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
                    Log.trace("app activated -> collapse (frontmost is another app)")
                    self?.collapse()
                }
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshReduceMotion() }
        })
    }

    // MARK: Event sources

    private var moveMonitor: Any?
    /// True while the panel accepts mouse events (pointer over the compact / expanded body).
    private var interactive = false
    /// The pointer has been over the open capsule at least once; only then does leaving close it. A capsule opened
    /// with the hotkey while the pointer is elsewhere would otherwise close again right away.
    private var expandedArmed = false
    /// After 功能 ↔ 檔案中轉站 the capsule changes width under the pointer: nothing (leaving, clicking outside) may close
    /// it until the pointer has been over it again.
    private var holdUntilHover = false
    /// While the capsule is still resizing, tracking-area enter / exit events (the edge sweeping past a resting pointer)
    /// are noise: they neither arm nor schedule a collapse.
    private var resizeGraceUntil = Date.distantPast
    private var inResizeGrace: Bool { Date() < resizeGraceUntil }
    fileprivate var watchTask: Task<Void, Never>?
    /// Extra horizontal room before the swollen compact capsule counts as left (stops edge flicker).
    private static let sideLeaveSlack: CGFloat = 4
    /// After leaving, entering again is ignored for a moment so a resize under a resting pointer cannot oscillate.
    private var lastLeave = Date.distantPast
    var onInteractivityChange: ((Bool) -> Void)?
    private var downMonitor: Any?

    /// While the status-item menu is open all monitors are removed so the menu gets the event stream to itself.
    func setMonitorsSuspended(_ suspended: Bool) {
        guard !ProcessInfo.processInfo.environment.keys.contains("PENDANT_DEBUG_NO_MONITORS") else { return }
        if suspended {
            removeMonitors()
        } else if !monitorsInstalled {
            installMonitors()
        }
    }

    private func removeMonitors() {
        if let moveMonitor { NSEvent.removeMonitor(moveMonitor) }
        if let downMonitor { NSEvent.removeMonitor(downMonitor) }
        moveMonitor = nil
        downMonitor = nil
        monitorsInstalled = false
        cancelAll()
        isHovering = false
        model.setSwelled(false)
    }

    private func installMonitors() {
        let downMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: downMask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.mouseDown(type: type) }
        })
        monitorsInstalled = true
        syncMoveMonitor(for: model.state)
    }

    /// The global move monitor is only needed in idle (the click-through panel never sees the pointer).
    /// In compact / expanded the capsule's own tracking area reports enter / exit, and leaving the
    /// monitor installed there slowed the hover animations (same effect as with the menu).
    func syncMoveMonitor(for state: CapsuleState) {
        guard monitorsInstalled else { return }
        // Needed whenever the pointer is outside the (interactive) capsule body: that is when the panel
        // is click-through and cannot see the pointer itself.
        if !interactive {
            guard moveMonitor == nil else { return }
            moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
                MainActor.assumeIsolated { self?.mouseMoved() }
            })
        } else if let moveMonitor {
            NSEvent.removeMonitor(moveMonitor)
            self.moveMonitor = nil
        }
    }

    /// Called when the state changes (before it animates): decides if the panel should take clicks right now.
    func refreshInteractivity(for state: CapsuleState) {
        guard let layout = model.layout else { return }
        let inside = state != .idle && isInHit(layout, NSEvent.mouseLocation, state: state)
        setInteractive(inside, for: state)
    }

    private func setInteractive(_ on: Bool, for state: CapsuleState? = nil) {
        let state = state ?? model.state
        // While the panel takes clicks in the compact state something must always be watching the pointer.
        if on, state == .compact { startPointerWatch() }
        if on != interactive {
            Log.trace("interactive -> \(on) state=\(state)")
            interactive = on
            onInteractivityChange?(on)
        }
        syncMoveMonitor(for: state)
    }

    /// Pointer enter / exit of the capsule body, reported by an AppKit tracking area (no event monitor:
    /// a local mouse-move monitor made hover animations and menus stutter). Global monitors only see
    /// events outside our own windows, so this covers the inside.
    func capsulePointer(inside: Bool) {
        guard isActive else { return }
        switch model.state {
        case .idle:
            // While the notch is swollen the panel takes the pointer's clicks (see `enterZone`), so this is where leaving shows.
            if !inside, isHovering, let layout = model.layout, !layout.triggerRect(for: .idle).containsPointer(NSEvent.mouseLocation) {
                leaveZone()
                setInteractive(false)
            }
        case .compact:
            if inside, !isHovering {
                enterZone()
            } else if !inside, isHovering, let layout = model.layout, !hoverRect(layout).containsPointer(NSEvent.mouseLocation) {
                leaveZone() // a tracking exit while the pointer is still on the swollen capsule is just a resize
            }
            if !inside, let layout = model.layout, !hoverRect(layout).containsPointer(NSEvent.mouseLocation),
               !isOverIsland(NSEvent.mouseLocation) { setInteractive(false) }
        case .expanded:
            if inside {
                if !inResizeGrace {
                    expandedArmed = true
                    holdUntilHover = false
                }
                cancelCollapse()
            } else {
                scheduleCollapse()
                setInteractive(false)
            }
        }
    }

    // MARK: Handlers

    private func mouseMoved() {
        guard isActive, let layout = model.layout else { return }
        let point = NSEvent.mouseLocation

        if model.state != .idle, !interactive, isInHit(layout, point, state: model.state) {
            // Pointer came back over the capsule while the panel was click-through: take clicks again.
            setInteractive(true)
        }

        if model.state == .expanded {
            let inside = layout.triggerRect(for: .expanded).containsPointer(point)
            if inside { cancelCollapse() } else { scheduleCollapse() }
            return
        }

        // Hysteresis: entering needs the resting zone, leaving needs the pointer to be outside the capsule as it
        // looks while hovered (it is taller / wider then). Without it a pointer resting in the thin band that only
        // exists while swollen made the capsule flip between compact and swollen.
        let zone = (isHovering && model.state == .compact) ? hoverRect(layout) : layout.triggerRect(for: model.state)
        let inZone = zone.containsPointer(point)
        if inZone, !isHovering { enterZone() } else if !inZone, isHovering { leaveZone() }
    }

    /// Opens the notch's context menu (settings / quit). Wired by the window controller.
    var onContextMenu: (() -> Void)?

    private func mouseDown(type: NSEvent.EventType = .leftMouseDown) {
        guard isActive, let layout = model.layout else { return }
        let point = NSEvent.mouseLocation
        if type == .rightMouseDown, isOnCapsule(layout, point) {
            onContextMenu?()
            return
        }
        if type == .otherMouseDown { return }
        switch model.state {
        case .idle:
            // Clicks on the notch itself reach us only through the global monitor.
            if layout.triggerRect(for: .idle).containsPointer(point) { expand(feelsClick: true) }
        case .compact:
            // Normally the panel receives these clicks itself (see `handleCapsuleTap`). A click that arrives here
            // came while the panel was still click-through (pointer just entered): it must not be lost.
            if let id = islandID(at: point) {
                onIslandClick?(id)
            } else if visibleBodyRect(layout).containsPointer(point) {
                expandFromMain()
            }
        case .expanded:
            if !holdUntilHover, !layout.triggerRect(for: .expanded).containsPointer(point) { collapse() }
        }
    }

    func handleCapsuleTap() {
        guard model.state != .expanded, let layout = model.layout else { return }
        // Only the visible capsule body opens it, not the transparent room around it in the panel.
        if visibleBodyRect(layout).containsPointer(NSEvent.mouseLocation) { expandFromMain() }
    }

    /// Clicking the compact capsule opens it on its activity's page (3.5.5).
    private func expandFromMain() {
        onMainClick?()
        expand(feelsClick: true)
    }

    // MARK: Secondary islands

    var onIslandClick: ((String) -> Void)?
    var onMainClick: (() -> Void)?

    /// Pointer entered / left a secondary island (reported by that island's tracking area).
    func islandPointer(inside: Bool) {
        guard isActive, model.state == .compact else { return }
        if inside {
            setInteractive(true)
            startPointerWatch() // so a missed tracking-area exit cannot leave the island swollen
        } else if let layout = model.layout, !hoverRect(layout).containsPointer(NSEvent.mouseLocation),
                  !isOverIsland(NSEvent.mouseLocation) {
            setInteractive(false)
        }
    }

    private static let islandSlack: CGFloat = 3

    func islandID(at point: CGPoint) -> String? {
        guard let layout = model.layout, model.secondariesShown else { return nil }
        return layout.secondaries.first { $0.rect.insetBy(dx: -Self.islandSlack, dy: -Self.islandSlack).containsPointer(point) }?.id
    }

    private func isOverIsland(_ point: CGPoint) -> Bool { islandID(at: point) != nil }

    /// Where the panel must take mouse events: the capsule body (as before) and the visible secondary islands.
    private func isInHit(_ layout: CapsuleLayout, _ point: CGPoint, state: CapsuleState) -> Bool {
        guard state == .compact else { return layout.hitRect(for: state).containsPointer(point) }
        // Resting compact capsule: just its body. The taller zone (swell + song line) only exists while hovered, so the
        // transparent room around the body stays click-through.
        let zone = isHovering ? hoverRect(layout) : layout.triggerRect(for: .compact)
        return zone.containsPointer(point) || isOverIsland(point)
    }

    // MARK: Hover

    private func enterZone() {
        Log.trace("enterZone state=\(model.state) cooldownBlocked=\(Date().timeIntervalSince(lastLeave) < 0.18)")
        if model.state == .compact, Date().timeIntervalSince(lastLeave) < 0.18 { return }
        isHovering = true
        if model.state == .compact {
            startPointerWatch()
            setInteractive(true) // take clicks right away, not only after the next mouse move
        } else if model.state == .idle {
            // A right click on the swollen notch must reach our own menu: while the panel was click-through it also
            // reached the menu bar, which opened its own 「選單列設定」 next to ours.
            setInteractive(true)
            startPointerWatch() // and the watch makes sure the panel is let go again when the pointer leaves
        }
        unswellTask?.cancel()
        // Already compact/expanded: no swell and no entry feedback (3.4 rule 4).
        if model.state == .idle, model.hoverEffectEnabled {
            model.setSwelled(true)
        } else if model.state == .compact, model.hoverEffectEnabled {
            // Reference recording (音樂小膠囊.mp4): the compact capsule swells on hover too.
            model.setSwelled(true)
        }

        expandTask?.cancel()
        guard ExpandPolicy.shouldAutoExpand(mode: model.hoverExpandMode, state: model.state) else { return }
        let delay = model.hoverDelay
        expandTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.expand()
        }
    }

    private func leaveZone() {
        Log.trace("leaveZone state=\(model.state) pt=\(NSEvent.mouseLocation)")
        lastLeave = Date()
        isHovering = false
        expandTask?.cancel()
        unswellTask?.cancel()
        if model.state == .compact {
            // Swell and peek end together (no delay: one smooth shrink).
            model.endCompactHover()
            return
        }
        let delay = model.swellLeaveDelay
        unswellTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.model.setSwelled(false)
        }
    }

    // MARK: Transitions

    /// `feelsClick`: opened by a physical click, which already gave the trackpad's own haptic; ours is skipped then so
    /// it does not buzz twice.
    func expand(feelsClick: Bool = false) {
        holdUntilHover = false
        model.suppressExpandHaptic = feelsClick
        Log.trace("expand state=\(model.state)")
        cancelAll()
        isHovering = false
        if let layout = model.layout {
            expandedArmed = layout.hitRect(for: model.state).containsPointer(NSEvent.mouseLocation)
        }
        model.transition(to: .expanded)
        startPointerWatch()
    }

    /// The open capsule changed width under the pointer (e.g. 功能 → 檔案中轉站): it must not count as "left" until the
    /// pointer has been over the new shape again.
    func disarmCollapse() {
        resizeGraceUntil = Date().addingTimeInterval(1.2)
        expandedArmed = false
        holdUntilHover = true
        cancelCollapse()
    }

    /// Global shortcut: open when closed, close when open.
    func toggleExpanded() {
        if model.state == .expanded { collapse() } else { expand() }
    }

    func collapse() {
        guard model.state == .expanded else { return }
        Log.trace("collapse")
        holdUntilHover = false
        cancelAll()
        isHovering = false
        model.transition(to: model.restingState)
    }

    private func scheduleCollapse() {
        guard collapseTask == nil, expandedArmed, !inResizeGrace, model.keepsOpen?() != true else { return }
        #if DEBUG
        // PENDANT_DEBUG_STAY=1: never auto-collapse (headless screenshots of an open capsule).
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_STAY"] != nil { return }
        #endif
        let delay = model.collapseDelay
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.collapseTask = nil
            self?.collapse()
        }
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func cancelAll() {
        stopPointerWatch()
        expandTask?.cancel()
        unswellTask?.cancel()
        cancelCollapse()
    }
}

extension CapsuleInteractionController {
    // MARK: Pointer watch

    /// While the capsule is hovered (compact) or open (expanded) the pointer position is checked a few
    /// times a second. Tracking-area exits can be missed when the capsule changes size under a still
    /// pointer (it then stayed swollen); this makes leaving reliable without any event monitor.
    private func startPointerWatch() {
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled, let self else { return }
                if !checkPointer() { stopPointerWatch() }
            }
        }
    }

    private func stopPointerWatch() {
        watchTask?.cancel()
        watchTask = nil
    }

    /// A swollen secondary island whose exit was never reported goes back to rest.
    private func releaseStaleIslandHover(_ layout: CapsuleLayout, _ point: CGPoint) {
        guard let hovered = model.hoveredIsland, islandID(at: point) != hovered else { return }
        model.setHoveredIsland(nil)
        if !isHovering, !isInHit(layout, point, state: .compact) { setInteractive(false) }
    }

    /// Returns false when the watch is no longer needed.
    private func checkPointer() -> Bool {
        guard isActive, let layout = model.layout else { return false }
        let point = NSEvent.mouseLocation
        switch model.state {
        case .idle:
            // The swollen notch takes clicks (so a right click reaches our menu): if the pointer is no longer on it, hand the
            // clicks back and settle — a missed tracking-area exit must never leave it swollen and swallowing clicks.
            if isHovering || interactive, !layout.triggerRect(for: .idle).containsPointer(point) {
                if isHovering { leaveZone() }
                setInteractive(false)
            }
            return isHovering || interactive
        case .compact:
            if isHovering, !hoverRect(layout).containsPointer(point) { leaveZone() }
            // Safety net: a missed tracking-area exit must never leave the panel swallowing clicks.
            if !isHovering, interactive, !isInHit(layout, point, state: .compact) {
                Log.trace("safety net released the panel")
                setInteractive(false)
            }
            releaseStaleIslandHover(layout, point)
            return isHovering || interactive || model.hoveredIsland != nil
        case .expanded:
            let inside = layout.triggerRect(for: .expanded).containsPointer(point)
            if inside {
                if !inResizeGrace {
                    expandedArmed = true
                    holdUntilHover = false
                }
                cancelCollapse()
            } else {
                scheduleCollapse()
            }
            setInteractive(inside)
            return true
        }
    }

    /// Compact capsule including its swollen / song-info extension.
    private func hoverRect(_ layout: CapsuleLayout) -> CGRect {
        var rect = layout.triggerRect(for: .compact)
        let size = model.bodySize
        let top = rect.maxY
        let height = max(size.height, layout.bodySize(for: .compact).height) + 2 * NotchGeometry.triggerMargin
        let width = max(size.width, layout.bodySize(for: .compact).width) + 2 * NotchGeometry.triggerMargin + 2 * Self.sideLeaveSlack
        rect = CGRect(x: rect.midX - width / 2, y: top - height, width: width, height: height)
        return rect
    }

    // MARK: Geometry helpers and shutdown

    /// Stops everything this controller listens to (the notch on this screen is going away).
    func shutdown() {
        isActive = false
        removeMonitors()
        stopPointerWatch()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    private func isOnCapsule(_ layout: CapsuleLayout, _ point: CGPoint) -> Bool {
        switch model.state {
        case .idle: layout.triggerRect(for: .idle).containsPointer(point)
        case .compact: visibleBodyRect(layout).containsPointer(point)
        case .expanded: layout.triggerRect(for: .expanded).containsPointer(point)
        }
    }

    /// The capsule as currently drawn (including swell / peek), in screen coordinates.
    private func visibleBodyRect(_ layout: CapsuleLayout) -> CGRect {
        let size = model.bodySize
        let body = layout.bodyRect(for: model.state)
        return CGRect(x: body.midX - size.width / 2, y: body.maxY - size.height, width: size.width, height: size.height)
            .insetBy(dx: -NotchGeometry.earRadius, dy: 0)
    }

}
