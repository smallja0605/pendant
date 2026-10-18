import SwiftUI

/// 7.5 Liquid (macOS 26+ only; the tab does not exist on older systems).
struct LiquidSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var tuning = Tuning.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private func tuned(_ key: ReferenceWritableKeyPath<Tuning, Double>) -> Binding<Double> {
        Binding(get: { tuning[keyPath: key] }, set: { tuning[keyPath: key] = $0; tuning.save() })
    }

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section { LiquidDemoView().illustrationRow() }
            Section {
                Toggle("使用 Liquid Glass", isOn: $settings.liquidGlassEnabled)
                    .dimmed(when: reduceTransparency)
                    .settingNote(reduceTransparency ? "系統已開啟「降低透明度」" : nil)
                // The stored switch is "use the system's own control" (off by default); this one is its opposite.
                Toggle("自製 Liquid Glass 元件", isOn: Binding(get: { !settings.nativeSegmented }, set: { settings.nativeSegmented = !$0 }))
                    .dimmed(when: reduceTransparency || !settings.liquidGlassEnabled)
                    .settingNote("系統沒有提供的元件改用自製版本")
            }
            Section("膠囊尺寸") {
                SliderRow(title: "小膠囊側翼寬度", value: tuned(\.wingExtra), range: -10...40, unit: "pt")
                SliderRow(title: "大膠囊每格寬度", value: tuned(\.cellWidth), range: 40...110, unit: "pt")
                SliderRow(title: "大膠囊內容高度", value: tuned(\.expandedContentHeight), range: 110...240, unit: "pt")
            }
        }
        .formStyle(.grouped)
    }
}
