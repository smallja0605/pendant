import SwiftUI

/// Height of a row's first line: the title and the control are centred on it, so with a tip under the title the control stays in
/// the title's line instead of the middle of the whole row.
private let rowLine: CGFloat = 24

private struct SliderLengthKey: EnvironmentKey { static let defaultValue: CGFloat = 240 }

extension EnvironmentValues {
    /// Length of every settings slider in a view (narrow panes set a shorter one, but all sliders in them match).
    var sliderLength: CGFloat {
        get { self[SliderLengthKey.self] }
        set { self[SliderLengthKey.self] = newValue }
    }
}

/// A row label with an optional tip under the title (5 pt apart).
struct TipLabel: View {
    let title: String
    var tip: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(loc(title)).lineLimit(1).minimumScaleFactor(0.75).frame(minHeight: rowLine, alignment: .leading)
            if let tip { Text(loc(tip)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Slider + number field + unit, the shape every numeric setting takes. All sliders have the same length.
struct SliderRow: View {
    let title: String
    var tip: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit = ""
    var fractionDigits = 0
    /// Something after the unit (a reset button).
    var accessory: AnyView?
    @Environment(\.sliderLength) private var sliderLength

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TipLabel(title: title, tip: tip)
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                HapticSlider(value: $value, in: range, step: step, length: sliderLength)
                NumberField(value: $value, range: range, step: step, fractionDigits: fractionDigits)
                Text(loc(unit)).foregroundStyle(.secondary).fixedSize().frame(minWidth: 22, alignment: .leading)
                if let accessory { accessory.fixedSize() }
            }
            .frame(minHeight: rowLine)
        }
    }
}

/// A switch or menu row with an optional tip.
struct TipRow<Control: View>: View {
    let title: String
    var tip: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TipLabel(title: title, tip: tip)
            Spacer(minLength: 12)
            control.toggleStyle(.switch).frame(minHeight: rowLine)
        }
    }
}

/// A row that folds rows away; the whole row (title included) is the button.
struct DisclosureRow: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(loc(title))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// A disabled row: it cannot be used and is clearly faded and greyed, so nobody has to guess.
    func dimmed(when disabled: Bool) -> some View {
        self.disabled(disabled)
            .opacity(disabled ? 0.3 : 1)
            .saturation(disabled ? 0 : 1)
            .animation(.easeOut(duration: 0.2), value: disabled)
    }
}
