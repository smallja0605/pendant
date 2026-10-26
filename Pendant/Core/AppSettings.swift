import Foundation
import Observation

/// User-facing settings (requirements 7.x). Every property is persisted in UserDefaults immediately and
/// read back at launch. Views and controllers observe this single object.
@Observable
// swiftlint:disable:next type_body_length
final class AppSettings: @unchecked Sendable {
    static let shared = AppSettings(defaults: .standard)
    static let prefix = "settings."

    @ObservationIgnored private let defaults: UserDefaults

    // MARK: General (7.1)
    var screenChoice: ScreenChoice { didSet { save(screenChoice.rawValue, "screenChoice") } }
    var hoverExpandMode: HoverExpandMode { didSet { save(hoverExpandMode.rawValue, "hoverExpandMode") } }
    var hoverDelay: Double { didSet { save(hoverDelay, "hoverDelay") } }
    // MARK: Virtual notch (screens without a physical notch)
    var virtualNotchEnabled: Bool { didSet { save(virtualNotchEnabled, "virtualNotchEnabled") } }
    /// Hide the virtual notch while an app is full screen (its own Space, the green button) on its screen.
    var virtualHideInFullscreen: Bool { didSet { save(virtualHideInFullscreen, "virtualHideInFullscreen") } }
    /// 懸浮膠囊態: the virtual notch floats below the top edge as a rounded capsule (gap in points) instead of hanging from it.
    var virtualFloating: Bool { didSet { save(virtualFloating, "virtualFloating") } }
    var virtualFloatGap: Double { didSet { save(virtualFloatGap, "virtualFloatGap") } }
    var virtualIdleHide: VirtualIdleHide { didSet { save(virtualIdleHide.rawValue, "virtualIdleHide") } }
    var virtualIdleHover: Bool { didSet { save(virtualIdleHover, "virtualIdleHover") } }
    var virtualMiddle: VirtualMiddle { didSet { save(virtualMiddle.rawValue, "virtualMiddle") } }
    var virtualClock24h: Bool { didSet { save(virtualClock24h, "virtualClock24h") } }
    var virtualClockSeconds: Bool { didSet { save(virtualClockSeconds, "virtualClockSeconds") } }
    var virtualClockDate: Bool { didSet { save(virtualClockDate, "virtualClockDate") } }
    var virtualBatteryStyle: VirtualBatteryStyle { didSet { save(virtualBatteryStyle.rawValue, "virtualBatteryStyle") } }
    var virtualDateFormat: VirtualDateFormat { didSet { save(virtualDateFormat.rawValue, "virtualDateFormat") } }
    var virtualBigStrip: Bool { didSet { save(virtualBigStrip, "virtualBigStrip") } }
    var virtualBigBattery: Bool { didSet { save(virtualBigBattery, "virtualBigBattery") } }
    var virtualBigDate: Bool { didSet { save(virtualBigDate, "virtualBigDate") } }
    var virtualBigTime: Bool { didSet { save(virtualBigTime, "virtualBigTime") } }
    var virtualLeft: VirtualSide { didSet { save(virtualLeft.rawValue, "virtualLeft") } }
    var virtualBatteryPercent: Bool { didSet { save(virtualBatteryPercent, "virtualBatteryPercent") } }
    var virtualRight: VirtualSide { didSet { save(virtualRight.rawValue, "virtualRight") } }
    /// A module's detailed page closes when the pointer leaves the capsule (off: it stays until it is closed or clicked away).
    var focusCollapsesOnLeave: Bool { didSet { save(focusCollapsesOnLeave, "focusCollapsesOnLeave") } }
    var collapseDelay: Double { didSet { save(collapseDelay, "collapseDelay") } }
    var hotkeyEnabled: Bool { didSet { save(hotkeyEnabled, "hotkeyEnabled") } }
    var hotkeyKeyCode: Int { didSet { save(hotkeyKeyCode, "hotkeyKeyCode") } }
    var hotkeyModifiers: Int { didSet { save(hotkeyModifiers, "hotkeyModifiers") } }
    var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, "showMenuBarIcon") } }
    var languageOverride: String { didSet { save(languageOverride, "languageOverride") } }

    // MARK: Capsule and notch (7.3)
    var hoverEffectEnabled: Bool { didSet { save(hoverEffectEnabled, "hoverEffectEnabled") } }
    var notchWidthAdjust: Double { didSet { save(notchWidthAdjust, "notchWidthAdjust") } }

    // MARK: Liquid (7.5, macOS 26+)
    /// Try the system's own segmented control (timer 倒數 / 碼錶) instead of the hand-built glass lens (macOS 26+).
    /// HUD in the notch when the volume / brightness changes.
    var hudVolume: Bool { didSet { save(hudVolume, "hudVolume") } }
    var hudBrightness: Bool { didSet { save(hudBrightness, "hudBrightness") } }
    /// Stop macOS's own volume / brightness pop-up while the notch HUD is on.
    var hudHideSystem: Bool { didSet { save(hudHideSystem, "hudHideSystem") } }
    var hudSeconds: Double { didSet { save(hudSeconds, "hudSeconds") } }
    // MARK: System features (charging, low battery, Bluetooth)
    var chargingToast: Bool { didSet { save(chargingToast, "chargingToast") } }
    var chargingToastSeconds: Double { didSet { save(chargingToastSeconds, "chargingToastSeconds") } }
    var lowBatteryToast: Bool { didSet { save(lowBatteryToast, "lowBatteryToast") } }
    var lowBatteryThreshold: Double { didSet { save(lowBatteryThreshold, "lowBatteryThreshold") } }
    var lowBatteryDismissOnActivity: Bool { didSet { save(lowBatteryDismissOnActivity, "lowBatteryDismissOnActivity") } }
    var lowBatteryActivityDelay: Double { didSet { save(lowBatteryActivityDelay, "lowBatteryActivityDelay") } }
    var bluetoothToast: Bool { didSet { save(bluetoothToast, "bluetoothToast") } }
    var bluetoothToastSeconds: Double { didSet { save(bluetoothToastSeconds, "bluetoothToastSeconds") } }
    var tourSeen: Bool { didSet { save(tourSeen, "tourSeen") } }
    /// Status strip (open capsule, top right).
    var statusBattery: Bool { didSet { save(statusBattery, "statusBattery") } }
    var statusBatteryPercent: Bool { didSet { save(statusBatteryPercent, "statusBatteryPercent") } }
    var statusUpdateTag: Bool { didSet { save(statusUpdateTag, "statusUpdateTag") } }
    var shelfAirDropPercent: Double { didSet { save(shelfAirDropPercent, "shelfAirDropPercent") } }
    /// Under the compact capsule (shelf): the newest file as "name · size", with its icon in front.
    var shelfPeekWithIcon: Bool { didSet { save(shelfPeekWithIcon, "shelfPeekWithIcon") } }
    /// Show the newest file under the shelf's small capsule while the pointer is on it.
    var shelfPeekEnabled: Bool { didSet { save(shelfPeekEnabled, "shelfPeekEnabled") } }
    var shelfShowsCount: Bool { didSet { save(shelfShowsCount, "shelfShowsCount") } }
    var nativeSegmented: Bool { didSet { save(nativeSegmented, "nativeSegmented") } }
    var liquidGlassEnabled: Bool { didSet { save(liquidGlassEnabled, "liquidGlassEnabled") } }

    // MARK: Gestures (7.6)
    var swipeTracksEnabled: Bool { didSet { save(swipeTracksEnabled, "swipeTracksEnabled") } }
    var swipeThreshold: Double { didSet { save(swipeThreshold, "swipeThreshold") } }
    var swipeReversed: Bool { didSet { save(swipeReversed, "swipeReversed") } }
    var calendarSwipeEnabled: Bool { didSet { save(calendarSwipeEnabled, "calendarSwipeEnabled") } }
    var calendarSwipeThreshold: Double { didSet { save(calendarSwipeThreshold, "calendarSwipeThreshold") } }

    // MARK: Live activities (7.7)
    var activityPriority: [String] { didSet { save(activityPriority, "activityPriority") } }
    var disabledActivities: [String] { didSet { save(disabledActivities, "disabledActivities") } }
    var mainOnlyActivities: [String] { didSet { save(mainOnlyActivities, "mainOnlyActivities") } }
    var secondaryOnlyActivities: [String] { didSet { save(secondaryOnlyActivities, "secondaryOnlyActivities") } }
    /// Song / artist line under the compact capsule whenever the track changes.
    var showTrackInfoOnChange: Bool { didSet { save(showTrackInfoOnChange, "showTrackInfoOnChange") } }
    var trackInfoSeconds: Double { didSet { save(trackInfoSeconds, "trackInfoSeconds") } }
    var showCoverInCompact: Bool { didSet { save(showCoverInCompact, "showCoverInCompact") } }
    var showWaveformInCompact: Bool { didSet { save(showWaveformInCompact, "showWaveformInCompact") } }
    /// The compact capsule's bars follow the real sound (system audio tap + FFT) instead of a calm made-up motion.
    var realWaveform: Bool { didSet { save(realWaveform, "realWaveform") } }
    /// Number of bars in the waveform, 3…7.
    var waveformBars: Int { didSet { save(waveformBars, "waveformBars") } }
    /// Real waveform, in percent: how tall the bars grow, and how easily quiet sound shows.
    /// 平衡器: which part of the sound the real waveform spreads over (`SpectrumAnalyzer.Focus` raw value).
    var waveformFocus: Int { didSet { save(waveformFocus, "waveformFocus") } }
    var waveformGain: Int { didSet { save(waveformGain, "waveformGain") } }
    var waveformSensitivity: Int { didSet { save(waveformSensitivity, "waveformSensitivity") } }

    // MARK: Split islands (3.5)
    var islandLeftEnabled: Bool { didSet { save(islandLeftEnabled, "islandLeftEnabled") } }
    var islandRightEnabled: Bool { didSet { save(islandRightEnabled, "islandRightEnabled") } }
    var islandPrioritySide: IslandSide { didSet { save(islandPrioritySide.rawValue, "islandPrioritySide") } }
    var islandGap: Double { didSet { save(islandGap, "islandGap") } }
    /// Percent of the screen width the whole island row may span.
    var islandMaxSpanPercent: Double { didSet { save(islandMaxSpanPercent, "islandMaxSpanPercent") } }
    var islandLeftOffset: Double { didSet { save(islandLeftOffset, "islandLeftOffset") } }
    var islandRightOffset: Double { didSet { save(islandRightOffset, "islandRightOffset") } }
    var islandMaxWidth: Double { didSet { save(islandMaxWidth, "islandMaxWidth") } }
    var islandDisplayMode: IslandDisplayMode { didSet { save(islandDisplayMode.rawValue, "islandDisplayMode") } }
    /// 3.5.8 ②: fade the secondary islands while a menu is open under them.
    var islandHideDuringMenus: Bool { didSet { save(islandHideDuringMenus, "islandHideDuringMenus") } }
    /// 3.5.8 ④: hang below the menu bar instead of covering it.
    var islandSinking: Bool { didSet { save(islandSinking, "islandSinking") } }
    /// 3.5.8 ⑥ (experimental, needs Accessibility): keep islands off the frontmost app's menu items.
    var islandSmartAvoid: Bool { didSet { save(islandSmartAvoid, "islandSmartAvoid") } }
    /// Seconds a paused player still counts as a live activity (0 = not at all).
    var mediaPauseRetention: Double { didSet { save(mediaPauseRetention, "mediaPauseRetention") } }

    // MARK: Media (4.1)
    var mediaSourcePreference: MediaSourcePreference { didSet { save(mediaSourcePreference.rawValue, "mediaSourcePreference") } }
    var artworkGlow: Bool { didSet { save(artworkGlow, "artworkGlow") } }
    /// Streamed Apple Music tracks have no artwork through AppleScript: look the cover up (title + artist only).
    /// Keep every shown cover on disk (swaps instantly when a track comes back).
    var artworkCache: Bool { didSet { save(artworkCache, "artworkCache") } }
    var onlineArtwork: Bool { didSet { save(onlineArtwork, "onlineArtwork") } }
    var onlineLyrics: Bool { didSet { save(onlineLyrics, "onlineLyrics") } }
    /// Where the detailed music page takes lyrics from, in the order they are asked (disabled ones are skipped).
    var lyricsSources: [LyricsSourceItem] {
        didSet { if let data = try? JSONEncoder().encode(lyricsSources) { save(data, "lyricsSources") } }
    }
    var lyricsTraditional: Bool { didSet { save(lyricsTraditional, "lyricsTraditional") } } // see `LyricsFormatter`
    var lyricsFillerDots: Bool { didSet { save(lyricsFillerDots, "lyricsFillerDots") } }
    var lyricsSplitLines: Bool { didSet { save(lyricsSplitLines, "lyricsSplitLines") } }
    var lyricsHideRomanization: Bool { didSet { save(lyricsHideRomanization, "lyricsHideRomanization") } }
    var lyricsOffset: Double { didSet { save(lyricsOffset, "lyricsOffset") } } // seconds; + = lines appear sooner
    var virtualLyricsScroll: Bool { didSet { save(virtualLyricsScroll, "virtualLyricsScroll") } } // new line scrolls up
    var showWaveformInTitle: Bool { didSet { save(showWaveformInTitle, "showWaveformInTitle") } }

    // MARK: Timer (4.4)
    var timerPresets: [Int] { didSet { save(timerPresets, "timerPresets") } }
    var timerRing: Bool { didSet { save(timerRing, "timerRing") } }
    var timerSound: Bool { didSet { save(timerSound, "timerSound") } }
    var timerNotification: Bool { didSet { save(timerNotification, "timerNotification") } }
    var timerLastDuration: Double { didSet { save(timerLastDuration, "timerLastDuration") } }

    // MARK: Reminders (4.3)
    var remindersHiddenListIDs: [String] { didSet { save(remindersHiddenListIDs, "remindersHiddenListIDs") } }
    var remindersShowCompleted: Bool { didSet { save(remindersShowCompleted, "remindersShowCompleted") } }
    var remindersSort: ReminderSort { didSet { save(remindersSort.rawValue, "remindersSort") } }
    var remindersLimit: Int { didSet { save(remindersLimit, "remindersLimit") } }

    // MARK: Calendar (4.5)
    /// Calendars the user unchecked (by `calendarIdentifier`); new / unknown calendars are visible by default.
    var calendarHiddenIDs: [String] { didSet { save(calendarHiddenIDs, "calendarHiddenIDs") } }
    var calendarShowPast: Bool { didSet { save(calendarShowPast, "calendarShowPast") } }
    var calendarShowAllDay: Bool { didSet { save(calendarShowAllDay, "calendarShowAllDay") } }
    var calendarShowMultiDay: Bool { didSet { save(calendarShowMultiDay, "calendarShowMultiDay") } }
    /// The strip covers today's whole month (default); otherwise days behind / ahead apply.
    var calendarWholeMonth: Bool { didSet { save(calendarWholeMonth, "calendarWholeMonth") } }
    var calendarDaysBehind: Int { didSet { save(calendarDaysBehind, "calendarDaysBehind") } }
    var calendarDaysAhead: Int { didSet { save(calendarDaysAhead, "calendarDaysAhead") } }

    // MARK: Updates (8.1)
    var autoCheckUpdates: Bool { didSet { save(autoCheckUpdates, "autoCheckUpdates") } }
    /// Download and install a new version by itself (otherwise the user is only told).
    var autoInstallUpdates: Bool { didSet { save(autoInstallUpdates, "autoInstallUpdates") } }
    /// `UpdateRules.Channel` raw value: "stable" or "preview" (includes pre-releases).
    var updateChannel: String { didSet { save(updateChannel, "updateChannel") } }

    // MARK: Notes (4.2)
    var notesFontSize: Double { didSet { save(notesFontSize, "notesFontSize") } }
    var notesOpenLast: Bool { didSet { save(notesOpenLast, "notesOpenLast") } }
    /// Empty = the default folder inside Application Support.
    var notesCustomPath: String { didSet { save(notesCustomPath, "notesCustomPath") } }
    var notesLastID: String { didSet { save(notesLastID, "notesLastID") } }

    // MARK: Shortcuts (4.7) and Mirror (4.8)
    var shortcutsHidden: [String] { didSet { save(shortcutsHidden, "shortcutsHidden") } }
    var shortcutsGrid: Bool { didSet { save(shortcutsGrid, "shortcutsGrid") } }
    var mirrorFlip: Bool { didSet { save(mirrorFlip, "mirrorFlip") } }
    var mirrorCameraID: String { didSet { save(mirrorCameraID, "mirrorCameraID") } }

    // MARK: Shelf and drop zone (4.6, active from M7)
    var shelfAutoClear: ShelfAutoClear { didSet { save(shelfAutoClear.rawValue, "shelfAutoClear") } }
    var shelfAutoClearDays: Int { didSet { save(shelfAutoClearDays, "shelfAutoClearDays") } }
    var dragOpensShelf: Bool { didSet { save(dragOpensShelf, "dragOpensShelf") } }
    var dragProximity: Double { didSet { save(dragProximity, "dragProximity") } }
    /// A file dragged over from another screen does not open the shelf (moving a file between screens is not a trip to the shelf).
    var dragIgnoresOtherScreens: Bool { didSet { save(dragIgnoresOtherScreens, "dragIgnoresOtherScreens") } }

    /// Default activity order (requirements 3.5.2): media > timer > reminders > shelf.
    static let defaultActivityPriority = ["media", "timer", "stopwatch", "reminders", "shelf"]
    /// Orders that were the default before 3.5 (kept only if the user never changed them): replaced by the new default.
    private static let legacyActivityPriorities = [
        ["timer", "media", "reminders"], ["timer", "media", "reminders", "shelf"], ["media", "timer", "reminders", "shelf"],
    ]

    // swiftlint:disable:next function_body_length
    init(defaults: UserDefaults) {
        self.defaults = defaults
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: Self.prefix + key) as? Bool ?? fallback }
        func double(_ key: String, _ fallback: Double) -> Double { defaults.object(forKey: Self.prefix + key) as? Double ?? fallback }
        func int(_ key: String, _ fallback: Int) -> Int { defaults.object(forKey: Self.prefix + key) as? Int ?? fallback }
        func string(_ key: String) -> String? { defaults.string(forKey: Self.prefix + key) }

        screenChoice = string("screenChoice").flatMap(ScreenChoice.init(rawValue:)) ?? .main
        hoverExpandMode = string("hoverExpandMode").flatMap(HoverExpandMode.init(rawValue:)) ?? .off
        hoverDelay = double("hoverDelay", 0.3)
        virtualNotchEnabled = bool("virtualNotchEnabled", true)
        virtualHideInFullscreen = bool("virtualHideInFullscreen", true)
        virtualFloating = bool("virtualFloating", false)
        virtualFloatGap = min(max(double("virtualFloatGap", 6), 2), 24)
        virtualIdleHide = string("virtualIdleHide").flatMap(VirtualIdleHide.init(rawValue:)) ?? .off
        virtualIdleHover = bool("virtualIdleHover", true)
        virtualMiddle = string("virtualMiddle").flatMap(VirtualMiddle.init(rawValue:)) ?? .clock
        virtualClock24h = bool("virtualClock24h", true)
        virtualClockSeconds = bool("virtualClockSeconds", false)
        virtualClockDate = bool("virtualClockDate", false)
        virtualBatteryStyle = string("virtualBatteryStyle").flatMap(VirtualBatteryStyle.init(rawValue:)) ?? .icon
        virtualDateFormat = string("virtualDateFormat").flatMap(VirtualDateFormat.init(rawValue:)) ?? .monthDay
        virtualBigStrip = bool("virtualBigStrip", true)
        virtualBigBattery = bool("virtualBigBattery", true)
        virtualBigDate = bool("virtualBigDate", true)
        virtualBigTime = bool("virtualBigTime", true)
        virtualLeft = string("virtualLeft").flatMap(VirtualSide.init(rawValue:)) ?? .battery
        virtualBatteryPercent = bool("virtualBatteryPercent", true)
        virtualRight = string("virtualRight").flatMap(VirtualSide.init(rawValue:)) ?? .none
        collapseDelay = double("collapseDelay", 0.3)
        focusCollapsesOnLeave = bool("focusCollapsesOnLeave", false)
        hotkeyEnabled = bool("hotkeyEnabled", true)
        hotkeyKeyCode = int("hotkeyKeyCode", 49) // Space
        hotkeyModifiers = int("hotkeyModifiers", 1 << 19) // ⌥ (NSEvent.ModifierFlags.option)
        showMenuBarIcon = bool("showMenuBarIcon", true)
        languageOverride = string("languageOverride") ?? "system"
        hoverEffectEnabled = bool("hoverEffectEnabled", true)
        notchWidthAdjust = double("notchWidthAdjust", 0)
        liquidGlassEnabled = bool("liquidGlassEnabled", true)
        nativeSegmented = bool("nativeSegmented", false)
        shelfPeekWithIcon = bool("shelfPeekWithIcon", true)
        shelfShowsCount = bool("shelfShowsCount", true)
        shelfPeekEnabled = bool("shelfPeekEnabled", true)
        shelfAirDropPercent = double("shelfAirDropPercent", 22)
        statusBattery = bool("statusBattery", true)
        statusUpdateTag = bool("statusUpdateTag", true)
        statusBatteryPercent = bool("statusBatteryPercent", true)
        tourSeen = bool("tourSeen", false)
        hudVolume = bool("hudVolume", true)
        hudBrightness = bool("hudBrightness", true)
        hudSeconds = double("hudSeconds", 1.6)
        chargingToast = bool("chargingToast", true)
        chargingToastSeconds = double("chargingToastSeconds", 4)
        lowBatteryToast = bool("lowBatteryToast", true)
        lowBatteryThreshold = double("lowBatteryThreshold", 20)
        lowBatteryDismissOnActivity = bool("lowBatteryDismissOnActivity", true)
        lowBatteryActivityDelay = double("lowBatteryActivityDelay", 3)
        bluetoothToast = bool("bluetoothToast", false) // off until asked for: turning it on makes the system ask for Bluetooth access
        bluetoothToastSeconds = double("bluetoothToastSeconds", 4)
        hudHideSystem = bool("hudHideSystem", true)
        swipeTracksEnabled = bool("swipeTracksEnabled", true)
        swipeThreshold = double("swipeThreshold", 60)
        swipeReversed = bool("swipeReversed", false)
        calendarSwipeEnabled = bool("calendarSwipeEnabled", true)
        calendarSwipeThreshold = double("calendarSwipeThreshold", 40)
        let storedPriority = defaults.stringArray(forKey: Self.prefix + "activityPriority")
        var priority = storedPriority.flatMap { Self.legacyActivityPriorities.contains($0) ? nil : $0 } ?? Self.defaultActivityPriority
        // Activities added later (the stopwatch) join a customised order right after the countdown.
        for id in Self.defaultActivityPriority where !priority.contains(id) {
            let after = id == "stopwatch" ? priority.firstIndex(of: "timer").map { $0 + 1 } : nil
            priority.insert(id, at: after ?? priority.count)
        }
        activityPriority = priority
        mainOnlyActivities = defaults.stringArray(forKey: Self.prefix + "mainOnlyActivities") ?? []
        secondaryOnlyActivities = defaults.stringArray(forKey: Self.prefix + "secondaryOnlyActivities") ?? []
        islandLeftEnabled = bool("islandLeftEnabled", true)
        islandRightEnabled = bool("islandRightEnabled", true)
        islandPrioritySide = string("islandPrioritySide").flatMap(IslandSide.init(rawValue:)) ?? .right
        islandGap = double("islandGap", 9)
        islandMaxSpanPercent = double("islandMaxSpanPercent", 40)
        islandLeftOffset = double("islandLeftOffset", 0)
        islandRightOffset = double("islandRightOffset", 0)
        islandMaxWidth = double("islandMaxWidth", 100)
        islandDisplayMode = string("islandDisplayMode").flatMap(IslandDisplayMode.init(rawValue:)) ?? .always
        islandHideDuringMenus = bool("islandHideDuringMenus", true)
        islandSinking = bool("islandSinking", false)
        islandSmartAvoid = bool("islandSmartAvoid", false)
        mediaPauseRetention = double("mediaPauseRetention", 60)
        // The shelf count is off the island row until the user turns it on (it would otherwise keep the capsule open all day).
        disabledActivities = defaults.stringArray(forKey: Self.prefix + "disabledActivities") ?? ["shelf"]
        showCoverInCompact = bool("showCoverInCompact", true)
        showTrackInfoOnChange = bool("showTrackInfoOnChange", true)
        trackInfoSeconds = double("trackInfoSeconds", 2.5)
        showWaveformInCompact = bool("showWaveformInCompact", true)
        realWaveform = bool("realWaveform", false)
        waveformBars = min(max(int("waveformBars", 3), 3), 7)
        waveformFocus = min(max(int("waveformFocus", 0), 0), SpectrumAnalyzer.Focus.allCases.count - 1)
        waveformGain = min(max(int("waveformGain", 100), 50), 200)
        waveformSensitivity = min(max(int("waveformSensitivity", 100), 50), 200)
        artworkGlow = bool("artworkGlow", true)
        onlineArtwork = bool("onlineArtwork", true)
        onlineLyrics = bool("onlineLyrics", true)
        showWaveformInTitle = bool("showWaveformInTitle", true)
        lyricsTraditional = bool("lyricsTraditional", true)
        lyricsFillerDots = bool("lyricsFillerDots", true)
        lyricsSplitLines = bool("lyricsSplitLines", true)
        lyricsHideRomanization = bool("lyricsHideRomanization", true)
        lyricsOffset = min(max(double("lyricsOffset", 0), -3), 3)
        virtualLyricsScroll = bool("virtualLyricsScroll", false)
        if let data = defaults.data(forKey: Self.prefix + "lyricsSources"),
           let stored = try? JSONDecoder().decode([LyricsSourceItem].self, from: data) {
            lyricsSources = LyricsSourceItem.merged(stored)
        } else {
            // Before the list existed there was a choice: automatic (the default list), only Apple Music's own, or only online.
            var list = LyricsSourceItem.defaults
            switch string("lyricsSource") {
            case "player": list[0].enabled = false
            case "online": list[1].enabled = false
            default: break
            }
            lyricsSources = list
        }
        artworkCache = bool("artworkCache", true)
        mediaSourcePreference = string("mediaSourcePreference").flatMap(MediaSourcePreference.init(rawValue:)) ?? .auto
        timerPresets = (defaults.array(forKey: Self.prefix + "timerPresets") as? [Int]) ?? [1, 5, 10, 25]
        timerSound = bool("timerSound", true)
        timerRing = bool("timerRing", true)
        timerNotification = bool("timerNotification", true)
        timerLastDuration = double("timerLastDuration", 300)
        remindersHiddenListIDs = defaults.stringArray(forKey: Self.prefix + "remindersHiddenListIDs") ?? []
        remindersShowCompleted = bool("remindersShowCompleted", false)
        remindersSort = string("remindersSort").flatMap(ReminderSort.init(rawValue:)) ?? .dueDate
        remindersLimit = int("remindersLimit", 20)
        calendarHiddenIDs = defaults.stringArray(forKey: Self.prefix + "calendarHiddenIDs") ?? []
        calendarShowPast = bool("calendarShowPast", false)
        calendarShowAllDay = bool("calendarShowAllDay", true)
        calendarShowMultiDay = bool("calendarShowMultiDay", true)
        calendarWholeMonth = bool("calendarWholeMonth", true)
        calendarDaysBehind = int("calendarDaysBehind", 7)
        calendarDaysAhead = int("calendarDaysAhead", 7)
        autoCheckUpdates = bool("autoCheckUpdates", true)
        autoInstallUpdates = bool("autoInstallUpdates", false)
        updateChannel = string("updateChannel") ?? "stable"
        notesFontSize = double("notesFontSize", 13)
        notesOpenLast = bool("notesOpenLast", true)
        notesCustomPath = string("notesCustomPath") ?? ""
        notesLastID = string("notesLastID") ?? ""
        shortcutsHidden = defaults.stringArray(forKey: Self.prefix + "shortcutsHidden") ?? []
        shortcutsGrid = bool("shortcutsGrid", true)
        mirrorFlip = bool("mirrorFlip", true)
        mirrorCameraID = string("mirrorCameraID") ?? ""
        shelfAutoClear = string("shelfAutoClear").flatMap(ShelfAutoClear.init(rawValue:)) ?? .never
        shelfAutoClearDays = int("shelfAutoClearDays", 7)
        dragOpensShelf = bool("dragOpensShelf", true)
        dragProximity = double("dragProximity", 120)
        dragIgnoresOtherScreens = bool("dragIgnoresOtherScreens", true)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: Self.prefix + key)
    }

    func activityRole(_ id: String) -> ActivityRole {
        if disabledActivities.contains(id) { return .hidden }
        if mainOnlyActivities.contains(id) { return .mainOnly }
        return secondaryOnlyActivities.contains(id) ? .secondaryOnly : .anyIsland
    }

    func setActivityRole(_ id: String, _ role: ActivityRole) {
        disabledActivities.removeAll { $0 == id }
        mainOnlyActivities.removeAll { $0 == id }
        secondaryOnlyActivities.removeAll { $0 == id }
        switch role {
        case .hidden: disabledActivities.append(id)
        case .mainOnly: mainOnlyActivities.append(id)
        case .secondaryOnly: secondaryOnlyActivities.append(id)
        case .anyIsland: break
        }
    }

    /// Changes whenever something affecting the panel geometry / visibility changes.
    var geometrySignature: [Double] {
        [notchWidthAdjust, screenChoice == .main ? 0 : 1,
         islandLeftEnabled ? 1 : 0, islandRightEnabled ? 1 : 0, islandPrioritySide == .left ? 0 : 1, islandGap,
         islandMaxSpanPercent, islandLeftOffset, islandRightOffset, islandMaxWidth, islandSinking ? 1 : 0,
         islandSmartAvoid ? 1 : 0, virtualNotchEnabled ? 1 : 0, virtualHideInFullscreen ? 1 : 0]
    }
}
