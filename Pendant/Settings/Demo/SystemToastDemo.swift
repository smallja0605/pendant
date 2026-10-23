import SwiftUI

/// 即時提示: the system cards one after the other (charging, low battery, a Bluetooth device) as they grow out of the notch.
struct SystemToastDemoView: View {
    private static let cards: [SystemToast] = [
        SystemEventMonitor.chargingToast(.init(percent: 70, charging: true, pluggedIn: true)),
        SystemEventMonitor.lowBatteryToast(.init(percent: 18, charging: false, pluggedIn: false)),
        SystemToast(title: "耳機 1", subtitle: "已連接 · 70%", progress: 0.7, tint: .blue, ringSymbol: "bluetooth",
                    trailing: .symbol("headphones")),
    ]

    private let bar = DemoDesk<EmptyView>.menuBarHeight
    private let screenWidth = DemoDesk<EmptyView>.screenWidth

    var body: some View {
        DemoDesk(viewport: 480, height: 120) {
            TimelineView(.periodic(from: .now, by: 3.2)) { context in
                let index = Int(context.date.timeIntervalSinceReferenceDate / 3.2) % Self.cards.count
                card(Self.cards[index], index: index)
            }
        }
    }

    private func card(_ toast: SystemToast, index: Int) -> some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28)
            .fill(Color.black)
            .frame(width: CapsuleLayout.virtualToastWidth, height: CapsuleLayout.toastContentHeight)
            .overlay(alignment: .top) {
                ToastContent(toast: toast)
                    .frame(width: CapsuleLayout.virtualToastWidth, height: CapsuleLayout.toastContentHeight)
                    .id(index)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
            .frame(width: screenWidth, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: index)
    }
}
