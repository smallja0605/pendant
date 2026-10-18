import SwiftUI

/// "Pendant" tab with two sub-pages: capsule / notch settings (7.3) and widget management (4.10).
struct PendantSettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general = "一般"
        case widgets = "自訂小工具"
        var id: String { rawValue }
    }

    @State private var page = Page.widgets

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $page) {
                ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            .padding(.vertical, 10)
            Divider()
            switch page {
            case .general: CapsuleSettingsView()
            case .widgets: WidgetsSettingsView()
            }
        }
    }
}

/// 7.3 Capsule and notch.
struct CapsuleSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var tuning = Tuning.shared

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section("瀏海") {
                Toggle("瀏海懸停效果", isOn: $settings.hoverEffectEnabled)
                    .settingNote("總開關:同時控制膨脹動畫與進入震動;懸停展開與點擊展開不受影響。")
                LabeledContent("實體瀏海寬度微調") {
                    HStack {
                        HapticSlider(value: $settings.notchWidthAdjust, in: -30...30, step: 1)
                        Text(String(format: "%+.0f pt", settings.notchWidthAdjust)).monospacedDigit().frame(width: 56, alignment: .trailing)
                        Button("重設為自動") { settings.notchWidthAdjust = 0 }
                    }
                }
            }
            Section("膠囊") {
                slider("小膠囊側翼寬度", value: $tuning.wingExtra, range: -10...40, unit: "pt")
                slider("大膠囊每格寬度", value: $tuning.cellWidth, range: 40...110, unit: "pt")
                slider("大膠囊內容高度", value: $tuning.expandedContentHeight, range: 110...240, unit: "pt")
                    .settingNote("調整時可直接在螢幕上方看到膠囊的變化。更細的數值在「開發者選項」(選單列按住 ⌥)。")
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        LabeledContent(title) {
            HStack {
                HapticSlider(
                    value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; tuning.save() }),
                    in: range, step: 1
                )
                Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().frame(width: 56, alignment: .trailing)
            }
        }
    }
}
