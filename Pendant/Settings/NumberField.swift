import SwiftUI

/// Numeric input: only digits (and `-` / `.` where useful) can be typed, the value is clamped to its range, and the
/// ↑ / ↓ keys step it (one haptic tick per step), like the slider next to it.
struct NumberField: View {
    @Binding var value: Double
    var range: ClosedRange<Double>?
    var step: Double = 1
    var fractionDigits = 0
    var width: CGFloat = 54

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .focused($focused)
            .onAppear { text = Self.format(value, fractionDigits) }
            .onChange(of: text) { _, new in
                let filtered = Self.filter(new, allowNegative: (range?.lowerBound ?? -1) < 0, allowDecimal: fractionDigits > 0)
                if filtered != new { text = filtered }
            }
            .onChange(of: value) { _, new in if !focused { text = Self.format(new, fractionDigits) } }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onSubmit(commit)
            .onKeyPress(.upArrow) { nudge(step); return .handled }
            .onKeyPress(.downArrow) { nudge(-step); return .handled }
    }

    private func commit() {
        if let parsed = Double(text) { value = clamp(parsed) }
        text = Self.format(value, fractionDigits)
    }

    private func nudge(_ delta: Double) {
        let base = Double(text) ?? value
        let next = clamp(base + delta)
        guard next != value else { return }
        value = next
        text = Self.format(next, fractionDigits)
        HapticService.shared.play(.dragStep)
    }

    private func clamp(_ number: Double) -> Double {
        guard let range else { return number }
        return min(max(number, range.lowerBound), range.upperBound)
    }

    /// Keeps digits, one leading `-` (if negatives are allowed) and one `.` (if decimals are allowed).
    static func filter(_ text: String, allowNegative: Bool, allowDecimal: Bool) -> String {
        var result = ""
        var seenDot = false
        for (index, character) in text.enumerated() {
            if character.isASCII, character.isNumber {
                result.append(character)
            } else if character == "-", allowNegative, index == 0 {
                result.append(character)
            } else if character == ".", allowDecimal, !seenDot {
                seenDot = true
                result.append(character)
            }
        }
        return result
    }

    static func format(_ number: Double, _ digits: Int) -> String {
        digits == 0 ? String(Int(number.rounded())) : String(format: "%.\(digits)f", number)
    }
}
