import SwiftUI

/// Two-finger swipe left on a row, in three stages (like Mail): (1) swiping — let go before the haptic and it springs
/// back; (2) past the first haptic the delete pill stays open, even after the fingers leave the trackpad; (3) past the
/// second haptic the pill fills the whole row and letting go deletes. The row's text stays visible (it is squeezed,
/// not covered) until the pill fills the row.
struct SwipeToDelete<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 240
    @State private var height: CGFloat = 30
    @State private var swiping = false
    @State private var decided = false
    @State private var armed = false
    @State private var fullArmed = false
    @State private var collapsed = false
    @State private var settleTask: Task<Void, Never>?
    @State private var hovering = false

    private let arm: CGFloat = 34
    private let openWidth: CGFloat = 52
    private var full: CGFloat { max(width * 0.6, 110) }

    var body: some View {
        let amount = -offset
        let pillWidth = amount > 0 ? min(max(amount - 6, 0), width - 4) : 0
        ZStack(alignment: .trailing) {
            // The whole row (with its highlight) slides left, its left part falls out of view, while the text inside
            // is pushed back right by the same amount, so the text stays where it was until the pill covers it.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(hovering || amount > 0 ? 0.1 : 0))
                content
                    .padding(.horizontal, 6)
                    .offset(x: amount)
                    .opacity(amount > width * 0.82 ? 0 : 1)
            }
            // Flexible, not `width`: a fixed frame of the measured width could never get narrower than its first value (the
            // measurement saw the frame itself), and the list overflowed the module on both sides.
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: -amount)
            Button {
                HapticService.shared.play(.stateSettled)
                remove()
            } label: {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.red)
                    // Always centred in the pill until stage 3 (full swipe), where it moves to the pill's left end.
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14)
                        .offset(x: (amount >= full ? 26 : pillWidth / 2) - 7)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: amount >= full)
                        .opacity(pillWidth > 18 ? 1 : 0)
                }
                .frame(width: pillWidth, height: 28)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
            .opacity(amount > 2 ? 1 : 0)
            .allowsHitTesting(amount > arm)
            .accessibilityLabel("刪除")
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width; if !collapsed { height = proxy.size.height } }
                .onChange(of: proxy.size) { _, size in width = size.width; if !collapsed { height = size.height } }
        })
        .animation(.easeOut(duration: 0.12), value: hovering)
        .clipped()
        .onActiveHover { hovering = $0 != nil }
        .frame(height: collapsed ? 0 : nil)
        .opacity(collapsed ? 0 : 1)
        .clipped()
        .onScrollWheelPhased { deltaX, deltaY, phase in handle(deltaX, deltaY, phase) }
    }

    private func handle(_ deltaX: Double, _ deltaY: Double, _ phase: ScrollPhase) -> Bool {
        if phase.momentum { return swiping } // inertia after the fingers left: swallow it, nothing more to do
        // A gesture is claimed by its first moving event, by direction; vertical gestures stay with the list.
        if phase.began || !phase.hasPhase { decided = false }
        if !decided, deltaX != 0 || deltaY != 0 {
            swiping = abs(deltaX) > abs(deltaY)
            decided = true
        }
        if phase.ended { decided = false }
        guard swiping else { return false }
        settleTask?.cancel()
        let next = min(max(offset + deltaX, -width), 0)
        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.9)) { offset = next }
        updateHaptics()
        if phase.ended {
            finish()
        } else if !phase.hasPhase {
            settleTask = Task { // a mouse wheel has no "fingers lifted": a short pause counts as letting go
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                finish()
            }
        }
        return true
    }

    private func updateHaptics() {
        let amount = -offset
        if (amount >= arm) != armed {
            armed = amount >= arm
            if armed { HapticService.shared.play(.stateSettled) }
        }
        if (amount >= full) != fullArmed {
            fullArmed = amount >= full
            if fullArmed { HapticService.shared.play(.stateSettled) }
        }
    }

    private func finish() {
        swiping = false
        let amount = -offset
        if amount >= full {
            remove()
        } else {
            let target: CGFloat = amount >= arm ? -openWidth : 0
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { offset = target }
            armed = target != 0
            fullArmed = false
        }
    }

    private func remove() {
        swiping = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = -width }
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.easeIn(duration: 0.22)) { collapsed = true }
            try? await Task.sleep(for: .milliseconds(230))
            onDelete()
        }
    }
}
