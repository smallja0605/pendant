import SwiftUI

/// 外觀: real controls (button, button group, switch, slider) over a colourful backdrop, drawn the way the capsule's own controls
/// are with the current Liquid Glass settings.
struct LiquidDemoView: View {
    @State private var settings = AppSettings.shared
    @State private var range = "day"
    @State private var on = true
    @State private var value = 0.4

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.17, green: 0.29, blue: 0.61), Color(red: 0.48, green: 0.25, blue: 0.54)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: 12) {
                    button
                    LiquidTabPicker(items: [.init(id: "day", title: "日"), .init(id: "week", title: "週"), .init(id: "month", title: "月")],
                                    selection: $range)
                    Toggle("", isOn: $on).labelsHidden().toggleStyle(.switch).environment(\.colorScheme, .dark)
                    Slider(value: $value).frame(width: 110).environment(\.colorScheme, .dark)
                }
                .scaleEffect(1.35)
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .animation(.easeOut(duration: 0.25), value: settings.liquidGlassEnabled)
        .animation(.easeOut(duration: 0.25), value: settings.nativeSegmented)
    }

    @ViewBuilder private var button: some View {
        if #available(macOS 26, *), LiquidGlass.isEnabled {
            Button("按鈕") {}.buttonStyle(.glass).controlSize(.large)
        } else {
            Button("按鈕") {}.buttonStyle(.bordered).controlSize(.large)
        }
    }
}
