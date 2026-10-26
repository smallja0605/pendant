import AppKit
import SwiftUI

/// What the simulation panel can trigger: made-up events that go through the real capsule, so every card, island and
/// animation can be looked at without a player, a charger or a Bluetooth device.
@MainActor
final class Simulator {
    static let shared = Simulator()

    private var trackNumber = 0
    private var playing = false
    private var savedDuration: TimeInterval?
    private var restoreTask: Task<Void, Never>?

    private var manager: NotchManager? { AppDelegate.currentManager }
    private var timer: TimerController { TimerController.shared }

    /// Everything the developer window started stops: the made-up track, the card, both timers (the countdown goes back to the
    /// user's own duration).
    func stopAll() {
        restoreTask?.cancel()
        manager?.media.endSimulation()
        manager?.hideToasts()
        trackNumber = 0
        playing = false
        timer.reset(.stopwatch)
        timer.reset()
        if let saved = savedDuration { timer.setDuration(saved) }
        savedDuration = nil
    }

    // MARK: Music

    private static let palettes: [[NSColor]] = [
        [.systemPink, .systemOrange, .systemPurple], [.systemTeal, .systemBlue, .systemIndigo],
        [.systemGreen, .systemYellow, .systemTeal], [.systemRed, .systemOrange, .systemYellow], [.systemPurple, .systemBlue, .systemMint],
    ]

    func newTrack(playing: Bool = true) {
        trackNumber = (1...99).randomElement() ?? 1
        self.playing = playing
        publishTrack()
    }

    func togglePlayback() {
        if trackNumber == 0 { newTrack(); return }
        playing.toggle()
        publishTrack()
    }

    private func publishTrack() {
        manager?.media.simulate(
            title: "歌曲 \(trackNumber)", artist: "歌手 \(Int.random(in: 1...30))", album: "專輯 \(Int.random(in: 1...20))",
            playing: playing, key: "sim-\(trackNumber)-\(UInt32.random(in: 0...9999))",
            colors: Self.palettes.randomElement() ?? Self.palettes[0]
        )
    }

    // MARK: Cards

    func charging() {
        let reading = BatteryMonitor.Reading(percent: Int.random(in: 40...95), charging: true, pluggedIn: true)
        manager?.simulateToast(SystemEventMonitor.chargingToast(reading), seconds: 6)
    }

    func lowBattery() {
        let reading = BatteryMonitor.Reading(percent: Int.random(in: 8...20), charging: false, pluggedIn: false)
        manager?.simulateToast(SystemEventMonitor.lowBatteryToast(reading), seconds: 6)
    }

    static let devices: [(name: String, symbol: String)] = [
        ("耳機", "headphones"), ("鍵盤", "keyboard"), ("滑鼠", "computermouse"), ("喇叭", "hifispeaker"),
        ("觸控板", "rectangle.and.hand.point.up.left"),
    ]

    func bluetooth(battery: Int, device kind: Int? = nil) {
        let device = kind.map { Self.devices[$0] } ?? Self.devices.randomElement() ?? Self.devices[0]
        let toast = SystemToast(
            title: "\(device.0) \(Int.random(in: 1...9))", subtitle: "已連接 · \(battery)%", progress: Double(battery) / 100, tint: .blue,
            ringSymbol: "bluetooth", trailing: .symbol(device.1)
        )
        manager?.simulateToast(toast, seconds: 6)
    }

    // MARK: Timer

    func stopwatchStart() {
        timer.viewMode = .stopwatch
        if !timer.isStopwatchRunning { timer.toggle(.stopwatch) }
    }

    func stopwatchEnd() { timer.reset(.stopwatch) }

    func countdownStart() {
        restoreTask?.cancel()
        if savedDuration == nil { savedDuration = timer.engine.duration }
        timer.viewMode = .countdown
        timer.reset()
        timer.setDuration(30)
        timer.start()
    }

