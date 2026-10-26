import SwiftUI

/// Horizontal date strip with a magnified focus date (reference: 日曆示範.mp4). `position` is the continuous
/// day offset from today; dragging or two-finger horizontal scrolling moves it, one haptic per day, and it
/// springs to the nearest day when the gesture pauses or ends.
struct DayStrip: View {
    let today: Date
    let range: ClosedRange<Int>
    @Binding var position: Double
    /// Where across the strip (0…1) the focus date sits; 0.5 centres it. The strip fills its whole width either way.
    var anchor: CGFloat = 0.5
    /// The detailed page's strip: days far from the focus date stay readable instead of fading out.
    var wide = false

    @State private var dragStart: Double?
    @State private var tracker = StepTracker(unit: 1)
    @State private var settleTask: Task<Void, Never>?
    /// Position where the current scroll gesture started; limits how far one flick can travel.
    @State private var scrollOrigin: Double?
    /// Days scrolled since the gesture began (content direction, before easing).
    @State private var scrollTotal = 0.0
    @State private var hoveredOffset: Int?

    private static let snap = Animation.spring(response: 0.42, dampingFraction: 0.66)
    /// A single flick (with its momentum) can travel at most about this many days.
    static let maxFlickDays = 14.0
    /// How far past either end the strip may be pulled before it springs back.
    static let overscroll = 0.7

    /// Resistance beyond the ends of the range.
    static func rubberBand(_ value: Double, in range: ClosedRange<Int>) -> Double {
        let lower = Double(range.lowerBound), upper = Double(range.upperBound)
        if value > upper { return upper + overscroll * tanh((value - upper) / overscroll) }
        if value < lower { return lower - overscroll * tanh((lower - value) / overscroll) }
        return value
    }

    var body: some View {
        let tuning = Tuning.shared
        GeometryReader { proxy in
            let center = proxy.size.width * anchor
            // Days enough to fill the strip on both sides of the focus date.
            let before = Int(ceil(center / tuning.calItemWidth)) + 2
            let after = Int(ceil((proxy.size.width - center) / tuning.calItemWidth)) + 2
            let lower = max(Int(position.rounded(.down)) - before, range.lowerBound)
            let upper = min(Int(position.rounded(.up)) + after, range.upperBound)
            ZStack {
                if lower <= upper {
                    ForEach(lower...upper, id: \.self) { offset in
                        let distance = Double(offset) - position
                        DayCell(date: CalendarMath.day(offset: offset, from: today), isToday: offset == 0, distance: distance,
                                hovering: hoveredOffset == offset, wide: wide)
                            .onActiveHover { hoveredOffset = $0 != nil ? offset : (hoveredOffset == offset ? nil : hoveredOffset) }
                            .onTapGesture { jump(to: offset) }
                            .position(x: center + Self.xOffset(for: distance, tuning: tuning), y: proxy.size.height / 2)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: anchor < 0.4 ? 0.05 : 0.16),
                            .init(color: .black, location: anchor < 0.4 ? 0.93 : 0.84), .init(color: .clear, location: 1)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { drag in
                        let start = dragStart ?? position
                        dragStart = start
                        move(to: start - drag.translation.width / tuning.calItemWidth)
                    }
                    .onEnded { _ in
                        dragStart = nil
                        settle()
                    }
            )
            .onScrollWheel(wheelUnit: AppSettings.shared.calendarSwipeThreshold, wheelIsHorizontal: true) { deltaX, _ in
                let settings = AppSettings.shared
                guard settings.calendarSwipeEnabled else { return }
                let origin = scrollOrigin ?? position
                scrollOrigin = origin
                scrollTotal -= deltaX / settings.calendarSwipeThreshold
                // Soft saturation instead of a hard stop: a hard flick approaches `maxFlickDays` smoothly, and the
                // strip chases that target with a spring, so it eases in and out (and bounces at the ends).
                let eased = Self.maxFlickDays * tanh(scrollTotal / Self.maxFlickDays)
                move(to: Self.rubberBand(origin + eased, in: range), eased: true)
                scheduleSettle()
            }
        }
        .frame(height: tuning.calStripHeight)
    }

    /// Spacing grows around the focus date so it has room to be large.
    static func xOffset(for distance: Double, tuning: Tuning) -> CGFloat {
        let sign: Double = distance < 0 ? -1 : 1
        let magnitude = abs(distance)
        return CGFloat(sign * (magnitude * tuning.calItemWidth + min(magnitude, 1) * tuning.calFocusGap))
    }

    private func move(to newPosition: Double, eased: Bool = false) {
        settleTask?.cancel()
        let low = Double(range.lowerBound) - Self.overscroll, high = Double(range.upperBound) + Self.overscroll
        let clamped = min(max(newPosition, low), high)
        if eased {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { position = clamped }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { position = clamped }
        }
        let inRange = min(max(clamped, Double(range.lowerBound)), Double(range.upperBound))
        if tracker.crossedBoundary(at: inRange + 0.5) { HapticService.shared.play(.dateChanged) }
    }

    /// Click on a day: the strip glides to it.
    private func jump(to offset: Int) {
        settleTask?.cancel()
        guard Double(offset) != position.rounded() else { return }
        HapticService.shared.play(.dateChanged)
        withAnimation(Self.snap) { position = Double(offset) }
        scrollOrigin = nil
        scrollTotal = 0
    }

    private func settle() {
        let target = min(max(position.rounded(), Double(range.lowerBound)), Double(range.upperBound))
        withAnimation(Self.snap) { position = target }
        tracker.reset()
        scrollOrigin = nil
        scrollTotal = 0
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: .seconds(0.16))
            guard !Task.isCancelled else { return }
            settle()
        }
    }
}

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    let distance: Double
    var hovering = false
    var wide = false

    var body: some View {
        let tuning = Tuning.shared
        let focus = max(0, 1 - abs(distance)) // 1 on the focus date, 0 from one day away
        let size = tuning.calOtherSize + (tuning.calFocusSize - tuning.calOtherSize) * focus
        let weekend = CalendarMath.isWeekend(date)
        let tint: Color = isToday ? Color(red: 0.2, green: 0.55, blue: 1) : (weekend ? Color(red: 1, green: 0.45, blue: 0.4) : .white)
        VStack(spacing: 1) {
            Text(CalendarMath.weekdayLabel(date))
                .font(.system(size: 8.5 + 2 * focus, weight: .semibold))
                .foregroundStyle(tint.opacity(isToday || weekend ? 0.9 : 0.45))
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.system(size: size, weight: focus > 0.5 ? .bold : .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint.opacity(isToday || weekend || focus > 0.5 ? 1 : 0.62))
        }
        .padding(.horizontal, 7).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(max(hovering ? 0.16 : 0, 0.14 * focus))))
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .opacity(wide ? max(0.5, 1 - 0.2 * min(abs(distance), 3)) : max(0.1, 1 - 0.3 * min(abs(distance), 3)))
        .blur(radius: wide ? 0 : max(0, abs(distance) - 2) * 1.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}
