import SwiftUI

/// A `Slider` that gives one haptic tick every time the value crosses a step (settings sliders, like the capsule's own
/// scrubbing controls). Without `step` the range is divided into 40 ticks.
struct HapticSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    /// A fixed track length (a frame around the whole control draws the track shorter than the frame).
    var length: CGFloat?
    /// Words at the two ends of the track (they hug it).
    var ends: (min: String, max: String)?

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil, length: CGFloat? = nil,
         ends: (min: String, max: String)? = nil) {
        self.ends = ends
        _value = value
        self.range = range
        self.step = step
        self.length = length
    }

    /// The slider's tick spacing: the given step, or a multiple of it (2, 5, 10, 25 …) so that there are at most 20 ticks — at one
    /// point per tick they only looked like a solid line.
    private var tickStep: Double? {
        guard let step, step > 0 else { return nil }
        let count = (range.upperBound - range.lowerBound) / step
        let multiple = [1.0, 2, 5, 10, 25, 50, 100, 250, 500].first { count / $0 <= 20 } ?? 1000
        return step * multiple
    }

    private var unit: Double { tickStep ?? max((range.upperBound - range.lowerBound) / 40, .leastNonzeroMagnitude) }

    var body: some View {
        slider
            .focusable()
            // The arrow keys step the slider once it has focus: ← ↓ down, → ↑ up.
            .onKeyPress(.leftArrow) { nudge(-1); return .handled }
            .onKeyPress(.downArrow) { nudge(-1); return .handled }
            .onKeyPress(.rightArrow) { nudge(1); return .handled }
            .onKeyPress(.upArrow) { nudge(1); return .handled }
            .onChange(of: value) { old, new in
                if (old / unit).rounded(.down) != (new / unit).rounded(.down) { HapticService.shared.play(.dragStep) }
            }
    }

    private func nudge(_ direction: Double) {
        value = min(max(value + direction * unit, range.lowerBound), range.upperBound)
    }

    @ViewBuilder private var slider: some View {
        if let ends {
            Slider(value: $value, in: range) { EmptyView() } minimumValueLabel: {
                Text(loc(ends.min)).font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(loc(ends.max)).font(.caption).foregroundStyle(.secondary)
            }
            .labelsHidden()
        } else if let tickStep {
            Slider(value: $value, in: range, step: tickStep).frame(width: length)
        } else {
            Slider(value: $value, in: range).frame(width: length)
        }
    }
}
