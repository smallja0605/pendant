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

    // MARK: Music page
    /// Lyrics: size (pt), weight (0 regular … 4 heavy), centred or left, the look of the other lines, the scrolling.
    var lyricsFontSize: Int { didSet { save(lyricsFontSize, "lyricsFontSize") } }
    var lyricsFontWeight: Int { didSet { save(lyricsFontWeight, "lyricsFontWeight") } }
    var lyricsCentered: Bool { didSet { save(lyricsCentered, "lyricsCentered") } }
    var lyricsOthersOpacity: Int { didSet { save(lyricsOthersOpacity, "lyricsOthersOpacity") } }
    var lyricsOthersScale: Int { didSet { save(lyricsOthersScale, "lyricsOthersScale") } }
    var lyricsScrollDuration: Double { didSet { save(lyricsScrollDuration, "lyricsScrollDuration") } }
    var lyricsScrollSpring: Bool { didSet { save(lyricsScrollSpring, "lyricsScrollSpring") } }
    /// The word being sung (and the line) take the cover's colour instead of white.
    var lyricsFillArtwork: Bool { didSet { save(lyricsFillArtwork, "lyricsFillArtwork") } }
    var lyricsTapToSeek: Bool { didSet { save(lyricsTapToSeek, "lyricsTapToSeek") } }
    /// The cover's glow (percent of the usual), the player's share of the width (percent), progress times, AirPlay / volume.
    var glowStrength: Int { didSet { save(glowStrength, "glowStrength") } }
    var playerShare: Int { didSet { save(playerShare, "playerShare") } }
    var showProgressTimes: Bool { didSet { save(showProgressTimes, "showProgressTimes") } }
    var showOutputButtons: Bool { didSet { save(showOutputButtons, "showOutputButtons") } }

    // MARK: Reminders page
    /// The list's share of the width (percent), extra height (pt), the handle (0 always, 1 on hover, 2 off), a new item's start.
    var remindersSplit: Int { didSet { save(remindersSplit, "remindersSplit") } }
    var remindersExtraHeight: Int { didSet { save(remindersExtraHeight, "remindersExtraHeight") } }
    var remindersHandle: Int { didSet { save(remindersHandle, "remindersHandle") } }
    var remindersDefaultPriority: Int { didSet { save(remindersDefaultPriority, "remindersDefaultPriority") } }
    var remindersDefaultDue: Int { didSet { save(remindersDefaultDue, "remindersDefaultDue") } }
    var remindersDefaultList: String { didSet { save(remindersDefaultList, "remindersDefaultList") } }

    // MARK: Calendar page
    /// Where today sits on the strip (percent), an event tile's width, the first day of the week (0 = system's, 1 = Sunday … 7).
    var calendarTodayPosition: Int { didSet { save(calendarTodayPosition, "calendarTodayPosition") } }
    var calendarTileWidth: Int { didSet { save(calendarTileWidth, "calendarTileWidth") } }
    var calendarWeekStart: Int { didSet { save(calendarWeekStart, "calendarWeekStart") } }

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
        func bool(_ key: String, _ fallback: Bool) -> Bool { has(key) ? defaults.bool(forKey: Self.prefix + key) : fallback }
        func ranged(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            min(max(int(key, fallback), range.lowerBound), range.upperBound)
        }
        lyricsFontSize = ranged("lyricsFontSize", 17, 12...28)
        lyricsFontWeight = ranged("lyricsFontWeight", 3, 0...4)
        lyricsCentered = bool("lyricsCentered", false)
        lyricsOthersOpacity = ranged("lyricsOthersOpacity", 32, 10...80)
        lyricsOthersScale = ranged("lyricsOthersScale", 96, 80...100)
        let duration = defaults.object(forKey: Self.prefix + "lyricsScrollDuration") as? Double ?? 0.45
        lyricsScrollDuration = min(max(duration, 0.2), 1.2)
        lyricsScrollSpring = bool("lyricsScrollSpring", false)
        lyricsFillArtwork = bool("lyricsFillArtwork", false)
        lyricsTapToSeek = bool("lyricsTapToSeek", true)
        glowStrength = ranged("glowStrength", 100, 0...200)
        playerShare = ranged("playerShare", 56, 30...70)
        showProgressTimes = bool("showProgressTimes", true)
        showOutputButtons = bool("showOutputButtons", true)
        remindersSplit = ranged("remindersSplit", 50, 25...75)
        remindersExtraHeight = ranged("remindersExtraHeight", 0, -60...240)
        remindersHandle = ranged("remindersHandle", 0, 0...2)
        remindersDefaultPriority = ranged("remindersDefaultPriority", 0, 0...3)
        remindersDefaultDue = ranged("remindersDefaultDue", 0, 0...3)
        remindersDefaultList = defaults.string(forKey: Self.prefix + "remindersDefaultList") ?? ""
        calendarTodayPosition = ranged("calendarTodayPosition", 15, 0...50)
        calendarTileWidth = ranged("calendarTileWidth", 210, 140...320)
        calendarWeekStart = ranged("calendarWeekStart", 0, 0...7)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: Self.prefix + key)
    }
}
