import SwiftUI

/// Timer page of the expanded capsule (requirements 4.4).
@MainActor
final class TimerModule: PendantModule {
    let id = "timer"
    let displayName = String(localized: "module.timer", defaultValue: "Timer")
    let symbolName = "timer"
    let cells = CellRange(default: 4, range: 3...6)
    let supportsCompact = true
    var isEnabled = false

    private let controller = TimerController.shared

    func makeView(size: CGSize) -> AnyView {
        AnyView(TimerView(controller: controller).frame(width: size.width, height: size.height))
    }

    func makeSettingsView() -> AnyView { AnyView(TimerModuleSettings()) }

    var activityPriority: Int { 1 }

    func makeCompactView(role: IslandRole) -> AnyView? {
        role == .secondary ? AnyView(TimerIslandContent()) : nil
    }

    func activate() {}
    func deactivate() {}
}

private struct TimerModuleSettings: View {
    @State private var settings = AppSettings.shared
    @State private var presetsText = ""

    var body: some View {
        ModuleForm(moduleID: "timer") {
            TipRow(title: "快速計時") {
                HStack {
                    TextField("1, 5, 10, 25", text: $presetsText)
                        .textFieldStyle(.roundedBorder).frame(width: 150).onSubmit(commitPresets)
                    Text("分鐘").foregroundStyle(.secondary)
                }
            }
            Toggle("提示音", isOn: $settings.timerSound)
            Toggle("系統通知", isOn: $settings.timerNotification)
        }
        .onAppear { presetsText = settings.timerPresets.map(String.init).joined(separator: ", ") }
        .onDisappear(perform: commitPresets)
    }

    private func commitPresets() {
        let values = presetsText.split(whereSeparator: { ", ，".contains($0) }).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let valid = values.filter { (1...999).contains($0) }.prefix(6)
        if !valid.isEmpty { settings.timerPresets = Array(valid) }
        presetsText = settings.timerPresets.map(String.init).joined(separator: ", ")
    }
}

/// Countdown or stopwatch as a secondary island: coloured icon (countdown: orange ring that empties, stopwatch: blue)
/// and the remaining / elapsed time, refreshed once a second.
struct TimerIslandContent: View {
    var mode: TimerEngine.Mode = .countdown

    var body: some View {
        let engine = TimerController.shared.engine(for: mode)
        let color = TimerStyle.color(for: mode)
        let symbol = TimerStyle.symbol(for: mode)
        HStack(spacing: 8) {
            if AppSettings.shared.timerRing, mode == .countdown {
                ZStack {
                    TimerProgressRing(lineWidth: 2)
                    Image(systemName: symbol).font(.system(size: 8, weight: .semibold)).foregroundStyle(color)
                }
                .frame(width: 18, height: 18)
            } else {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(TimerEngine.format(engine.displayTime(at: context.date)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.identity)
                    .animation(nil, value: TimerEngine.format(engine.displayTime(at: context.date)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }
}
