import AppKit
import SwiftUI

/// Timer page: countdown with three scroll wheels and presets, or a stopwatch.
struct TimerView: View {
    let controller: TimerController
    @Environment(\.capsuleExpanded) private var isExpanded
    @Environment(\.moduleAtCapsuleEdge) private var atCapsuleEdge
    @State private var hours = 0
    @State private var minutes = 5
    @State private var seconds = 0
    @State private var settings = AppSettings.shared

    private var mode: TimerEngine.Mode { controller.viewMode }
    private var engine: TimerEngine { controller.engine(for: mode) }

    var body: some View {
        VStack(spacing: 3) {
            modePicker
            Group {
                if mode == .countdown && !engine.hasStarted { wheels } else { readout }
            }
            .frame(maxHeight: .infinity)
            controls
                // The module ends `contentInset` before the capsule edge; reach into that inset so the right
                // margin equals the bottom margin (still smaller than the gap between modules).
                // With a neighbour (and its divider) on the right the buttons stay inside the module.
                .padding(
                    .trailing,
                    atCapsuleEdge ? -(Tuning.shared.contentInset - Tuning.shared.timerEdgeMargin) : Tuning.shared.timerDividerMargin
                )
        }
        .padding(.top, ModuleHeader.topPadding(rowHeight: 31)) // the mode picker sits on the calendar's month-label line
        // Right and bottom margins are the same, and the buttons' corners are concentric with the capsule's.
        .padding(.bottom, Tuning.shared.timerEdgeMargin)
        .onAppear { syncWheels() }
        .onChange(of: engine.duration) { _, _ in syncWheels() }
        .onChange(of: controller.viewMode) { _, _ in syncWheels() }
    }

    // MARK: Pieces

    private var modePicker: some View {
        HStack {
            LiquidTabPicker(
                items: TimerEngine.Mode.allCases.map { tab in
                    // The other timer keeps running in the background: its colour dot says so.
                    .init(id: tab, title: tab == .countdown ? "倒數" : "碼錶",
                          dot: tab != mode && controller.engine(for: tab).isRunning ? TimerStyle.color(for: tab) : nil)
                },
                selection: Binding(
                    get: { controller.viewMode },
                    set: { mode in withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { controller.viewMode = mode } }
                )
            )
            Spacer()
        }
        .frame(height: 31)
    }

    private var wheels: some View {
        HStack(spacing: 2) {
            DigitWheel(value: $hours, range: 0...99, rowHeight: 22, width: 52, fontSize: 20)
            colon
            DigitWheel(value: $minutes, range: 0...59, rowHeight: 22, width: 52, fontSize: 20)
            colon
            DigitWheel(value: $seconds, range: 0...59, rowHeight: 22, width: 52, fontSize: 20)
        }
        .foregroundStyle(.white)
        .onChange(of: hours) { _, _ in commitWheels() }
        .onChange(of: minutes) { _, _ in commitWheels() }
        .onChange(of: seconds) { _, _ in commitWheels() }
    }

