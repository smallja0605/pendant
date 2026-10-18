import SwiftUI

/// A number "wheel": the previous / next values are visible above and below and really scroll
/// (and fade / blur by distance) while you drag or two-finger scroll vertically, then spring-snap to
/// the nearest value. One `.dateChanged` haptic (same as the calendar strip) per unit crossed.
struct DigitWheel: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...99
    var rowHeight: CGFloat = 30
    var width: CGFloat = 64
    var fontSize: CGFloat = 24
    var haptic: HapticEvent = .dateChanged

    /// Continuous position in units (== `value` when at rest).
    @State private var position: Double = 0
    @State private var dragStart: Double?
    @State private var tracker = StepTracker(unit: 1)
    @State private var settleTask: Task<Void, Never>?

    private static let snap = Animation.spring(response: 0.32, dampingFraction: 0.7)

    var body: some View {
        let center = Int(position.rounded())
        ZStack {
            ForEach(max(center - 2, range.lowerBound)...min(center + 2, range.upperBound), id: \.self) { number in
                let distance = Double(number) - position
                Text(String(format: "%02d", number))
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .scaleEffect(1 - min(abs(distance), 2) * 0.14)
                    .opacity(max(0, 1 - abs(distance) * 0.55))
                    .blur(radius: min(abs(distance), 2) * 1.2)
                    .offset(y: distance * rowHeight)
            }
        }
        .frame(width: width, height: rowHeight * 3)
        .clipped()
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.28),
                        .init(color: .black, location: 0.72), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .textSelection(.disabled)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let start = dragStart ?? position
                    dragStart = start
                    // Dragging the content down shows smaller numbers.
                    move(to: start - drag.translation.height / rowHeight, animated: false)
                }
                .onEnded { _ in
                    dragStart = nil
                    settle()
                }
        )
        .onScrollWheel { _, deltaY in
            move(to: position - deltaY / rowHeight, animated: false)
            scheduleSettle()
        }
        .onAppear { position = Double(value) }
        .onChange(of: value) { _, newValue in
            // External change (e.g. a preset): glide there.
            if Int(position.rounded()) != newValue, dragStart == nil { withAnimation(Self.snap) { position = Double(newValue) } }
        }
        .accessibilityElement()
        .accessibilityValue(String(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(by: 1)
            case .decrement: step(by: -1)
            @unknown default: break
            }
        }
    }

    private func move(to newPosition: Double, animated: Bool) {
        settleTask?.cancel()
        let clamped = min(max(newPosition, Double(range.lowerBound)), Double(range.upperBound))
        if animated {
            withAnimation(Self.snap) { position = clamped }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { position = clamped }
        }
        let rounded = Int(clamped.rounded())
        if rounded != value { value = rounded }
        if tracker.crossedBoundary(at: clamped + 0.5) { HapticService.shared.play(haptic) }
    }

    private func settle() {
        withAnimation(Self.snap) { position = position.rounded() }
        tracker.reset()
    }

    /// Scroll events have no explicit end we can rely on (momentum, mouse wheels), so settle after a pause.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: .seconds(0.14))
            guard !Task.isCancelled else { return }
            settle()
        }
    }

    private func step(by delta: Int) {
        move(to: position.rounded() + Double(delta), animated: true)
        tracker.reset()
    }
}
