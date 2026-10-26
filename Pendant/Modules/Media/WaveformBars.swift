import AppKit
import SwiftUI

// MARK: - Compact capsule pieces

/// Which settings a waveform follows: the small capsule's (设定 › 小工具 › 大膠囊 › 音樂) or the single music capsule's title (獨立膠囊).
enum WaveformStyle { case compact, title }

/// Thin bars (3…7 by setting). By default a calm made-up rise and fall (flat while paused); with 真實音波 on they follow the real sound:
/// each bar is a band of the music's frequencies, low notes on the left, high on the right. With 依專輯顏色 on they are a gradient of the
/// cover's colours, which change smoothly when the track does.
struct WaveformBars: View {
    let isPlaying: Bool
    let isVisible: Bool
    var style = WaveformStyle.compact
    /// The cover's two colours (lighter first), when the controller has them.
    var palette: [Color]?
    @State private var settings = AppSettings.shared
    @State private var focusSettings = FocusCapsuleSettings.shared
    @State private var owner = UUID()
    @State private var fade = ColorFade()

    private static let frequencies = [0.9, 1.2, 1.0, 0.8, 1.1, 1.3, 0.95]
    private static let phases = [0.0, 1.7, 3.1, 0.9, 2.4, 4.0, 5.2]

    /// The numbers this waveform uses (the two styles have separate settings).
    private struct Config {
        var real: Bool, bars: Int, focus: Int, gain: Int, sensitivity: Int, artworkColor: Bool
    }

    private var config: Config {
        switch style {
        case .compact:
            Config(real: settings.realWaveform, bars: settings.waveformBars, focus: settings.waveformFocus, gain: settings.waveformGain,
                   sensitivity: settings.waveformSensitivity, artworkColor: settings.waveformArtworkColor)
        case .title:
            Config(real: focusSettings.waveformReal, bars: focusSettings.waveformBars, focus: focusSettings.waveformFocus,
                   gain: focusSettings.waveformGain, sensitivity: focusSettings.waveformSensitivity,
                   artworkColor: focusSettings.waveformArtworkColor)
        }
    }

    /// The real sound is read only while it can be seen.
    private var wantsSound: Bool { config.real && isPlaying && isVisible }

    private func realLevels(_ config: Config) -> [Double]? {
        guard wantsSound, #available(macOS 14.2, *) else { return nil }
        let focus = SpectrumAnalyzer.Focus(rawValue: config.focus) ?? .full
        return AudioSpectrum.shared.levels(count: config.bars, focus: focus).map(Double.init)
    }

    /// The colours the bars are wanted in: the cover's, or white.
    private var wantedColors: [NSColor] {
        guard config.artworkColor, let palette, palette.count >= 2 else { return ColorFade.white }
        return palette.prefix(2).map { NSColor($0).usingColorSpace(.deviceRGB) ?? .white }
    }

    var body: some View {
        let config = config
        let count = config.bars
        let width: CGFloat = count <= 3 ? 2.5 : (count <= 5 ? 2.3 : 2.0)
        let gap: CGFloat = count <= 3 ? 2.5 : 2.0
        let wanted = wantedColors
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !((isPlaying && isVisible) || fade.isMoving))) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let real = realLevels(config)
            let colors = fade.colors(at: context.date)
            let gradient = LinearGradient(colors: colors.map { Color(nsColor: $0) }, startPoint: .top, endPoint: .bottom)
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(gradient)
                        .opacity(0.92)
                        .frame(width: width, height: height(index, time: time, real: real, config: config))
                        .transaction(value: isPlaying) { $0.animation = .easeInOut(duration: 0.25) }
                        // Heights are drawn every frame: an animation from outside (the capsule's hover morph) must not slide them.
                        // Only the bars' own heights: the whole row still glides with the capsule when it swells.
                        .transaction { $0.animation = nil }
                }
            }
        }
        .frame(height: 14)
        .onChange(of: wanted, initial: true) { _, new in fade.move(to: new) }
        .onChange(of: wantsSound, initial: true) { _, wanted in
            if #available(macOS 14.2, *) { AudioSpectrum.shared.setWanted(wanted, owner: owner) }
        }
        .onDisappear {
            if #available(macOS 14.2, *) { AudioSpectrum.shared.setWanted(false, owner: owner) }
        }
        .accessibilityHidden(true)
    }

    private func height(_ index: Int, time: Double, real: [Double]?, config: Config) -> CGFloat {
        guard isPlaying else { return 2.5 }
        if config.real {
            // Waiting for sound: flat, not a made-up motion that would pretend to be the music.
            let level = real.map { shaped($0[index], config) } ?? 0
            return 2.5 + 11.5 * CGFloat(level)
        }
        let wave = (sin(time * 2 * .pi * Self.frequencies[index] + Self.phases[index]) + 1) / 2
        return 3.5 + 4 * wave
    }

    /// Sensitivity lifts quiet sound (a curve: 200 % shows soft passages, 50 % only the loud ones); gain scales the height.
    private func shaped(_ level: Double, _ config: Config) -> Double {
        let sensitivity = Double(config.sensitivity) / 100
        let gain = Double(config.gain) / 100
        return min(max(pow(level, 1 / sensitivity) * gain, 0), 1)
    }
}

/// The bars' two colours moving from the old pair to the new one (0.8 s, ease in and out), computed per frame by the waveform's timeline.
final class ColorFade {
    static let white = [NSColor(white: 1, alpha: 1), NSColor(white: 1, alpha: 1)]
    private static let duration = 0.8

    private var from = ColorFade.white
    private var to = ColorFade.white
    private var start = Date.distantPast

    var isMoving: Bool { Date().timeIntervalSince(start) < Self.duration }

    func move(to target: [NSColor]) {
        guard target != to else { return }
        from = colors(at: Date())
        to = target
        start = Date()
    }

    func colors(at date: Date) -> [NSColor] {
        let raw = min(max(date.timeIntervalSince(start) / Self.duration, 0), 1)
        let eased = raw * raw * (3 - 2 * raw)
        return zip(from, to).map { Self.mix($0, $1, eased) }
    }

    static func mix(_ first: NSColor, _ second: NSColor, _ amount: Double) -> NSColor {
        let one = first.usingColorSpace(.deviceRGB) ?? first, two = second.usingColorSpace(.deviceRGB) ?? second
        func between(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat { lhs + (rhs - lhs) * amount }
        return NSColor(red: between(one.redComponent, two.redComponent), green: between(one.greenComponent, two.greenComponent),
                       blue: between(one.blueComponent, two.blueComponent), alpha: 1)
    }
}
