import SwiftUI

/// What a virtual notch (a screen without a physical one) shows in its three parts: the clock in the middle, the battery on the
/// left, nothing yet on the right. While an activity (music, timer, shelf…) is live it takes both sides over: the side contents
/// blur out as the activity's icons blur in, the same way the volume HUD replaces the capsule.
struct VirtualNotchContent: View {
    let model: CapsuleModel
    let size: CGSize
    @State private var settings = AppSettings.shared

    var body: some View {
        let notch = model.layout?.notch.size ?? .zero
        let wing = max((size.width - notch.width) / 2, 0)
        let free = model.activity == nil
        ZStack {
            if settings.virtualMiddle == .clock {
                VirtualClockView(settings: settings).frame(width: notch.width, height: size.height)
            }
            HStack(spacing: 0) {
                VirtualSideView(kind: settings.virtualLeft, showsPercent: settings.virtualBatteryPercent)
                    .frame(width: wing, height: size.height, alignment: .leading)
                    .padding(.leading, Tuning.shared.iconMargin + 3)
                    .modifier(RevealEffect(isVisible: free, delay: 0.06, blurOnExit: true))
                Spacer(minLength: 0)
                VirtualSideView(kind: settings.virtualRight, showsPercent: settings.virtualBatteryPercent)
                    .frame(width: wing, height: size.height, alignment: .trailing)
                    .padding(.trailing, Tuning.shared.iconMargin + 3)
                    .modifier(RevealEffect(isVisible: free, delay: 0.06, blurOnExit: true))
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// The clock of the virtual notch's middle part.
struct VirtualClockView: View {
    let settings: AppSettings

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(VirtualClockFormat.string(
                for: context.date, use24Hour: settings.virtualClock24h, seconds: settings.virtualClockSeconds,
                showsDate: settings.virtualClockDate
            ))
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .contentTransition(.identity)
            .padding(.horizontal, 6)
        }
    }
}

/// One side of the virtual notch.
struct VirtualSideView: View {
    let kind: VirtualSide
    let showsPercent: Bool
    private let battery = BatteryMonitor.shared

    var body: some View {
        switch kind {
        case .battery:
            if let reading = battery.reading {
                HStack(spacing: 3) {
                    Image(systemName: reading.charging ? "battery.100percent.bolt" : BatteryMonitor.symbol(percent: reading.percent))
                        .font(.system(size: 14))
                    if showsPercent { Text("\(reading.percent)%").font(.system(size: 10.5, weight: .semibold)).monospacedDigit() }
                }
                .foregroundStyle(.white)
                .fixedSize()
            }
        case .none:
            EmptyView()
        }
    }
}
