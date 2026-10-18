import SwiftUI

/// 即時提示: the things the notch shows when the system does something — volume and brightness, the charger, a low battery, a
/// Bluetooth device.
struct SystemFeaturesSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section { SystemToastDemoView().illustrationRow() }
            Section("音量與亮度") {
                Toggle("音量", isOn: $settings.hudVolume)
                Toggle("亮度", isOn: $settings.hudBrightness)
                TipRow(title: "取代系統提示", tip: "需輔助使用") {
                    Toggle("", isOn: $settings.hudHideSystem).labelsHidden()
                        .onChange(of: settings.hudHideSystem) { _, on in if on { MediaKeyInterceptor.requestPermission() } }
                }
                SliderRow(title: "顯示時間", value: $settings.hudSeconds, range: 0.8...4, step: 0.2, unit: "秒", fractionDigits: 1)
            }
            Section("充電") {
                Toggle("充電提示", isOn: $settings.chargingToast)
                SliderRow(title: "顯示時間", value: $settings.chargingToastSeconds, range: 2...10, step: 0.5, unit: "秒", fractionDigits: 1)
                    .dimmed(when: !settings.chargingToast)
            }
            Section("低電量") {
                Toggle("低電量提示", isOn: $settings.lowBatteryToast)
                SliderRow(title: "閾值", value: $settings.lowBatteryThreshold, range: 5...50, unit: "%")
                    .dimmed(when: !settings.lowBatteryToast)
                TipRow(title: "有操作時自動關閉", tip: "沒有操作時提示會一直留著") {
                    Toggle("", isOn: $settings.lowBatteryDismissOnActivity).labelsHidden()
                }
                .dimmed(when: !settings.lowBatteryToast)
                SliderRow(title: "操作後延時", value: $settings.lowBatteryActivityDelay, range: 1...10, step: 0.5, unit: "秒", fractionDigits: 1)
                    .dimmed(when: !settings.lowBatteryToast || !settings.lowBatteryDismissOnActivity)
            }
            Section("藍牙") {
                TipRow(title: "連接提示", tip: "開啟時系統會詢問藍牙權限") {
                    Toggle("", isOn: $settings.bluetoothToast).labelsHidden()
                }
                SliderRow(title: "顯示時間", value: $settings.bluetoothToastSeconds, range: 2...10, step: 0.5, unit: "秒", fractionDigits: 1)
                    .dimmed(when: !settings.bluetoothToast)
            }
        }
        .formStyle(.grouped)
    }
}