    private var colon: some View {
        Text(":").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.4))
    }

    private var tickInterval: Double { mode == .stopwatch ? 0.1 : 0.5 }

    /// Big readout while running / paused / finished, and for the stopwatch.
    private var readout: some View {
        // Ticks only while the capsule is open and the timer runs (no polling otherwise).
        TimelineView(.animation(minimumInterval: tickInterval, paused: !(isExpanded && engine.isRunning))) { context in
            let now = context.date
            VStack(spacing: 8) {
                Text(TimerEngine.format(engine.displayTime(at: now), tenths: mode == .stopwatch))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(mode == .countdown && controller.justFinished ? Color.orange : .white)
                    .contentTransition(.numericText())
                if mode == .countdown {
                    Capsule().fill(.white.opacity(0.18)).frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { proxy in
                                Capsule().fill(.white).frame(width: proxy.size.width * engine.progress(at: now))
                            }
                        }
                        .padding(.horizontal, 14)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if mode == .countdown && !engine.hasStarted {
                // Presets never wrap: the row can be dragged (or swiped) sideways and fades out at the ends.
                DragScrollRow {
                    HStack(spacing: 8) {
                        ForEach(settings.timerPresets, id: \.self) { minutes in
                            Text("\(minutes)m")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(.white.opacity(Int(engine.duration) == minutes * 60 ? 0.28 : 0.1)))
                                .contentShape(Capsule())
                                .onTapGesture { controller.setDuration(Double(minutes * 60)); HapticService.shared.play(.dragStep) }
                                .hapticOnHover()
                                .accessibilityButton("\(minutes) 分鐘")
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(height: 28)
            }
            Spacer(minLength: 0)
            if engine.hasStarted {
                RoundButton(symbol: "arrow.counterclockwise", prominent: false) { controller.reset(mode) }
            }
            if !(mode == .countdown && controller.justFinished) {
                RoundButton(symbol: engine.isRunning ? "pause.fill" : "play.fill", prominent: true) { controller.toggle(mode) }
                    .disabled(mode == .countdown && engine.duration <= 0)
            }
        }
        .frame(height: Tuning.shared.timerButtonSize)
    }

    // MARK: Wheel sync

    private func syncWheels() {
        let parts = TimerEngine.components(of: engine.duration)
        if hours != parts.hours { hours = parts.hours }
        if minutes != parts.minutes { minutes = parts.minutes }
        if seconds != parts.seconds { seconds = parts.seconds }
    }

    private func commitWheels() {
        controller.setDuration(Double(hours * 3600 + minutes * 60 + seconds))
    }
}

private struct RoundButton: View {
    let symbol: String
    let prominent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(prominent ? Color.black : .white)
                .frame(width: Tuning.shared.timerButtonSize, height: Tuning.shared.timerButtonSize)
                .background(
                    RoundedRectangle(cornerRadius: Tuning.shared.timerButtonRadius, style: .continuous)
                        .fill(prominent ? Color.white : Color.white.opacity(0.16))
                )
        }
        .buttonStyle(PressScale())
        .hapticOnHover()
        .accessibilityLabel(SymbolLabel.text(for: symbol))
    }
}

private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Sizes of the timer in the compact capsule (main island): the wing is as wide as the digits plus the usual icon margin
/// on both sides, so the margins left, right, top and bottom match.
enum TimerCompactMetrics {
    /// 12 pt semibold rounded, monospaced digits: the font the compact timer is drawn with.
    private nonisolated(unsafe) static let font: NSFont = {
        let base = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return NSFont(descriptor: descriptor, size: 12) ?? base
    }()

    /// Exact width of the digits as drawn, so the progress line (and the wing) match them to the point.
    static func textWidth(_ text: String) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    /// Text the timer will show at its widest while running.
    @MainActor static func sampleText(_ mode: TimerEngine.Mode = .countdown) -> String {
        let engine = TimerController.shared.engine(for: mode)
        return TimerEngine.format(mode == .countdown ? engine.duration : 0)
    }

    /// Extra width per side on top of the standard compact wing (`notchHeight + wingExtra`).
    @MainActor static func extraWing(standardWing: CGFloat, mode: TimerEngine.Mode = .countdown) -> CGFloat {
        max(0, textWidth(sampleText(mode)) + 2 * Tuning.shared.iconMargin - standardWing)
    }
}

/// Colours and symbols of the two timers: countdown orange, stopwatch blue.
enum TimerStyle {
    static let countdownColor = Color.orange
    static let stopwatchColor = Color(red: 0.2, green: 0.55, blue: 1)

    static func color(for mode: TimerEngine.Mode) -> Color { mode == .countdown ? countdownColor : stopwatchColor }
    static func symbol(for mode: TimerEngine.Mode) -> String { mode == .countdown ? "timer" : "stopwatch" }
}

/// Ring that empties as the countdown runs out (compact capsule); refreshed once a second.
struct TimerProgressRing: View {
    var lineWidth: CGFloat = 2

    var body: some View {
        let controller = TimerController.shared
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = 1 - controller.engine.progress(at: context.date)
            ZStack {
                Circle().stroke(.white.opacity(0.22), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(remaining, 0.001))
                    .stroke(TimerStyle.countdownColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
            }
        }
        .accessibilityHidden(true)
    }
}
