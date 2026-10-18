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
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("快速預設(分鐘,以逗號分隔)") {
                TextField("1, 5, 10, 25", text: $presetsText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .onSubmit(commitPresets)
            }
            Toggle("小膠囊顯示剩餘時間圓圈", isOn: $settings.timerRing)
            Toggle("結束時播放提示音", isOn: $settings.timerSound)
            Toggle("結束時顯示系統通知", isOn: $settings.timerNotification)
            Text("計時使用絕對時間,休眠或 App 卡頓都不會造成誤差。進行中會在小膠囊顯示剩餘時間。")
                .font(.caption).foregroundStyle(.secondary)
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
