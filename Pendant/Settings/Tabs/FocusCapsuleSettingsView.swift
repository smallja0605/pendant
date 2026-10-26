import SwiftUI

/// 獨立膠囊: the settings of the capsule that shows a single tool's page (the music page with its lyrics, …). The list on the left names the
/// tools that have such a page; the selected one's settings are on the right, in titled cards like the big capsule's tools.
struct FocusCapsuleSettingsView: View {
    @State private var selection = "media"
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
        Tool(id: "reminders", title: "待辦事項", symbol: "checklist", ready: false),
        Tool(id: "calendar", title: "行事曆", symbol: "calendar", ready: false),
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

/// The music page of the single-tool capsule: the waveform beside the title, and the lyrics.
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
            moduleGroup("歌詞") {
                LyricsSourcesSection()
                TipRow(title: "線上歌詞", tip: "歌名、歌手與長度會送到已開啟的線上來源") {
                    Toggle("", isOn: $settings.onlineLyrics).labelsHidden()
                }
                SliderRow(title: "歌詞時間調整", tip: "歌詞比聲音慢就調大（提早出現），比聲音快就調小", value: $settings.lyricsOffset,
                          range: -3...3, step: 0.1, unit: "秒", fractionDigits: 1)
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
