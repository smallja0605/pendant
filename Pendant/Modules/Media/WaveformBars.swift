import SwiftUI

// MARK: - Compact capsule pieces

/// Three thin bars with a calm ~1 Hz rise and fall; flat while paused.
struct WaveformBars: View {
    let isPlaying: Bool
    let isVisible: Bool

    private static let frequencies = [0.9, 1.2, 1.0]
    private static let phases = [0.0, 1.7, 3.1]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !(isPlaying && isVisible))) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = (sin(time * 2 * .pi * Self.frequencies[index] + Self.phases[index]) + 1) / 2
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: 2.5, height: isPlaying ? 3.5 + 4 * wave : 2.5)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isPlaying)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}
