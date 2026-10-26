import Foundation
import Observation

/// Settings of the single-tool (獨立) capsule, kept apart from the small capsule's (設定 › 小工具 › 獨立膠囊). The music page's title waveform
/// has its own set, so changing it never touches the small capsule's waveform. Persisted like `AppSettings`, under `settings.focus.`.
@Observable
final class FocusCapsuleSettings: @unchecked Sendable {
    static let shared = FocusCapsuleSettings(defaults: .standard)
    static let prefix = "settings.focus."

    @ObservationIgnored private let defaults: UserDefaults

    var waveformReal: Bool { didSet { save(waveformReal, "waveformReal") } }
    var waveformBars: Int { didSet { save(waveformBars, "waveformBars") } }
    var waveformFocus: Int { didSet { save(waveformFocus, "waveformFocus") } }
    var waveformGain: Int { didSet { save(waveformGain, "waveformGain") } }
    var waveformSensitivity: Int { didSet { save(waveformSensitivity, "waveformSensitivity") } }
    /// The bars take the album cover's colours (a gradient) instead of white.
    var waveformArtworkColor: Bool { didSet { save(waveformArtworkColor, "waveformArtworkColor") } }

    init(defaults: UserDefaults, compact: AppSettings = .shared) {
        self.defaults = defaults
        func has(_ key: String) -> Bool { defaults.object(forKey: Self.prefix + key) != nil }
        func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: Self.prefix + key) as? Int ?? fallback }
        // The first time, the title waveform starts as the small capsule's waveform is set (nothing changes for the user).
        waveformReal = has("waveformReal") ? defaults.bool(forKey: Self.prefix + "waveformReal") : compact.realWaveform
        waveformBars = min(max(int("waveformBars", compact.waveformBars), 3), 7)
        waveformFocus = min(max(int("waveformFocus", compact.waveformFocus), 0), SpectrumAnalyzer.Focus.allCases.count - 1)
        waveformGain = min(max(int("waveformGain", compact.waveformGain), 50), 200)
        waveformSensitivity = min(max(int("waveformSensitivity", compact.waveformSensitivity), 50), 200)
        waveformArtworkColor = has("waveformArtworkColor") ? defaults.bool(forKey: Self.prefix + "waveformArtworkColor") : false
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: Self.prefix + key)
    }
}
