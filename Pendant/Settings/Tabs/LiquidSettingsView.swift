import SwiftUI

/// 7.5 Liquid (macOS 26+ only; the tab does not exist on older systems).
struct LiquidSettingsView: View {
    @State private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section { AppearanceIllustration().illustrationRow() }
            Section("Liquid Glass") {
                Toggle("使用 Liquid Glass", isOn: $settings.liquidGlassEnabled)
                    .disabled(reduceTransparency)
                    .settingNote(reduceTransparency ? "系統已開啟「降低透明度」，Liquid Glass 已自動停用。" : nil)
                // The stored switch is "use the system's own control" (off by default); this one is its opposite.
                Toggle("自製 Liquid Glass 元件", isOn: Binding(get: { !settings.nativeSegmented }, set: { settings.nativeSegmented = !$0 }))
                    .disabled(reduceTransparency || !settings.liquidGlassEnabled)
                    .settingNote("開啟時，系統沒有提供 Liquid Glass 版本的元件(例如計時器的倒數／碼錶)，會改用 Pendant 自製的 Liquid Glass;關閉則使用系統原生的樣式。")
            }
        }
        .formStyle(.grouped)
    }
}
