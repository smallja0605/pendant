import SwiftUI

/// 獨立膠囊: the settings of the capsule that shows a single tool's page (the music page with its lyrics, …). The list on the left names the
/// tools that have such a page; the selected one's settings are on the right, in titled cards like the big capsule's tools.
struct FocusCapsuleSettingsView: View {
    // PENDANT_DEBUG_FOCUS_TOOL=media|reminders|calendar opens that tool's page (for screenshots).
    @State private var selection = ProcessInfo.processInfo.environment["PENDANT_DEBUG_FOCUS_TOOL"] ?? "media"
    @Environment(\.pageViewportHeight) private var viewportHeight
    @State private var panelTop: CGFloat = 200

    private struct Tool {
        let id: String
        let title: String
        let symbol: String
        let ready: Bool
    }

    private static let tools = [
        Tool(id: "media", title: "音樂", symbol: "music.note", ready: true),
        Tool(id: "reminders", title: "待辦事項", symbol: "checklist", ready: true),
        Tool(id: "calendar", title: "行事曆", symbol: "calendar", ready: true),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 8) {
                ToolListCard {
                    VStack(spacing: 0) {
                        ForEach(Self.tools, id: \.id) { tool in
                            ToolRow(symbol: tool.symbol, title: tool.title, isSelected: selection == tool.id, comingSoon: !tool.ready)
                                .frame(height: 40)
                                .onTapGesture { if tool.ready { selection = tool.id } }
                        }
                    }
                }
            }
            .frame(width: 216)
            Group {
                switch selection {
                case "reminders": FocusRemindersSettings()
                case "calendar": FocusCalendarSettings()
                default: FocusMusicSettings()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: viewportHeight > 0 ? max(400, viewportHeight - panelTop - 24) : 400)
        }
        .background(GeometryReader { proxy in
            Color.clear.onChange(of: proxy.frame(in: .named(PageSpace.content)).minY, initial: true) { _, top in panelTop = top }
        })
    }
}

/// A slider row over one of the single-tool capsule's whole-number settings.
@MainActor
func focusSlider(
    _ title: String, _ path: ReferenceWritableKeyPath<FocusCapsuleSettings, Int>,
    range: ClosedRange<Int>, step: Int = 1, unit: String, tip: String? = nil
) -> some View {
    let settings = FocusCapsuleSettings.shared
    return SliderRow(
        title: title, tip: tip,
        value: Binding(get: { Double(settings[keyPath: path]) },
                       set: { settings[keyPath: path] = min(max(Int($0.rounded()), range.lowerBound), range.upperBound) }),
        range: Double(range.lowerBound)...Double(range.upperBound), step: Double(step), unit: unit
    )
}

/// The music page of the single-tool capsule: the waveform beside the title, the lyrics and the player.
private struct FocusMusicSettings: View {
    @State private var settings = AppSettings.shared
    @State private var focus = FocusCapsuleSettings.shared

