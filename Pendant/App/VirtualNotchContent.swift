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
            } else if settings.virtualMiddle == .lyrics {
                VirtualLyricsView(model: model, settings: settings)
                    .frame(width: notch.width + (model.layout?.virtualMiddleExtra ?? 0), height: row)
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

/// How much wider than its resting width the virtual notch's middle part has to be for the lyric line it shows (the capsule widens
/// with it). Set by `VirtualLyricsView`; the notch controllers re-plan when it changes.
@MainActor
final class VirtualLyricWidth {
    static let shared = VirtualLyricWidth()
    static let changed = Notification.Name("PendantVirtualLyricWidthChanged")
    private(set) var extra: CGFloat = 0
    private static let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let maxExtra: CGFloat = 220

    /// The extra width for a line of text: its width plus the middle's padding, beyond the resting middle, in steps of 8 pt.
    static func extra(for text: String?) -> CGFloat {
        guard let text, !text.isEmpty else { return 0 }
        let wanted = (text as NSString).size(withAttributes: [.font: font]).width + 16
        let over = max(wanted - NotchGeometry.virtualContentWidth, 0)
        return min((over / 8).rounded(.up) * 8, maxExtra)
    }

    func set(_ value: CGFloat) {
        guard value != extra else { return }
        extra = value
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

/// The middle part showing the playing song's current lyric line (synchronised lyrics only), the clock while there is none.
/// The lyrics are looked up here (the sources of 設定 › 小工具 › 音樂) while this is the chosen content and a song is playing.
struct VirtualLyricsView: View {
    let model: CapsuleModel
    let settings: AppSettings
    private let lyrics = LyricsStore.shared

    /// What the middle shows for the current moment: a phrase (with an id that changes with it), counting dots, or nothing (the clock).
    private enum Shown: Equatable {
        case text(id: String, text: String)
        case dots(progress: Double)

        var key: String {
            switch self {
            case let .text(id, _): id
            case .dots: "dots"
            }
        }
        var text: String? { if case let .text(_, text) = self { text } else { nil } }
    }

    var body: some View {
        let playing = model.media?.nowPlaying
        ZStack {
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                let shown = current(at: context.date)
                let change = Self.lineTransition(scroll: settings.virtualLyricsScroll)
                ZStack {
                    switch shown {
                    case let .text(id, text):
                        Text(text)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 6)
                            .id(id)
                            .transition(change)
                    case let .dots(progress):
                        LyricDots(progress: progress, size: 5).transition(change)
                    case nil:
                        VirtualClockView(settings: settings).transition(change)
                    }
                }
                .clipped()
                .animation(.easeInOut(duration: settings.virtualLyricsScroll ? 0.38 : 0.3), value: shown?.key)
                .onChange(of: shown?.key, initial: true) { _, _ in VirtualLyricWidth.shared.set(VirtualLyricWidth.extra(for: shown?.text)) }
            }
        }
        .onDisappear { VirtualLyricWidth.shared.set(0) }
        .task(id: "\(playing?.snapshot.trackKey ?? "")|\(settings.lyricsSourcesSignature)") {
            if let snapshot = playing?.snapshot { lyrics.load(for: snapshot) }
        }
    }

    /// Blur in / out, or (the setting) the new line scrolls up from below like a reel while the old one leaves above.
    private static func lineTransition(scroll: Bool) -> AnyTransition {
        guard scroll else { return AnyTransition(.blurReplace) }
        return .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity))
    }

    private func current(at date: Date) -> Shown? {
        guard let playing = model.media?.nowPlaying, playing.isPlaying, case let .synced(lines) = lyrics.state else { return nil }
        let position = lyricPosition(of: playing, at: date)
        guard let index = lines.lastIndex(where: { $0.time <= position + 0.25 }) else { return nil }
        let line = lines[index]
        let end = index + 1 < lines.count ? lines[index + 1].time : line.time + 5
        if line.isInterlude { return .dots(progress: LyricsLineProgress.fraction(position, from: line.time, to: end)) }
        let parts = line.displayParts
        guard parts.count > 1 else { return .text(id: "\(line.id)", text: parts[0]) }
        // Phrases of one line take their turns by length over the line's time (a long gap counts as at most ten seconds).
        let total = Double(parts.reduce(0) { $0 + max($1.count, 1) })
        let elapsed = LyricsLineProgress.fraction(position, from: line.time, to: min(end, line.time + 10)) * total
        var passed = 0.0
        for (number, part) in parts.enumerated() {
            passed += Double(max(part.count, 1))
            if elapsed < passed || number == parts.count - 1 { return .text(id: "\(line.id).\(number)", text: part) }
        }
        return nil
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
                Image(systemName: reading.onCharger ? "battery.100percent.bolt" : BatteryMonitor.symbol(percent: reading.percent))
                    .font(.system(size: size))
                    .foregroundStyle(.white)
            case .ring:
                let low = !reading.onCharger && Double(reading.percent) <= AppSettings.shared.lowBatteryThreshold
                ToastRing(progress: Double(reading.percent) / 100, tint: low ? .red : .green,
                          symbol: reading.onCharger ? "bolt.fill" : nil, lineWidth: 2.6, symbolSize: size * 0.5)
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
