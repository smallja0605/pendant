import SwiftUI

/// What a virtual notch (a screen without a physical one) shows in its three parts: the battery on the left, the clock in the
/// middle, the percentage on the right. While an activity (music, timer, shelf…) is live it takes both sides over: the side
/// contents blur out as the activity's icons blur in, the same way the volume HUD replaces the capsule.
struct VirtualNotchContent: View {
    let model: CapsuleModel
    let size: CGSize
    @State private var settings = AppSettings.shared

    var body: some View {
        let notch = model.layout?.notch.size ?? .zero
        let wing = max((size.width - notch.width) / 2, 0)
        let free = model.activity == nil
        let margin = Tuning.shared.iconMargin + 3
        // The parts are centred in the row the capsule's own icons use (the swollen height without the song line, see
        // `CompactContent`), so showing the song line under them does not move them, and the gap below the clock is not odd.
        let compact = model.layout?.bodySize(for: .compact) ?? size
        let swollen = model.showsSwell ? (model.layout?.swelledSize(compact, reduceMotion: model.reduceMotion) ?? compact) : compact
        let row = min(swollen.height, size.height)
        ZStack(alignment: .top) {
            if settings.virtualMiddle == .clock {
                VirtualClockView(settings: settings).frame(width: notch.width, height: row)
            }
            HStack(spacing: 0) {
                VirtualBatteryGlyph(style: settings.virtualBatteryStyle, size: 15)
                    .opacity(settings.virtualLeft == .battery ? 1 : 0)
                    .frame(width: wing, height: row, alignment: .leading)
                    .padding(.leading, margin)
                    .modifier(RevealEffect(isVisible: free, delay: 0.06, blurOnExit: true))
                Spacer(minLength: 0)
                VirtualPercentText()
                    .opacity(settings.virtualLeft == .battery && settings.virtualBatteryPercent ? 1 : 0)
                    .frame(width: wing, height: row, alignment: .trailing)
                    .padding(.trailing, margin)
                    .modifier(RevealEffect(isVisible: free, delay: 0.06, blurOnExit: true))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
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
                showsDate: settings.virtualClockDate, dateFormat: settings.virtualDateFormat
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

/// The battery as an icon (a bolt in it while charging) or a ring (a bolt in the middle while charging, red when it is low).
struct VirtualBatteryGlyph: View {
    let style: VirtualBatteryStyle
    var size: CGFloat
    private let battery = BatteryMonitor.shared

    var body: some View {
        if let reading = battery.reading {
            switch style {
            case .icon:
                Image(systemName: reading.charging ? "battery.100percent.bolt" : BatteryMonitor.symbol(percent: reading.percent))
                    .font(.system(size: size))
                    .foregroundStyle(.white)
            case .ring:
                let low = !reading.charging && Double(reading.percent) <= AppSettings.shared.lowBatteryThreshold
                ToastRing(progress: Double(reading.percent) / 100, tint: low ? .red : .green,
                          symbol: reading.charging ? "bolt.fill" : nil, lineWidth: 2.6, symbolSize: size * 0.5)
                    .frame(width: size + 3, height: size + 3)
            }
        }
    }
}

/// The charge as a number.
struct VirtualPercentText: View {
    var size: CGFloat = 11.5
    private let battery = BatteryMonitor.shared

    var body: some View {
        if let reading = battery.reading {
            Text("\(reading.percent)%").font(.system(size: size, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.white).fixedSize()
        }
    }
}

/// The open capsule's centre strip on a virtual notch: battery · date · time, where the small capsule was.
struct VirtualBigStrip: View {
    /// Room the strip may take in the middle of the open capsule's top row (the mode switcher and the status strip give way).
    static let width: CGFloat = 230
    @State private var settings = AppSettings.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 12) {
                if settings.virtualBigBattery {
                    HStack(spacing: 5) {
                        VirtualBatteryGlyph(style: settings.virtualBatteryStyle, size: 15)
                        if settings.virtualBatteryPercent { VirtualPercentText() }
                    }
                }
                if settings.virtualBigDate {
                    Text(VirtualClockFormat.date(context.date, format: settings.virtualDateFormat))
                }
                if settings.virtualBigTime {
                    Text(VirtualClockFormat.time(context.date, use24Hour: settings.virtualClock24h, seconds: settings.virtualClockSeconds))
                        .fontWeight(.bold)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
        }
    }
}
