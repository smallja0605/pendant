import SwiftUI

/// 小工具: the big capsule's tools (大膠囊) and the small capsule's (小膠囊).
struct PendantSettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case big = "大膠囊"
        case small = "小膠囊"
        var id: String { rawValue }
    }

    @Environment(\.settingsTitle) private var title
    #if DEBUG
    @State private var page = ProcessInfo.processInfo.environment["PENDANT_DEBUG_WIDGETS_PAGE"] == "small" ? Page.small : Page.big
    #else
    @State private var page = Page.big
    #endif

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                content.padding(.horizontal, 20).padding(.bottom, 20)
                    .environment(\.pageViewportHeight, proxy.size.height)
                    .coordinateSpace(name: PageSpace.content)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 30, weight: .bold)).padding(.top, 44)
            Picker("", selection: $page) {
                ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            switch page {
            case .big: WidgetsSettingsView()
            case .small: SmallCapsuleSettingsView()
            }
        }
    }
}

/// The coordinate space of the 小工具 page's content (its top is the scroll content's top).
enum PageSpace { static let content = "pendantPageContent" }

/// 7.3 Capsule and notch.
struct CapsuleSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var tuning = Tuning.shared

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section("瀏海") {
                Toggle("瀏海懸停效果", isOn: $settings.hoverEffectEnabled)
                    .settingNote("總開關:同時控制膨脹動畫與進入震動;懸停展開與點擊展開不受影響。")
                TipRow(title: "實體瀏海寬度微調") {
                    HStack {
                        HapticSlider(value: $settings.notchWidthAdjust, in: -30...30, step: 1)
                        Text(String(format: "%+.0f pt", settings.notchWidthAdjust)).monospacedDigit().frame(width: 56, alignment: .trailing)
                        Button("重設為自動") { settings.notchWidthAdjust = 0 }
                    }
                }
            }
            Section("膠囊") {
                slider("小膠囊側翼寬度", value: $tuning.wingExtra, range: -10...40, unit: "pt")
                slider("大膠囊每格寬度", value: $tuning.cellWidth, range: 40...110, unit: "pt")
                slider("大膠囊內容高度", value: $tuning.expandedContentHeight, range: 110...240, unit: "pt")
                    .settingNote("調整時可直接在螢幕上方看到膠囊的變化。更細的數值在「開發者選項」(選單列按住 ⌥)。")
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        TipRow(title: title) {
            HStack {
                HapticSlider(
                    value: Binding(get: { value.wrappedValue }, set: { value.wrappedValue = $0; tuning.save() }),
                    in: range, step: 1
                )
                Text("\(Int(value.wrappedValue)) \(unit)").monospacedDigit().frame(width: 56, alignment: .trailing)
            }
        }
    }
}
