import SwiftUI

/// 動態島: where the secondary islands sit, how they appear, their sizes and how long an idle activity stays.
struct ActivitiesSettingsView: View {
    @State private var settings = AppSettings.shared
    #if DEBUG
    @State private var sizeOpen = ProcessInfo.processInfo.environment["PENDANT_DEBUG_ISLAND_SIZE"] != nil
    #else
    @State private var sizeOpen = false
    #endif

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section { IslandDemoView(interactive: false).illustrationRow() }
            Section("副島") {
                Toggle("左副島", isOn: $settings.islandLeftEnabled)
                Toggle("右副島", isOn: $settings.islandRightEnabled)
                TipRow(title: "優先側", tip: "只有一個副島時，放在優先側") {
                    Picker("", selection: $settings.islandPrioritySide) {
                        Text("左").tag(IslandSide.left)
                        Text("右").tag(IslandSide.right)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                DropdownRow(title: "顯示方式", selection: $settings.islandDisplayMode, options: [
                    (IslandDisplayMode.always, "一直顯示"), (.brief, "變化時短暫顯示"), (.hoverOnly, "游標靠近才顯示"),
                ])
                TipRow(title: "選單展開時隱藏", tip: "選單列的選單展開時，暫時收起副島") {
                    Toggle("", isOn: $settings.islandHideDuringMenus).labelsHidden()
                }
                TipRow(title: "下沉", tip: "副島垂直下移，避免與瀏海邊緣重疊") {
                    Toggle("", isOn: $settings.islandSinking).labelsHidden()
                }
                TipRow(title: "避開選單列", tip: "需輔助使用") {
                    Toggle("", isOn: $settings.islandSmartAvoid).labelsHidden()
                }
                DisclosureRow(title: "尺寸", isExpanded: $sizeOpen)
                if sizeOpen {
                    SliderRow(title: "總寬度上限", tip: "主島與副島合計；超過時，優先級最低的副島會被隱藏",
                              value: $settings.islandMaxSpanPercent, range: 20...80, unit: "%")
                    SliderRow(title: "島間距", value: $settings.islandGap, range: 2...20, unit: "pt")
                    SliderRow(title: "最大寬度", value: $settings.islandMaxWidth, range: 44...120, unit: "pt")
                    SliderRow(title: "左側偏移", value: $settings.islandLeftOffset, range: -40...80, unit: "pt")
                    SliderRow(title: "右側偏移", value: $settings.islandRightOffset, range: -40...80, unit: "pt")
                }
            }
            Section {
                SliderRow(title: "閒置隱藏延時", tip: "小工具閒置（例如音樂暫停、計時器暫停）時，繼續顯示在動態島上的時間",
                          value: $settings.mediaPauseRetention, range: 0...300, unit: "秒")
            }
        }
        .formStyle(.grouped)
    }
}
