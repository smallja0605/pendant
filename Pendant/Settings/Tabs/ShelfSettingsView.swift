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
            Section { ShelfIllustration().illustrationRow() }
            Section("自動清除") {
                Picker("清除時機", selection: $settings.shelfAutoClear) {
                    Text("不自動清除").tag(AppSettings.ShelfAutoClear.never)
                    Text("登出時").tag(AppSettings.ShelfAutoClear.onLogout)
                    Text("重新開機時").tag(AppSettings.ShelfAutoClear.onReboot)
                    // The option names the number of days chosen below.
                    Text("\(settings.shelfAutoClearDays) 天後").tag(AppSettings.ShelfAutoClear.afterDays)
                }
                if settings.shelfAutoClear == .afterDays {
                    LabeledContent("天數") {
                        HStack {
                            NumberField(value: dayCount, range: 1...365)
                            Stepper("", value: $settings.shelfAutoClearDays, in: 1...365).labelsHidden()
                            Text("天")
                        }
                    }
                }
            }
            Section("版面") {
                LabeledContent("AirDrop 區寬度") {
                    HStack {
                        HapticSlider(value: $settings.shelfAirDropPercent, in: 10...60, step: 1)
                        NumberField(value: $settings.shelfAirDropPercent, range: 10...60)
                        Text("%")
                    }
                }
                .settingNote("檔案抽屜佔剩下的寬度。")
            }
            Section("拖曳自動展開") {
                Toggle("拖曳檔案靠近瀏海時自動展開", isOn: $settings.dragOpensShelf)
                LabeledContent("觸發距離") {
                    HStack {
                        HapticSlider(value: $settings.dragProximity, in: 60...200, step: 5)
                        Text("\(Int(settings.dragProximity)) pt").monospacedDigit().frame(width: 56, alignment: .trailing)
                    }
                }
                .disabled(!settings.dragOpensShelf)
            }
            Section {
                Text(
                    "拖入與拖出一律是複製，原檔不會被移動;檔案存放於 Application Support 的 Shelf 資料夾，沒有數量與容量上限，請搭配自動清除使用。"
                    + "放到「AirDrop」區會直接開啟傳送面板,不留下複本;放開後沒有放進任何區域時,膠囊會自動收合。"
                )
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
