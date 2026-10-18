import SwiftUI

/// 7.6 Gestures.
struct GesturesSettingsView: View {
    @State private var settings = AppSettings.shared
    @Environment(\.sliderLength) private var sliderLength

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section { GestureDemoView().illustrationRow() }
            Section("媒體") {
                Toggle("啟用", isOn: $settings.swipeTracksEnabled)
                sensitivity("靈敏度", value: $settings.swipeThreshold)
                    .dimmed(when: !settings.swipeTracksEnabled)
                Toggle("反轉方向", isOn: $settings.swipeReversed)
                    .dimmed(when: !settings.swipeTracksEnabled)
            }
            Section("日曆") {
                Toggle("啟用", isOn: $settings.calendarSwipeEnabled)
                sensitivity("靈敏度", value: $settings.calendarSwipeThreshold)
                    .dimmed(when: !settings.calendarSwipeEnabled)
            }
        }
        .formStyle(.grouped)
    }

    /// Lower threshold = more sensitive, so the slider is shown inverted.
    private func sensitivity(_ title: String, value: Binding<Double>) -> some View {
        TipRow(title: title) {
            HapticSlider(value: Binding(get: { 150 - value.wrappedValue }, set: { value.wrappedValue = 150 - $0 }), in: 30...120,
                         ends: ("低", "高"))
                .frame(width: sliderLength + 40)
        }
    }
}
