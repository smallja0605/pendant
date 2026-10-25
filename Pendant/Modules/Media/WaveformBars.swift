import SwiftUI

// MARK: - Compact capsule pieces

/// Thin bars (3…7 by setting). By default a calm made-up rise and fall (flat while paused); with 真實音波 on they follow the real sound:
/// each bar is a band of the music's frequencies, low notes on the left, high on the right.
struct WaveformBars: View {
    let isPlaying: Bool
    let isVisible: Bool
    @State private var settings = AppSettings.shared
    @State private var owner = UUID()

    private static let frequencies = [0.9, 1.2, 1.0, 0.8, 1.1, 1.3, 0.95]
    private static let phases = [0.0, 1.7, 3.1, 0.9, 2.4, 4.0, 5.2]

    /// The real sound is read only while it can be seen.
    private var wantsSound: Bool { settings.realWaveform && isPlaying && isVisible }

    private func realLevels(_ count: Int) -> [Double]? {
        guard wantsSound, #available(macOS 14.2, *) else { return nil }
        return AudioSpectrum.shared.levels(count: count).map(Double.init)
    }

    var body: some View {
        let count = settings.waveformBars
        let width: CGFloat = count <= 3 ? 2.5 : (count <= 5 ? 2.3 : 2.0)
        let gap: CGFloat = count <= 3 ? 2.5 : 2.0
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !(isPlaying && isVisible))) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let real = realLevels(count)
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: width, height: height(index, time: time, real: real))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isPlaying)
        }
        .frame(height: 14)
        .onChange(of: wantsSound, initial: true) { _, wanted in
            if #available(macOS 14.2, *) { AudioSpectrum.shared.setWanted(wanted, owner: owner) }
        }
        .onDisappear {
            if #available(macOS 14.2, *) { AudioSpectrum.shared.setWanted(false, owner: owner) }
        }
        .accessibilityHidden(true)
    }

    private func height(_ index: Int, time: Double, real: [Double]?) -> CGFloat {
        guard isPlaying else { return 2.5 }
        if settings.realWaveform {
            // Waiting for sound: flat, not a made-up motion that would pretend to be the music.
            let level = real.map { shaped($0[index]) } ?? 0
            return 2.5 + 11.5 * CGFloat(level)
        }
        let wave = (sin(time * 2 * .pi * Self.frequencies[index] + Self.phases[index]) + 1) / 2
        return 3.5 + 4 * wave
    }

    /// Sensitivity lifts quiet sound (a curve: 200 % shows soft passages, 50 % only the loud ones); gain scales the height.
    private func shaped(_ level: Double) -> Double {
        let sensitivity = Double(settings.waveformSensitivity) / 100
        let gain = Double(settings.waveformGain) / 100
        return min(max(pow(level, 1 / sensitivity) * gain, 0), 1)
    }
}
