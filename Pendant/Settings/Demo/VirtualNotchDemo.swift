import SwiftUI

/// 虛擬瀏海: the three parts on a screen without a notch (battery · clock · free), live with the settings. Hovering the notch
/// shows what happens when an activity is live: it takes both sides over.
struct VirtualNotchDemoView: View {
    @State private var settings = AppSettings.shared
    @State private var tuning = Tuning.shared
    @State private var hovering = false

    private let viewport: CGFloat = 400
    private let bar = DemoDesk<EmptyView>.menuBarHeight
    private let screenWidth = DemoDesk<EmptyView>.screenWidth

    var body: some View {
        DemoDesk(viewport: viewport, height: 92) { stage }
    }

    private var wing: CGFloat { CapsuleLayout.virtualWing + tuning.wingExtra }
    private var width: CGFloat { NotchGeometry.virtualContentWidth + 2 * wing }

    private var stage: some View {
        let notch = NotchGeometry.virtualContentWidth
        return ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15)
                .fill(Color.black)
                .frame(width: width, height: bar)
                .overlay {
                    ZStack {
                        if settings.virtualMiddle == .clock { VirtualClockView(settings: settings).frame(width: notch) }
                        HStack(spacing: 0) {
                            VirtualSideView(kind: settings.virtualLeft, showsPercent: settings.virtualBatteryPercent)
                                .frame(width: wing, alignment: .leading).padding(.leading, tuning.iconMargin + 3)
                                .modifier(RevealEffect(isVisible: !hovering, delay: 0.06))
                            Spacer(minLength: 0)
                            VirtualSideView(kind: settings.virtualRight, showsPercent: settings.virtualBatteryPercent)
                                .frame(width: wing, alignment: .trailing).padding(.trailing, tuning.iconMargin + 3)
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
                            .frame(width: wing, alignment: .trailing).padding(.trailing, tuning.iconMargin + 3)
                        }
                        .modifier(RevealEffect(isVisible: hovering, delay: 0.06))
                    }
                    .frame(width: width, height: bar)
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active = phase { hovering = true } else { hovering = false }
                }
                .frame(width: screenWidth, alignment: .top)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: wing)
        }
    }
}
