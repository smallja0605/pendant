import SwiftUI

/// 檔案中轉站 tab: clean-up and drag-near-notch behaviour (requirements 4.6). There is no size / count cap on the shelf.
struct ShelfSettingsView: View {
    @State private var settings = AppSettings.shared

    /// `NumberField` edits a Double; the days setting is an Int.
    private var dayCount: Binding<Double> {
        Binding(get: { Double(settings.shelfAutoClearDays) }, set: { settings.shelfAutoClearDays = Int($0.rounded()) })
    }

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section { ShelfDemoView().illustrationRow() }
            Section("自動清除") {
                // The last option names the number of days chosen below.
                DropdownRow(title: "清除時機", selection: $settings.shelfAutoClear, options: [
                    (AppSettings.ShelfAutoClear.never, "不自動清除"), (.onLogout, "登出時"), (.onReboot, "重新開機時"),
                    (.afterDays, tr("\(settings.shelfAutoClearDays) 天後")),
                ])
                if settings.shelfAutoClear == .afterDays {
                    SliderRow(title: "天數", value: dayCount, range: 1...365, unit: "天")
                }
            }
            Section("版面") {
                ShelfRatioRow(airDropPercent: $settings.shelfAirDropPercent)
            }
            Section("拖曳自動展開") {
                Toggle("拖曳檔案靠近瀏海時自動展開", isOn: $settings.dragOpensShelf)
                SliderRow(title: "觸發距離", value: $settings.dragProximity, range: 60...200, step: 5, unit: "pt")
                    .dimmed(when: !settings.dragOpensShelf)
                Toggle("跨螢幕拖曳時不展開", isOn: $settings.dragIgnoresOtherScreens)
                    .dimmed(when: !settings.dragOpensShelf)
            }
        }
        .formStyle(.grouped)
    }
}

/// 檔案中轉站比例: the drawer's share of the page against the AirDrop area's, set with one slider. It moves in tens; holding ⌘
/// moves it in single percents. The digits at both ends are the two shares (tens normally, whole percents with ⌘), and every step
/// ticks the trackpad.
private struct ShelfRatioRow: View {
    @Binding var airDropPercent: Double
    @State private var fine = false
    @Environment(\.sliderLength) private var sliderLength

    private var drawer: Double { 100 - airDropPercent }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("檔案中轉站比例")
                Spacer(minLength: 12)
                share(label(drawer), alignment: .trailing)
                Slider(value: Binding(get: { drawer }, set: { set($0) }), in: 10...90) { EmptyView() }
                    .labelsHidden()
                    .frame(width: sliderLength)
                share(label(airDropPercent), alignment: .leading)
            }
            Text("左側抽屜，右側 AirDrop；按住 ⌘ 微調")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onModifierChange { fine = $0.contains(.command) }
    }

    private func share(_ text: String, alignment: Alignment) -> some View {
        Text(text).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
            .frame(width: 30, alignment: alignment)
    }

    /// Tens as one digit ("8"), whole percents with ⌘ ("78").
    private func label(_ percent: Double) -> String {
        fine ? "\(Int(percent.rounded()))" : "\(Int((percent / 10).rounded()))"
    }

    private func set(_ raw: Double) {
        let commandHeld = NSEvent.modifierFlags.contains(.command)
        let snapped = commandHeld ? raw.rounded() : (raw / 10).rounded() * 10
        let newAirDrop = 100 - min(max(snapped, 10), 90)
        guard newAirDrop != airDropPercent else { return }
        HapticService.shared.play(.dragStep)
        airDropPercent = newAirDrop
    }
}

private extension View {
    /// Calls `action` with the keyboard modifiers whenever they change while the settings window is up.
    func onModifierChange(_ action: @escaping (NSEvent.ModifierFlags) -> Void) -> some View {
        modifier(ModifierWatcher(action: action))
    }
}

private struct ModifierWatcher: ViewModifier {
    let action: (NSEvent.ModifierFlags) -> Void
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                    action(event.modifierFlags)
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
