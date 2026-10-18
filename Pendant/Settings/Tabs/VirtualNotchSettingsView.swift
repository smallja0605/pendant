import SwiftUI

/// 虛擬瀏海: what a screen without a physical notch puts into its three parts.
struct VirtualNotchSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section { VirtualNotchDemoView().illustrationRow() }
            Section {
                TipRow(title: "啟用", tip: "僅限沒有瀏海的螢幕") {
                    Toggle("", isOn: $settings.virtualNotchEnabled).labelsHidden()
                }
            }
            Group {
                Section("中間") {
                    DropdownRow(title: "內容", selection: $settings.virtualMiddle, options: [
                        (VirtualMiddle.clock, "時間"), (.none, "無"),
                    ])
                    DropdownRow(title: "時間格式", selection: $settings.virtualClock24h, options: [(true, "24 小時"), (false, "12 小時")])
                        .dimmed(when: settings.virtualMiddle != .clock)
                    Toggle("秒數", isOn: $settings.virtualClockSeconds).dimmed(when: settings.virtualMiddle != .clock)
                    Toggle("日期", isOn: $settings.virtualClockDate).dimmed(when: settings.virtualMiddle != .clock)
                }
                Section("左側") {
                    DropdownRow(title: "內容", selection: $settings.virtualLeft, options: [(VirtualSide.battery, "電量"), (.none, "無")])
                    if settings.virtualLeft == .battery {
                        Toggle("百分比", isOn: $settings.virtualBatteryPercent)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                Section("右側") {
                    DropdownRow(title: "內容", selection: $settings.virtualRight, options: [(VirtualSide.none, "無")])
                }
            }
            .dimmed(when: !settings.virtualNotchEnabled)
        }
        .formStyle(.grouped)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: settings.virtualLeft)
    }
}
