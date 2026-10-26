import SwiftUI

/// 虛擬瀏海: what a screen without a physical notch puts into its three parts, and into the open capsule's top row.
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
                TipRow(title: "全螢幕時隱藏", tip: "App 進入全螢幕（綠燈）時，瀏海暫時隱藏") {
                    Toggle("", isOn: $settings.virtualHideInFullscreen).labelsHidden()
                }
                .dimmed(when: !settings.virtualNotchEnabled)
            }
            idleSection
            Group {
                middleSection
                leftSection
                Section("右側") {
                    DropdownRow(title: "內容", selection: $settings.virtualRight, options: [(VirtualSide.none, "無")])
                }
                bigSection
            }
            .dimmed(when: !settings.virtualNotchEnabled)
        }
        .formStyle(.grouped)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: settings.virtualLeft)
    }

    private var idleSection: some View {
        Section("閒置") {
            DropdownRow(title: "沒有動態時", tip: "沒有音樂、計時器等需要顯示的內容時", selection: $settings.virtualIdleHide, options: [
                (VirtualIdleHide.off, "照常顯示"), (.sliver, "縮成細條"), (.hidden, "完全隱藏"),
            ])
            if settings.virtualIdleHide == .hidden {
                TipRow(title: "游標移到頂端中央時顯示", tip: "關閉後，只有需要顯示的內容才會出現（仍可用快捷鍵展開）") {
                    Toggle("", isOn: $settings.virtualIdleHover).labelsHidden()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .dimmed(when: !settings.virtualNotchEnabled)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: settings.virtualIdleHide)
    }

    private var middleSection: some View {
        Section("中間") {
            DropdownRow(title: "內容", tip: settings.virtualMiddle == .lyrics ? "播放中顯示同步歌詞，沒有歌詞時顯示時間" : nil,
                        selection: $settings.virtualMiddle, options: [(VirtualMiddle.clock, "時間"), (.lyrics, "歌詞"), (.none, "無")])
            DropdownRow(title: "時間格式", selection: $settings.virtualClock24h, options: [(true, "24 小時"), (false, "12 小時")])
                .dimmed(when: settings.virtualMiddle == .none)
            Toggle("秒數", isOn: $settings.virtualClockSeconds).dimmed(when: settings.virtualMiddle == .none)
            Toggle("日期", isOn: $settings.virtualClockDate).dimmed(when: settings.virtualMiddle == .none)
            DropdownRow(title: "日期格式", selection: $settings.virtualDateFormat,
                        options: VirtualDateFormat.allCases.map { ($0, $0.title) })
        }
    }

    private var leftSection: some View {
        Section("左側") {
            DropdownRow(title: "內容", selection: $settings.virtualLeft, options: [(VirtualSide.battery, "電量"), (.none, "無")])
            if settings.virtualLeft == .battery {
                DropdownRow(title: "樣式", selection: $settings.virtualBatteryStyle,
                            options: [(VirtualBatteryStyle.icon, "電池圖示"), (.ring, "圓環")])
                    .transition(.opacity.combined(with: .move(edge: .top)))
                Toggle("百分比", isOn: $settings.virtualBatteryPercent)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var bigSection: some View {
        Section("大膠囊") {
            TipRow(title: "顯示", tip: "在大膠囊上方中間，原本小膠囊的位置") {
                Toggle("", isOn: $settings.virtualBigStrip).labelsHidden()
            }
            Toggle("電量", isOn: $settings.virtualBigBattery).dimmed(when: !settings.virtualBigStrip)
            Toggle("日期", isOn: $settings.virtualBigDate).dimmed(when: !settings.virtualBigStrip)
            Toggle("時間", isOn: $settings.virtualBigTime).dimmed(when: !settings.virtualBigStrip)
        }
    }
}
