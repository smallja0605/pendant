import SwiftUI

/// 7.7 Live activities: which activities may appear in the compact capsule, and their priority.
struct ActivitiesSettingsView: View {
    @State private var settings = AppSettings.shared

    private struct Info {
        let title: String
        let symbol: String
        let ready: Bool
    }

    private static let titles: [String: Info] = [
        "timer": Info(title: "倒數計時器", symbol: "timer", ready: true),
        "stopwatch": Info(title: "碼錶", symbol: "stopwatch", ready: true),
        "media": Info(title: "媒體播放中", symbol: "music.note", ready: true),
        "reminders": Info(title: "提醒到期", symbol: "checklist", ready: false),
        "shelf": Info(title: "檔案抽屜暫存數", symbol: "tray.and.arrow.down", ready: true),
    ]

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section { IslandsIllustration().illustrationRow() }
            Section("小膠囊顯示的活動(由上到下為優先順序)") {
                List {
                    ForEach(settings.activityPriority, id: \.self) { id in
                        if let info = Self.titles[id] {
                            HStack {
                                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                                Image(systemName: info.symbol).frame(width: 22)
                                VStack(alignment: .leading) {
                                    Text(info.title)
                                    if !info.ready { Text("即將推出…").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Picker("", selection: roleBinding(id)) {
                                    Text("可當副島").tag(ActivityRole.anyIsland)
                                    Text("只能當主島").tag(ActivityRole.mainOnly)
                                    Text("不顯示").tag(ActivityRole.hidden)
                                }
                                .labelsHidden()
                                .frame(width: 110)
                            }
                        }
                    }
                    .onMove { settings.activityPriority.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(minHeight: 150)
                Button("還原預設順序") { settings.activityPriority = AppSettings.defaultActivityPriority }
            }
            Section("分島(副島最多 2 個)") {
                Toggle("左側副島", isOn: $settings.islandLeftEnabled)
                Toggle("右側副島", isOn: $settings.islandRightEnabled)
                Picker("優先顯示側", selection: $settings.islandPrioritySide) {
                    Text("左").tag(IslandSide.left)
                    Text("右").tag(IslandSide.right)
                }
                .pickerStyle(.segmented)
                Picker("顯示模式", selection: $settings.islandDisplayMode) {
                    Text("常駐").tag(IslandDisplayMode.always)
                    Text("短暫顯示").tag(IslandDisplayMode.brief)
                    Text("僅 hover 主島時").tag(IslandDisplayMode.hoverOnly)
                }
                slider("島間距", value: $settings.islandGap, range: 2...20, unit: "pt")
                slider("總寬度上限", value: $settings.islandMaxSpanPercent, range: 20...80, unit: "%")
                slider("副島最大寬度", value: $settings.islandMaxWidth, range: 44...120, unit: "pt")
                slider("左側偏移", value: $settings.islandLeftOffset, range: -40...80, unit: "pt")
                slider("右側偏移", value: $settings.islandRightOffset, range: -40...80, unit: "pt")
            }
            Section("媒體暫停後") {
                LabeledContent("保留時間") {
                    HStack {
                        HapticSlider(value: $settings.mediaPauseRetention, in: 0...300, step: 1)
                        NumberField(value: $settings.mediaPauseRetention, range: 0...300)
                        Text("秒")
                    }
                }
                .settingNote("暫停超過這個時間,音樂就不再算進行中活動,計時器等其他活動會晉升為主島(0 = 一暫停就結束;測試晉升時可調成 3 秒)。")
            }
            Section("音量與亮度") {
                Toggle("調整音量時顯示", isOn: $settings.hudVolume)
                Toggle("調整亮度時顯示(內建螢幕)", isOn: $settings.hudBrightness)
                Toggle("同時隱藏系統自己的音量／亮度提示", isOn: $settings.hudHideSystem)
                    .onChange(of: settings.hudHideSystem) { _, on in if on { MediaKeyInterceptor.requestPermission() } }
                LabeledContent("顯示時間") {
                    HStack {
                        HapticSlider(value: $settings.hudSeconds, in: 0.8...4, step: 0.2)
                        NumberField(value: $settings.hudSeconds, range: 0.8...4)
                        Text("秒")
                    }
                }
                .settingNote(
                    "隱藏系統提示需要「輔助使用」權限:授權後音量、亮度、靜音鍵會由 Pendant 接手(Shift+Option 為細調)，系統完全不會出現自己的提示;"
                    + "沒有授權時只能在偵測到變化後停掉系統的提示程式，按鍵瞬間可能還會閃一下。"
                )
            }
            Section("避免遮擋選單列") {
                Toggle("選單展開時自動隱藏副島", isOn: $settings.islandHideDuringMenus)
                Toggle("下沉模式(副島懸掛在選單列下方)", isOn: $settings.islandSinking)
                Toggle("智慧避讓(實驗性,需「輔助使用」權限)", isOn: $settings.islandSmartAvoid)
                    .settingNote("智慧避讓只讀取前景 App 選單列的位置,用來讓左側副島避開選單項目;未授權或失敗時自動退回手動偏移。")
            }
            Section("小膠囊樣式") {
                Toggle("顯示專輯封面", isOn: $settings.showCoverInCompact)
                Toggle("顯示音波圖", isOn: $settings.showWaveformInCompact)
                Toggle("換歌時顯示歌曲資訊", isOn: $settings.showTrackInfoOnChange)
                LabeledContent("顯示時間") {
                    HStack {
                        HapticSlider(value: $settings.trackInfoSeconds, in: 1...8, step: 0.5)
                        NumberField(value: $settings.trackInfoSeconds, range: 1...8)
                        Text("秒")
                    }
                }
                .disabled(!settings.showTrackInfoOnChange)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Make sure every known activity is in the list (settings saved by older versions).
            for id in AppSettings.defaultActivityPriority + ["shelf"] where !settings.activityPriority.contains(id) {
                settings.activityPriority.append(id)
            }
        }
    }

    private func roleBinding(_ id: String) -> Binding<ActivityRole> {
        Binding(get: { settings.activityRole(id) }, set: { settings.setActivityRole(id, $0) })
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        LabeledContent(title) {
            HStack {
                HapticSlider(value: value, in: range, step: 1)
                Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().frame(width: 60, alignment: .trailing)
            }
        }
    }
}