    private var barCount: Binding<Double> {
        Binding(get: { Double(focus.waveformBars) }, set: { focus.waveformBars = min(max(Int($0.rounded()), 3), 7) })
    }
    private var gain: Binding<Double> {
        Binding(get: { Double(focus.waveformGain) }, set: { focus.waveformGain = min(max(Int($0.rounded()), 50), 200) })
    }
    private var sensitivity: Binding<Double> {
        Binding(get: { Double(focus.waveformSensitivity) }, set: { focus.waveformSensitivity = min(max(Int($0.rounded()), 50), 200) })
    }
    private static var canTap: Bool { if #available(macOS 14.2, *) { true } else { false } }

    var body: some View {
        Form {
            moduleGroup("音波圖", first: true) {
                Toggle("標題旁音波", isOn: $settings.showWaveformInTitle)
                Group {
                    TipRow(title: "真實音波", tip: "依實際播放的聲音動，需要「系統音訊錄製」權限") {
                        Toggle("", isOn: $focus.waveformReal).labelsHidden().disabled(!Self.canTap)
                    }
                    if focus.waveformReal { WaveformStatusRow() }
                    SliderRow(title: "音波線條數量", value: barCount, range: 3...7, step: 1, unit: "條")
                    if focus.waveformReal {
                        DropdownRow(title: "音波平衡器", selection: $focus.waveformFocus, options: [
                            (0, "全頻"), (1, "低音（鼓點）"), (2, "人聲"), (3, "高音"),
                        ])
                        SliderRow(title: "音波漲幅", value: gain, range: 50...200, step: 5, unit: "%")
                        SliderRow(title: "音波靈敏度", value: sensitivity, range: 50...200, step: 5, unit: "%")
                    }
                    TipRow(title: "依專輯顏色", tip: "音波圖用專輯封面的顏色（漸層），換歌時顏色漸變") {
                        Toggle("", isOn: $focus.waveformArtworkColor).labelsHidden()
                    }
                }
                .dimmed(when: !settings.showWaveformInTitle)
            }
            moduleGroup("歌詞外觀") {
                focusSlider("字級", \.lyricsFontSize, range: 12...28, unit: "pt")
                DropdownRow(title: "字重", selection: $focus.lyricsFontWeight, options: [
                    (0, "一般"), (1, "中等"), (2, "半粗"), (3, "粗"), (4, "特粗"),
                ])
                DropdownRow(title: "對齊", selection: $focus.lyricsCentered, options: [(false, "靠左"), (true, "置中")])
                focusSlider("其他行透明度", \.lyricsOthersOpacity, range: 10...80, step: 5, unit: "%", tip: "還沒唱到與已唱過的句子")
                focusSlider("其他行大小", \.lyricsOthersScale, range: 80...100, unit: "%")
                SliderRow(title: "捲動時間", value: $focus.lyricsScrollDuration, range: 0.2...1.2, step: 0.05, unit: "秒", fractionDigits: 2)
                Toggle("彈簧式捲動", isOn: $focus.lyricsScrollSpring)
                TipRow(title: "依專輯顏色", tip: "正在唱的那句（逐字歌詞的填色）用專輯封面的顏色") {
                    Toggle("", isOn: $focus.lyricsFillArtwork).labelsHidden()
                }
                Toggle("點歌詞跳到該句", isOn: $focus.lyricsTapToSeek)
            }
            moduleGroup("歌詞") {
                LyricsSourcesSection()
                TipRow(title: "線上歌詞", tip: "歌名、歌手與長度會送到已開啟的線上來源") {
                    Toggle("", isOn: $settings.onlineLyrics).labelsHidden()
                }
                SliderRow(title: "歌詞時間調整", tip: "歌詞比聲音慢就調大（提早出現），比聲音快就調小", value: $settings.lyricsOffset,
                          range: -3...3, step: 0.1, unit: "秒", fractionDigits: 1)
            }
            moduleGroup("播放器") {
                focusSlider("專輯光暈強度", \.glowStrength, range: 0...200, step: 5, unit: "%", tip: "100% = 大膠囊的光暈強度")
                focusSlider("播放器寬度", \.playerShare, range: 30...70, unit: "%", tip: "佔整個畫面的比例，預設 56%（最寬 5 格）")
                Toggle("顯示進度時間", isOn: $focus.showProgressTimes)
                Toggle("顯示 AirPlay 與音量按鈕", isOn: $focus.showOutputButtons)
            }
            moduleGroup("歌詞整理") {
                TipRow(title: "歌詞轉繁體", tip: "簡體中文歌詞轉成繁體（日文、韓文歌不轉）") {
                    Toggle("", isOn: $settings.lyricsTraditional).labelsHidden()
                }
                TipRow(title: "隱藏拼音歌詞", tip: "日文羅馬拼音、中文拼音這類只標發音的歌詞不顯示") {
                    Toggle("", isOn: $settings.lyricsHideRomanization).labelsHidden()
                }
                TipRow(title: "間奏顯示三點", tip: "間奏與「na na na」這類擬聲詞，改顯示倒數的三個點") {
                    Toggle("", isOn: $settings.lyricsFillerDots).labelsHidden()
                }
                TipRow(title: "長句自動斷行", tip: "中文歌詞依空格、英文長句在逗號或括號處分成兩段") {
                    Toggle("", isOn: $settings.lyricsSplitLines).labelsHidden()
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.top, -20)
        .padding(.horizontal, -20)
        .environment(\.sliderLength, 140)
    }
}

/// The reminders page of the single-tool capsule: the layout and what a new item starts with.
private struct FocusRemindersSettings: View {
    @State private var focus = FocusCapsuleSettings.shared
    @State private var store = RemindersStore.shared

    var body: some View {
        Form {
            moduleGroup("版面", first: true) {
                focusSlider("清單寬度比例", \.remindersSplit, range: 25...75, step: 5, unit: "%", tip: "清單佔的寬度，其餘是輸入框；50% = 5 : 5")
                focusSlider("預設高度", \.remindersExtraHeight, range: -60...240, step: 10, unit: "pt", tip: "比標準高多少；開啟時的高度，拖曳調整不會記住")
                DropdownRow(title: "調整高度的把手", selection: $focus.remindersHandle, options: [(0, "一直顯示"), (1, "滑過才顯示"), (2, "不顯示")])
            }
            moduleGroup("新增待辦") {
                DropdownRow(title: "預設清單", selection: $focus.remindersDefaultList,
                            options: [("", "系統預設")] + store.lists.map { ($0.id, $0.title) })
                DropdownRow(title: "預設優先度", selection: $focus.remindersDefaultPriority, options: [(0, "無"), (1, "低"), (2, "中"), (3, "高")])
                DropdownRow(title: "預設到期", selection: $focus.remindersDefaultDue, options: [(0, "無"), (1, "今天"), (2, "明天"), (3, "一小時後")])
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.top, -20)
        .padding(.horizontal, -20)
        .environment(\.sliderLength, 140)
        .task {
            await store.ensureAccess()
            await store.reload()
        }
    }
}

/// The calendar page of the single-tool capsule: the day strip and the event tiles.
private struct FocusCalendarSettings: View {
    @State private var focus = FocusCapsuleSettings.shared

    var body: some View {
        Form {
            moduleGroup("日期條", first: true) {
                focusSlider("今天的位置", \.calendarTodayPosition, range: 0...50, unit: "%", tip: "今天在日期條由左算起的位置，預設 15%")
                DropdownRow(title: "一週從哪天開始", selection: $focus.calendarWeekStart, options: [
                    (0, "跟隨系統"), (1, "週日"), (2, "週一"), (3, "週二"), (4, "週三"), (5, "週四"), (6, "週五"), (7, "週六"),
                ])
            }
            moduleGroup("行程") {
                focusSlider("行程磚寬度", \.calendarTileWidth, range: 140...320, step: 10, unit: "pt")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.top, -20)
        .padding(.horizontal, -20)
        .environment(\.sliderLength, 140)
    }
}
