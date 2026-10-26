import Foundation

/// Export and import of every setting as one JSON file that the Windows version reads and writes too (docs/SETTINGS-FORMAT.md).
///
/// ```
/// { "format": "pendant-settings", "version": 1, "platform": "macOS", "app": "0.4.16", "exportedAt": "2026-10-27T01:00:00Z",
///   "common": { "hoverEffectEnabled": true, "lyricsOffset": 0.3, "focus.waveformBars": 5, "moduleLayout": {…}, … },
///   "macOS":  { "liquidGlassEnabled": true, … } }
/// ```
/// `common` holds what both platforms have; a section named after one platform holds what only that one has. An import applies `common` and
/// its own platform's section and ignores every key it does not know (a setting the other platform lacks) — so a file from Windows loads
/// here with whatever fits. Nothing secret travels: the Keychain (API keys, the update signing key) is never read, and machine-specific
/// values (folders, camera, calendar ids, shortcut keys, what was seen once) are left out.
enum SettingsTransfer {
    static let format = "pendant-settings"
    static let version = 1
    static let platform = "macOS"

    /// Every setting `AppSettings` keeps (the names after `settings.`); a test keeps this list equal to the source.
    static let appKeys: [String] = [
        "activityPriority", "artworkCache", "artworkGlow", "autoCheckUpdates", "autoInstallUpdates", "bluetoothToast",
        "bluetoothToastSeconds", "calendarDaysAhead", "calendarDaysBehind", "calendarHiddenIDs", "calendarShowAllDay",
        "calendarShowMultiDay", "calendarShowPast", "calendarSwipeEnabled", "calendarSwipeThreshold", "calendarWholeMonth",
        "chargingToast", "chargingToastSeconds", "collapseDelay", "disabledActivities", "dragIgnoresOtherScreens",
        "dragOpensShelf", "dragProximity", "focusCollapsesOnLeave", "hotkeyEnabled", "hotkeyKeyCode", "hotkeyModifiers",
        "hoverDelay", "hoverEffectEnabled", "hoverExpandMode", "hudBrightness", "hudHideSystem", "hudSeconds", "hudVolume",
        "islandDisplayMode", "islandGap", "islandHideDuringMenus", "islandLeftEnabled", "islandLeftOffset",
        "islandMaxSpanPercent", "islandMaxWidth", "islandPrioritySide", "islandRightEnabled", "islandRightOffset",
        "islandSinking", "islandSmartAvoid", "languageOverride", "liquidGlassEnabled", "lowBatteryActivityDelay",
        "lowBatteryDismissOnActivity", "lowBatteryThreshold", "lowBatteryToast", "lyricsFillerDots", "lyricsHideRomanization",
        "lyricsOffset", "lyricsSources", "lyricsSplitLines", "lyricsTraditional", "mainOnlyActivities", "mediaPauseRetention",
        "mediaSourcePreference", "mirrorCameraID", "mirrorFlip", "nativeSegmented", "notchWidthAdjust", "notesCustomPath",
        "notesFontSize", "notesLastID", "notesOpenLast", "onlineArtwork", "onlineLyrics", "realWaveform",
        "remindersHiddenListIDs", "remindersLimit", "remindersShowCompleted", "remindersSort", "screenChoice",
        "secondaryOnlyActivities", "shelfAirDropPercent", "shelfAutoClear", "shelfAutoClearDays", "shelfPeekEnabled",
        "shelfPeekWithIcon", "shelfShowsCount", "shortcutsGrid", "shortcutsHidden", "showCoverInCompact", "showMenuBarIcon",
        "showTrackInfoOnChange", "showWaveformInCompact", "showWaveformInTitle", "statusBattery", "statusBatteryPercent",
        "statusUpdateTag", "swipeReversed", "swipeThreshold", "swipeTracksEnabled", "timerLastDuration", "timerNotification",
        "timerPresets", "timerRing", "timerSound", "tourSeen", "trackInfoSeconds", "updateChannel", "virtualBatteryPercent",
        "virtualBatteryStyle", "virtualBigBattery", "virtualBigDate", "virtualBigStrip", "virtualBigTime", "virtualClock24h",
        "virtualClockDate", "virtualClockSeconds", "virtualDateFormat", "virtualFloatGap", "virtualFloating",
        "virtualHideInFullscreen", "virtualIdleHide", "virtualIdleHover", "virtualLeft", "virtualLyricsScroll", "virtualMiddle",
        "virtualNotchEnabled", "virtualRight", "waveformArtworkColor", "waveformBars", "waveformFocus", "waveformGain",
        "waveformSensitivity", "wheelSensitivity",
    ]
    /// The single-tool capsule's (`settings.focus.`).
    static let focusKeys: [String] = [
        "calendarTileWidth", "calendarTodayPosition", "calendarWeekStart", "glowStrength", "lyricsCentered", "lyricsFillArtwork",
        "lyricsFontSize", "lyricsFontWeight", "lyricsOthersOpacity", "lyricsOthersScale", "lyricsScrollDuration",
        "lyricsScrollSpring", "lyricsTapToSeek", "playerShare", "remindersDefaultDue", "remindersDefaultList",
        "remindersDefaultPriority", "remindersExtraHeight", "remindersHandle", "remindersSplit", "showOutputButtons",
        "showProgressTimes", "waveformArtworkColor", "waveformBars", "waveformFocus", "waveformGain", "waveformReal",
        "waveformSensitivity",
    ]

