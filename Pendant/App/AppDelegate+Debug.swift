#if DEBUG
import AppKit
import SwiftUI

extension AppDelegate {
    // Environment-variable hooks used for headless checks (screenshots, timing); debug builds only.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func installDebugHooks(notch: NotchWindowController) {
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_TUNING"] != nil { tuningWindow.show() }
        // PENDANT_DEBUG_SETTINGS=<tab> (a SettingsTab raw value) opens the settings window; _SCALE=0.6 shrinks it for full-page shots.
        if let raw = ProcessInfo.processInfo.environment["PENDANT_DEBUG_SETTINGS"] {
            SettingsWindowController.shared.show(tab: SettingsTab(rawValue: raw) ?? .general)
        }
        // A/B diagnostics for menu-bar glitches: hide the notch panel entirely (combine with PENDANT_DEBUG_NO_MONITORS).
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_NO_PANEL"] != nil { notch.isPaused = true }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_CALENDAR"] == "fake" { CalendarStore.shared.enableFakeData() }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_REMINDERS"] == "fake" { RemindersStore.shared.enableFakeData() }
        if let mode = ProcessInfo.processInfo.environment["PENDANT_DEBUG_TIMER"] {
            // PENDANT_DEBUG_TIMER=run starts a 5-minute countdown; =finish makes one that ends after 2 s.
            TimerController.shared.setDuration(mode == "finish" ? 2 : 300)
            if mode != "idle" { TimerController.shared.start() }
        }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_NOTES"] != nil { NoteStore.shared.debugSeed() }
        if let mode = ProcessInfo.processInfo.environment["PENDANT_DEBUG_SHELF"] {
            // seed: three sample files go onto the real shelf (clear: empties it again)
            if mode == "clear" { ShelfStore.shared.clear() } else {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pendant-debug-shelf", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let urls = ["報告.txt", "photo.png", "notes.md"].map { dir.appendingPathComponent($0) }
                urls.forEach { try? "sample".write(to: $0, atomically: true, encoding: .utf8) }
                ShelfStore.shared.add(urls: urls)
            }
        }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_CHECK_UPDATE"] != nil {
            Task { await UpdateChecker.shared.check(userInitiated: true) }
        }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_HOTKEY"] != nil {
            // Same path as the global shortcut; prints whether the panel got keyboard focus.
            Task { @MainActor [weak notch] in
                try? await Task.sleep(for: .seconds(2))
                notch?.toggleExpanded()
                try? await Task.sleep(for: .seconds(1))
                let key = NSApp.keyWindow
                fputs("HOTKEY active=\(NSApp.isActive) key=\(key.map { String(describing: type(of: $0)) } ?? "none")\n", stderr)
            }
        }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_PANELSTATE"] != nil {
            Task { @MainActor [weak notch] in
                while !Task.isCancelled {
                    fputs("PANEL \(notch?.debugPanelState() ?? "-")\n", stderr)
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
        if let folder = ProcessInfo.processInfo.environment["PENDANT_DEBUG_GESTURE_DEMO"] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                IllustrationExporter.exportGestureFrames(to: URL(fileURLWithPath: folder))
            }
        }
        if let folder = ProcessInfo.processInfo.environment["PENDANT_DEBUG_ICON"] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                AppIconExporter.export(to: URL(fileURLWithPath: folder))
            }
        }
        if let folder = ProcessInfo.processInfo.environment["PENDANT_DEBUG_ILLUSTRATIONS"] {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                IllustrationExporter.export(to: URL(fileURLWithPath: folder))
            }
        }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_TOUR_PAGE"] != nil { TourWindowController.shared.show() }
        if let kind = ProcessInfo.processInfo.environment["PENDANT_DEBUG_HUD"] {
            // PENDANT_DEBUG_HUD=volume|brightness|mute|low: shows the HUD two seconds after launch.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                let level: SystemLevel = switch kind {
                case "brightness": .brightness(level: 0.7)
                case "mute": .volume(level: 0.4, muted: true)
                case "low": .volume(level: 0.15, muted: false)
                default: .volume(level: 0.7, muted: false)
                }
                self?.notchManager?.debugHUD(level)
            }
        }
        if let module = ProcessInfo.processInfo.environment["PENDANT_DEBUG_FOCUS"] {
            // PENDANT_DEBUG_FOCUS=<module id>: opens that module's detailed page (use with PENDANT_DEBUG_CYCLE + _STAY).
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                ModuleRegistry.shared.focus(module)
            }
        }
        if let kind = ProcessInfo.processInfo.environment["PENDANT_DEBUG_TOAST"] {
            // PENDANT_DEBUG_TOAST=charging|low|bluetooth: shows that system card two seconds after launch (and stays for 30 s).
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                let charging = kind == "charging"
                let reading = BatteryMonitor.Reading(percent: kind == "low" ? 18 : 70, charging: charging, pluggedIn: charging)
                let toast: SystemToast = switch kind {
                case "low": SystemEventMonitor.lowBatteryToast(reading)
                case "bluetooth": SystemToast(title: "耳機 1", subtitle: "已連接 · 70%", progress: 0.7, tint: .blue,
                                              ringSymbol: "bluetooth", trailing: .symbol("headphones"))
                default: SystemEventMonitor.chargingToast(reading)
                }
                self?.notchManager?.simulateToast(toast, seconds: 30)
            }
        }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_TIMER_FLIP"] != nil {
            // Switches the timer page between countdown and stopwatch twice (the liquid tab slider).
            Task { @MainActor in
                for mode in [TimerEngine.Mode.stopwatch, .countdown] {
                    try? await Task.sleep(for: .seconds(2.2))
                    withAnimation(.bouncy(duration: 0.5, extraBounce: 0.12)) { TimerController.shared.viewMode = mode }
                }
            }
        }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_STOPWATCH"] != nil {
            TimerController.shared.toggle(.stopwatch)
        }
        if let ids = ProcessInfo.processInfo.environment["PENDANT_DEBUG_MODULES"] {
            ModuleRegistry.shared.debugSetEnabled(ids.split(separator: ",").map(String.init)) // not persisted
        }
        if let tab = ProcessInfo.processInfo.environment["PENDANT_DEBUG_TAB_VIEW"] { ModuleRegistry.shared.setTab(tab) }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_SETTINGS"] != nil {
            let tab = ProcessInfo.processInfo.environment["PENDANT_DEBUG_TAB"].flatMap(SettingsTab.init(rawValue:))
            SettingsWindowController.shared.show(tab: tab)
        }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_PULSE"] != nil { notch.debugPulseSwell() }
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_HOVER"] != nil {
            Task { @MainActor [weak notch] in
                try? await Task.sleep(for: .seconds(1.2))
                let mode = ProcessInfo.processInfo.environment["PENDANT_DEBUG_HOVER"]
                notch?.debugCompactHover(artwork: mode == "artwork", controls: mode == "controls")
            }
        }
        if let step = ProcessInfo.processInfo.environment["PENDANT_DEBUG_STEP"] {
            // PENDANT_DEBUG_STEP=next|prev: plays the swipe icon (and the song line) a few seconds after launch.
            Task { @MainActor [weak notch] in
                try? await Task.sleep(for: .seconds(2))
                notch?.debugTrackInfo()
                switch step {
                case "cancel": notch?.debugStepCancel()
                case "flip": notch?.debugStepFlip()
                default: notch?.debugStep(forward: step == "next", leftwards: step == "prev")
                }
            }
        }
        if let mode = ProcessInfo.processInfo.environment["PENDANT_DEBUG_MEDIA"] { notch.debugMedia(playing: mode != "pause") }
        if let mode = ProcessInfo.processInfo.environment["PENDANT_DEBUG_COMPACT"] {
            notch.setActivity(mode == "shelf" ? .init(symbolName: "tray.full", kind: .shelf) : .init(symbolName: "music.note"))
        }
        // Headless smoke test: PENDANT_DEBUG_CYCLE=1 expands after 1.5 s and collapses 2.5 s later.
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_CYCLE"] != nil {
            Task { @MainActor [weak notch] in
                try? await Task.sleep(for: .seconds(1.5))
                notch?.debugExpand()
                // PENDANT_DEBUG_STAY=1 keeps it open (for screenshots of popovers).
                guard ProcessInfo.processInfo.environment["PENDANT_DEBUG_STAY"] == nil else { return }
                try? await Task.sleep(for: .seconds(2.5))
                notch?.debugCollapse()
            }
        }
    }
}
#endif
