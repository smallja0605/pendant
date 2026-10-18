import SwiftUI

/// 7.6 Gestures.
struct GesturesSettingsView: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section { GestureDemoView().illustrationRow() }
            Section("媒體:雙指左右滑動切歌") {
                Toggle("啟用", isOn: $settings.swipeTracksEnabled)
                sensitivity("靈敏度", value: $settings.swipeThreshold)
                    .disabled(!settings.swipeTracksEnabled)
                Toggle("反轉方向", isOn: $settings.swipeReversed)
                    .disabled(!settings.swipeTracksEnabled)
            }
            Section("日曆:左右滑動切換日期") {
                Toggle("啟用", isOn: $settings.calendarSwipeEnabled)
                sensitivity("靈敏度", value: $settings.calendarSwipeThreshold)
                    .disabled(!settings.calendarSwipeEnabled)
            }
        }
        .formStyle(.grouped)
    }

    /// Lower threshold = more sensitive, so the slider is shown inverted.
    private func sensitivity(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Text("低").font(.caption).foregroundStyle(.secondary)
                HapticSlider(value: Binding(get: { 150 - value.wrappedValue }, set: { value.wrappedValue = 150 - $0 }), in: 30...120)
                Text("高").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
