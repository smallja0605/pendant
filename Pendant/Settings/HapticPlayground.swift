#if DEBUG
import SwiftUI

/// Debug-only playground: real controls wired to the same haptic events the modules will use,
/// so each pattern is felt in context (hover, drag a slider, scrub days, scrub a timer digit).
struct HapticPlayground: View {
    var body: some View {
        Section {
            Text("游標掃過瀏海是第一階段，在瀏海上停留(或點擊)展開是第二階段，可直接在螢幕上緣體驗。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HoverButtonsRow()
            StepSliderRow()
            DayStripRow()
            TimerDigitRow()
            FinishRow()
        } header: {
            Text("觸覺試玩(除錯)")
        }
    }
}

private struct HoverButtonsRow: View {
    var body: some View {
        LabeledContent("Hover 可操作項目") {
            HStack {
                ForEach(["backward.fill", "play.fill", "forward.fill"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .frame(width: 34, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                        .hapticOnHover()
                }
            }
        }
    }
}

private struct StepSliderRow: View {
    @State private var value = 40.0
    @State private var tracker = StepTracker(unit: 1)

    var body: some View {
        LabeledContent("進度條/音量(每 1%)") {
            HStack {
                Slider(value: $value, in: 0...100, step: 1) { editing in
                    if editing { tracker.reset() }
                }
                .frame(width: 160)
                Text("\(Int(value))%").monospacedDigit().frame(width: 40, alignment: .trailing)
            }
        }
        .onChange(of: value) { _, newValue in
            if tracker.crossedBoundary(at: newValue) { HapticService.shared.play(.dragStep) }
        }
    }
}

private struct DayStripRow: View {
    private static let days = ["一", "二", "三", "四", "五", "六", "日"]
    private let cell: CGFloat = 36
    @State private var selected = 2
    @State private var scrollRemainder = 0.0
    @State private var tracker = StepTracker(unit: 1)

    var body: some View {
        LabeledContent("日曆切換日期") {
            HStack(spacing: 0) {
                ForEach(Self.days.indices, id: \.self) { index in
                    Text(Self.days[index])
                        .frame(width: cell, height: 28)
                        .background(RoundedRectangle(cornerRadius: 6).fill(index == selected ? Color.accentColor : .clear))
                        .foregroundStyle(index == selected ? .white : .primary)
                        .textSelection(.disabled)
                }
            }
            .contentShape(Rectangle())
            .onScrollWheel { deltaX, _ in
                // Two-finger horizontal swipe: one day per `cell` points, one haptic per day.
                scrollRemainder += deltaX
                let days = Int(scrollRemainder / cell)
                guard days != 0 else { return }
                scrollRemainder -= Double(days) * cell
                let next = min(max(selected - days, 0), Self.days.count - 1)
                if next != selected {
                    selected = next
                    HapticService.shared.play(.dateChanged)
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let position = min(max(drag.location.x / Double(cell), 0), Double(Self.days.count) - 0.001)
                        selected = Int(position)
                        if tracker.crossedBoundary(at: position) { HapticService.shared.play(.dateChanged) }
                    }
                    .onEnded { _ in tracker.reset() }
            )
        }
    }
}

private struct TimerDigitRow: View {
    @State private var minutes = 5

    var body: some View {
        LabeledContent("計時器數字(拖曳或雙指上下滑)") {
            DigitWheel(value: $minutes)
        }
    }
}

private struct FinishRow: View {
    var body: some View {
        LabeledContent("計時結束(兩次)") {
            Button("1 秒後觸發") {
                // Wait for the click itself to finish, or its own trackpad feedback masks the test.
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    HapticService.shared.play(.timerFinished)
                }
            }
        }
    }
}
#endif
