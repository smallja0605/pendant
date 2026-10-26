import SwiftUI

/// 虛擬瀏海: the notch on a screen without one (battery · clock · percentage) and, beside it, the open capsule's centre strip,
/// both live with the settings. Hovering the notch shows what happens when an activity is live: it takes both sides over.
struct VirtualNotchDemoView: View {
    @State private var settings = AppSettings.shared
    @State private var tuning = Tuning.shared
    @State private var hovering = false

    private let bar = DemoDesk<EmptyView>.menuBarHeight
    private let screenWidth = DemoDesk<EmptyView>.screenWidth

    var body: some View {
        HStack(spacing: 10) {
            DemoDesk(viewport: 330, height: 90) { notch }
            DemoDesk(viewport: 440, height: 90) { open }
        }
    }

    private var wing: CGFloat { CapsuleLayout.virtualWing + tuning.wingExtra }
    private var width: CGFloat { NotchGeometry.virtualContentWidth + 2 * wing }
    private var margin: CGFloat { tuning.iconMargin + 3 }

    private var notch: some View {
        let middle = NotchGeometry.virtualContentWidth
        return ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: concealed ? 3 : 15, bottomTrailingRadius: concealed ? 3 : 15)
                .fill(Color.black)
                .frame(width: shownWidth, height: shownHeight)
                .overlay {
                    ZStack {
                        if settings.virtualMiddle == .clock { VirtualClockView(settings: settings).frame(width: middle) }
                        if settings.virtualMiddle == .lyrics {
                            Text("歌詞").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).frame(width: middle)
                        }
                        HStack(spacing: 0) {
                            VirtualBatteryGlyph(style: settings.virtualBatteryStyle, size: 15)
                                .opacity(settings.virtualLeft == .battery ? 1 : 0)
                                .frame(width: wing, alignment: .leading).padding(.leading, margin)
                                .modifier(RevealEffect(isVisible: !hovering, delay: 0.06))
                            Spacer(minLength: 0)
                            VirtualPercentText()
                                .opacity(settings.virtualLeft == .battery && settings.virtualBatteryPercent ? 1 : 0)
                                .frame(width: wing, alignment: .trailing).padding(.trailing, margin)
                                .modifier(RevealEffect(isVisible: !hovering, delay: 0.06))
                        }
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                                .frame(width: 20, height: 20).frame(width: wing, alignment: .leading).padding(.leading, tuning.iconMargin)
                            Spacer(minLength: 0)
                            HStack(spacing: 2.5) {
                                ForEach(0..<3, id: \.self) { _ in Capsule().fill(.white).frame(width: 2.5, height: 12) }
                            }
                            .frame(width: wing, alignment: .trailing).padding(.trailing, margin)
                        }
                        .modifier(RevealEffect(isVisible: hovering, delay: 0.06))
                    }
                    .frame(width: width, height: bar)
                }
                .clipped()
                .frame(width: width, height: bar, alignment: .top)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active = phase { hovering = true } else { hovering = false }
                }
                .frame(width: screenWidth, alignment: .top)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: wing)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: concealed)
        }
    }

    /// The idle look chosen in 閒置: a thin bar or nothing until the pointer is on it.
    private var concealed: Bool { !hovering && settings.virtualIdleHide != .off }
    private var shownWidth: CGFloat {
        concealed ? (settings.virtualIdleHide == .sliver ? CapsuleLayout.virtualSliver.width : 0) : width
    }
    private var shownHeight: CGFloat {
        concealed ? (settings.virtualIdleHide == .sliver ? CapsuleLayout.virtualSliver.height : 0) : bar
    }

    /// The top of the open capsule: mode switcher on the left, the strip in the middle, the status on the right.
    private var open: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26)
            .fill(Color.black)
            .frame(width: 420, height: bar + 44)
            .overlay(alignment: .top) {
                ZStack {
                    HStack {
                        HStack(spacing: 6) {
                            Text("小工具").padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(.white.opacity(0.22)))
                            Text("檔案").foregroundStyle(.white.opacity(0.55))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .padding(.leading, 16)
                    if settings.virtualBigStrip { VirtualBigStrip().transition(.opacity.combined(with: .scale(scale: 0.94))) }
                }
                .foregroundStyle(.white)
                .frame(width: 420, height: bar)
            }
            .frame(width: screenWidth, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: settings.virtualBigStrip)
    }
}
