import SwiftUI

/// The open capsule's status strip, top right beside the notch: battery (icon and percent) and the "new version" tag. Each part
/// has its own switch in 設定 › 狀態列.
struct StatusStrip: View {
    @State private var settings = AppSettings.shared
    private let battery = BatteryMonitor.shared
    private let updater = UpdateChecker.shared

    var body: some View {
        HStack(spacing: 10) {
            if settings.statusUpdateTag, updater.availableRelease != nil {
                Button { SettingsWindowController.shared.show(tab: .about) } label: {
                    Text("有新版本可用")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .foregroundStyle(Color(red: 0.42, green: 0.05, blue: 0.1))
                        .background(Color(red: 1, green: 0.78, blue: 0.8), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color(red: 0.93, green: 0.55, blue: 0.6), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hapticOnHover()
                .accessibilityLabel("有新版本可用，打開關於頁面")
            }
            if settings.statusBattery, let reading = battery.reading {
                HStack(spacing: 4) {
                    Image(systemName: reading.charging ? "battery.100percent.bolt" : BatteryMonitor.symbol(percent: reading.percent))
                        .font(.system(size: 15, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(reading.percent <= 20 && !reading.pluggedIn ? Color.red : .white)
                    Text("\(reading.percent)%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("電量 \(reading.percent)%\(reading.charging ? "，充電中" : "")")
            }
        }
    }
}

/// 設定 › 狀態列.
struct StatusBarSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section { StatusBarIllustration().illustrationRow() }
            Section("大膠囊右上角") {
                Toggle("顯示電量(圖示與百分比)", isOn: $settings.statusBattery)
                Toggle("有新版本時顯示「有新版本可用」", isOn: $settings.statusUpdateTag)
            }
        }
        .formStyle(.grouped)
    }
}
