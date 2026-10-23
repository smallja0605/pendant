import SwiftUI

/// 檔案中轉站: the shelf's two faces side by side, half the width each — the small capsule (tray on the left wing, the count on
/// the right, the notch between; the newest file's line under it, as wide as the capsule) and the open big capsule with the
/// drawer and AirDrop zones split by the real ratio. Everything follows the settings; the names are made up.
struct ShelfDemoView: View {
    @State private var settings = AppSettings.shared
    @State private var tuning = Tuning.shared

    private let bar = DemoDesk<EmptyView>.menuBarHeight
    private let screenWidth = DemoDesk<EmptyView>.screenWidth

    var body: some View {
        HStack(spacing: 10) {
            DemoDesk(viewport: 330, height: 100) { compact }
            DemoDesk(viewport: 530, height: 160) { open }
        }
    }

    private var wing: CGFloat { bar + tuning.wingExtra }
    private var compactWidth: CGFloat { NotchGeometry.virtualSize.width + 2 * wing }
    private var openWidth: CGFloat { min(max(tuning.cellWidth * 6 + 24, compactWidth), 500) }
    private var drawerShare: CGFloat { CGFloat(100 - settings.shelfAirDropPercent) / 100 }

    private var compact: some View {
        // One black shape, as in the real capsule: the file line is part of it, so no corner shows between the two.
        let peekHeight: CGFloat = settings.shelfPeekEnabled ? 28 : 0
        return UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15)
            .fill(Color.black)
            .frame(width: compactWidth, height: bar + peekHeight)
            .overlay(alignment: .top) {
                HStack(spacing: 0) {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 15, weight: .semibold))
                        .frame(width: wing, alignment: .leading).padding(.leading, tuning.iconMargin + 3)
                    Spacer(minLength: 0)
                    if settings.shelfShowsCount {
                        Text("3").font(.system(size: 15, weight: .bold, design: .rounded))
                            .frame(width: wing, alignment: .trailing).padding(.trailing, tuning.iconMargin + 3)
                    }
                }
                .foregroundStyle(.white)
                .frame(width: compactWidth, height: bar)
            }
            .overlay(alignment: .bottom) {
                if settings.shelfPeekEnabled {
                    HStack(spacing: 6) {
                        if settings.shelfPeekWithIcon { Image(systemName: "doc.fill") }
                        Text("檔案 1.txt · 211 KB")
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .frame(width: compactWidth, height: peekHeight)
                    .transition(.opacity)
                }
            }
            .frame(width: screenWidth, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: settings.shelfPeekEnabled)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: settings.shelfShowsCount)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: tuning.wingExtra)
    }

    private var open: some View {
        let inner = openWidth - 24
        let drawer = (inner - 8) * drawerShare
        return UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26)
            .fill(Color.black)
            .frame(width: openWidth, height: bar + 100)
            .overlay(alignment: .top) {
                HStack(spacing: 8) {
                    Text("檔案抽屜").frame(width: drawer)
                        .frame(maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                    Text("AirDrop").frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.35, green: 0.69, blue: 0.93)))
                }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.top, bar + 4).padding(.bottom, 12)
            }
            .frame(width: screenWidth, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.4, dampingFraction: 0.72), value: settings.shelfAirDropPercent)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tuning.cellWidth)
    }
}