    /// Left out of every file: meaningful on this Mac only, or something that was shown once.
    static let excluded: Set<String> = [
        "tourSeen", "migratedFromLegacyDomain", "shelfLastBoot", "notesLastID", "notesCustomPath", "mirrorCameraID", "calendarHiddenIDs",
        "remindersHiddenListIDs", "timerLastDuration", "focus.remindersDefaultList",
    ]
    /// Only the Mac has these (Liquid Glass, the menu bar icon, Apple Music / Spotify, the trackpad, the Shortcuts app, the hot key).
    static let macOnly: Set<String> = [
        "liquidGlassEnabled", "nativeSegmented", "hudHideSystem", "showMenuBarIcon", "mediaSourcePreference", "hotkeyEnabled",
        "hotkeyKeyCode", "hotkeyModifiers", "shortcutsGrid", "shortcutsHidden", "swipeReversed", "swipeThreshold", "swipeTracksEnabled",
        "calendarSwipeEnabled", "calendarSwipeThreshold", "hapticsEnabled",
    ]
    /// Settings stored as JSON data, written into the file as real JSON: file key → UserDefaults key.
    private static let jsonBlobs = ["lyricsSources": "settings.lyricsSources", "moduleLayout": "modules.layout"]

    struct ImportResult: Equatable {
        var applied = 0
        var ignored = 0
        var platform = ""
    }

    enum TransferError: Error, Equatable {
        case notASettingsFile, newerVersion(Int), unreadable
        var message: String {
            switch self {
            case .notASettingsFile: "這不是 Pendant 的設定檔"
            case .newerVersion: "這份設定檔來自較新的版本，請先更新 Pendant"
            case .unreadable: "無法讀取這個檔案"
            }
        }
    }

    // MARK: Export

    /// The file's key for a UserDefaults key (nil: not a setting that travels).
    static func fileKey(for defaultsKey: String) -> String? {
        switch defaultsKey {
        case "modules.layout": "moduleLayout"
        case "haptics.enabled": "hapticsEnabled"
        case let key where key.hasPrefix(FocusCapsuleSettings.prefix): "focus." + key.dropFirst(FocusCapsuleSettings.prefix.count)
        case let key where key.hasPrefix(AppSettings.prefix): String(key.dropFirst(AppSettings.prefix.count))
        default: nil
        }
    }

    static func defaultsKey(for fileKey: String) -> String {
        switch fileKey {
        case "moduleLayout": "modules.layout"
        case "hapticsEnabled": "haptics.enabled"
        case let key where key.hasPrefix("focus."): FocusCapsuleSettings.prefix + key.dropFirst("focus.".count)
        default: AppSettings.prefix + fileKey
        }
    }

    private static func isKnown(_ fileKey: String) -> Bool {
        if fileKey == "moduleLayout" || fileKey == "hapticsEnabled" { return true }
        if fileKey.hasPrefix("focus.") { return focusKeys.contains(String(fileKey.dropFirst("focus.".count))) }
        return appKeys.contains(fileKey)
    }

    static func export(from defaults: UserDefaults, appVersion: String, now: Date = Date()) throws -> Data {
        var common: [String: Any] = [:], own: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() {
            guard let name = fileKey(for: key), isKnown(name), !excluded.contains(name) else { continue }
            var json: Any = value
            if let data = value as? Data {
                guard let object = try? JSONSerialization.jsonObject(with: data) else { continue }
                json = object
            }
            guard JSONSerialization.isValidJSONObject([json]) else { continue }
            if macOnly.contains(name) { own[name] = json } else { common[name] = json }
        }
        let root: [String: Any] = [
            "format": format, "version": version, "platform": platform, "app": appVersion,
            "exportedAt": ISO8601DateFormatter().string(from: now), "common": common, platform: own,
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: Import

    /// Applies a settings file to `defaults`. The caller restarts the app afterwards (the settings objects read their values at launch).
    @discardableResult
    static func apply(_ data: Data, to defaults: UserDefaults) throws -> ImportResult {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw TransferError.unreadable }
        guard root["format"] as? String == format else { throw TransferError.notASettingsFile }
        let fileVersion = root["version"] as? Int ?? 1
        guard fileVersion <= version else { throw TransferError.newerVersion(fileVersion) }
        var result = ImportResult(platform: root["platform"] as? String ?? "")
        for section in ["common", platform] {
            guard let values = root[section] as? [String: Any] else { continue }
            for (name, value) in values {
                guard isKnown(name), !excluded.contains(name), accepts(value, isBlob: jsonBlobs.keys.contains(name)) else {
                    result.ignored += 1
                    continue
                }
                // A Mac-only key under "common" (a file from another platform) is not applied.
                if section == "common", macOnly.contains(name) { result.ignored += 1; continue }
                if jsonBlobs.keys.contains(name) {
                    guard JSONSerialization.isValidJSONObject(value), let blob = try? JSONSerialization.data(withJSONObject: value) else {
                        result.ignored += 1
                        continue
                    }
                    defaults.set(blob, forKey: defaultsKey(for: name))
                } else {
                    defaults.set(value, forKey: defaultsKey(for: name))
                }
                result.applied += 1
            }
        }
        return result
    }

    /// A setting is a plain value (bool, number, text, a list of text); only the two JSON blobs may be objects or lists of objects.
    private static func accepts(_ value: Any, isBlob: Bool) -> Bool {
        if isBlob { return value is [String: Any] || value is [Any] }
        switch value {
        case is Bool, is NSNumber, is String: return true
        case let list as [Any]: return list.allSatisfy { $0 is String }
        default: return false
        }
    }
}
