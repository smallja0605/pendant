import SwiftUI

/// The small capsule's waveform settings (設定 › 小工具 › 小膠囊 › 音樂): real sound, bars, balance, gain, sensitivity, the cover's colours.
struct CompactWaveformRows: View {
    @State private var settings = AppSettings.shared

    private static var canTap: Bool { if #available(macOS 14.2, *) { true } else { false } }
    private var barCount: Binding<Double> {
        Binding(get: { Double(settings.waveformBars) }, set: { settings.waveformBars = min(max(Int($0.rounded()), 3), 7) })
    }
    private var gain: Binding<Double> {
        Binding(get: { Double(settings.waveformGain) }, set: { settings.waveformGain = min(max(Int($0.rounded()), 50), 200) })
    }
    private var sensitivity: Binding<Double> {
        Binding(get: { Double(settings.waveformSensitivity) }, set: { settings.waveformSensitivity = min(max(Int($0.rounded()), 50), 200) })
    }

    var body: some View {
        TipRow(title: "真實音波", tip: "依實際播放的聲音動，需要「系統音訊錄製」權限") {
            Toggle("", isOn: $settings.realWaveform).labelsHidden().disabled(!Self.canTap)
        }
        if settings.realWaveform { WaveformStatusRow() }
        SliderRow(title: "音波線條數量", value: barCount, range: 3...7, step: 1, unit: "條")
        if settings.realWaveform {
            DropdownRow(title: "音波平衡器", selection: $settings.waveformFocus, options: [
                (0, "全頻"), (1, "低音（鼓點）"), (2, "人聲"), (3, "高音"),
            ])
            SliderRow(title: "音波漲幅", value: gain, range: 50...200, step: 5, unit: "%")
            SliderRow(title: "音波靈敏度", value: sensitivity, range: 50...200, step: 5, unit: "%")
        }
        TipRow(title: "依專輯顏色", tip: "音波圖用專輯封面的顏色（漸層），換歌時顏色漸變") {
            Toggle("", isOn: $settings.waveformArtworkColor).labelsHidden()
        }
    }
}