    /// Runs out in two seconds (what the finish looks like), then the countdown goes back to the user's own duration.
    func countdownEnd() {
        restoreTask?.cancel()
        if savedDuration == nil { savedDuration = timer.engine.duration }
        timer.viewMode = .countdown
        timer.reset()
        timer.setDuration(2)
        timer.start()
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, let saved = savedDuration else { return }
            timer.reset()
            timer.setDuration(saved)
            savedDuration = nil
        }
    }
}

/// The sidebar button (above the tour): opens the developer window.
struct SimulationButton: View {
    var body: some View {
        Button { DeveloperWindowController.shared.show() } label: {
            Label("開發者視窗", systemImage: "wrench.and.screwdriver.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.environment["PENDANT_DEBUG_SIMULATE"] != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            DeveloperWindowController.shared.show()
            // PENDANT_DEBUG_SIM=music|bluetooth|countdown fires that simulation two seconds after the window opens.
            if let action = ProcessInfo.processInfo.environment["PENDANT_DEBUG_SIM"] {
                try? await Task.sleep(for: .seconds(2))
                switch action {
                case "music": Simulator.shared.newTrack()
                case "bluetooth": Simulator.shared.bluetooth(battery: 35)
                default: Simulator.shared.countdownEnd()
                }
                // PENDANT_DEBUG_SIM_CLOSE=1 closes the window 3 s later (what closing it does to the simulation).
                if ProcessInfo.processInfo.environment["PENDANT_DEBUG_SIM_CLOSE"] != nil {
                    try? await Task.sleep(for: .seconds(3))
                    DeveloperWindowController.shared.window?.close()
                }
            }
        }
        #endif
    }
}

/// The developer window: its own window beside the settings. Closing it stops everything it started.
@MainActor
final class DeveloperWindowController: NSObject, NSWindowDelegate {
    static let shared = DeveloperWindowController()
    fileprivate(set) var window: NSWindow?

    func show() {
        if window == nil {
            let window = FreeWindow.hosting(SimulationPanel())
            window.setContentSize(NSSize(width: 340, height: 300))
            window.title = tr("開發者視窗")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        if let window { WindowPresence.opened(window) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Simulator.shared.stopAll()
    }
}

/// The window's content: buttons grouped by kind. Music is random each time ("歌曲 12 · 歌手 3"), the Bluetooth card takes its battery
/// from the slider.
private struct SimulationPanel: View {
    @State private var battery = 80.0
    @State private var device = 0
    private let simulator = Simulator.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            buttonGroups
            bluetoothGroup
        }
        .padding(16)
        .frame(width: 340)
    }

    @ViewBuilder private var buttonGroups: some View {
            group("音樂") {
                button("播放／暫停", "playpause.fill") { simulator.togglePlayback() }
                button("上一首", "backward.fill") { simulator.newTrack() }
                button("下一首", "forward.fill") { simulator.newTrack() }
            }
            group("電源") {
                button("充電中", "bolt.fill") { simulator.charging() }
                button("低電量", "battery.25percent") { simulator.lowBattery() }
            }
            group("計時") {
                button("碼錶開始", "play.fill") { simulator.stopwatchStart() }
                button("碼錶結束", "stop.fill") { simulator.stopwatchEnd() }
                button("倒數開始", "timer") { simulator.countdownStart() }
                button("倒數結束", "bell.fill") { simulator.countdownEnd() }
            }
    }

    private var bluetoothGroup: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("藍牙").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text("電量").font(.system(size: 12)).foregroundStyle(.secondary)
                    Slider(value: $battery, in: 0...100, step: 1).frame(maxWidth: .infinity)
                    Text("\(Int(battery))%").font(.system(size: 12).monospacedDigit()).frame(width: 40, alignment: .trailing)
                }
                HStack(spacing: 8) {
                    Picker("", selection: $device) {
                        ForEach(Simulator.devices.indices, id: \.self) { index in
                            Label(Simulator.devices[index].name, systemImage: Simulator.devices[index].symbol).tag(index)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                    button("連接裝置", "link") { simulator.bluetooth(battery: Int(battery), device: device) }
                }
            }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            FlowButtons { content() }
        }
    }

    private func button(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// Wraps its buttons onto several lines.
private struct FlowButtons<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        FlowLayout(spacing: 6) { content }
    }
}
