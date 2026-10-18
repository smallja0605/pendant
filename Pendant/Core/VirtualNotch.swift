import Foundation

/// What the middle part of a virtual notch (a screen without a physical one) shows.
enum VirtualMiddle: String, CaseIterable, Sendable { case clock, none }

/// What a side part of a virtual notch shows while no activity (music, timer, shelf…) takes it over.
enum VirtualSide: String, CaseIterable, Sendable { case battery, none }

/// How the battery is drawn: the battery icon on the left with the percentage on the right, or a ring on the left (a bolt in it
/// while charging) with the percentage on the right.
enum VirtualBatteryStyle: String, CaseIterable, Sendable { case icon, ring }

/// How the date is written (always Chinese).
enum VirtualDateFormat: String, CaseIterable, Sendable {
    case monthDay, fullDate, slash, short

    var pattern: String {
        switch self {
        case .monthDay: "M月d日 EEE"
        case .fullDate: "yyyy年M月d日 EEE"
        case .slash: "yyyy/M/d EEE"
        case .short: "M/d EEE"
        }
    }

    var title: String {
        VirtualClockFormat.date(Date(), format: self)
    }
}

/// The text the virtual notch's clock and the open capsule's strip show for a date: pure, so it is testable.
enum VirtualClockFormat {
    static func date(_ date: Date, format: VirtualDateFormat) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format.pattern
        return formatter.string(from: date)
    }

    static func time(_ date: Date, use24Hour: Bool, seconds: Bool, locale: Locale = Locale(identifier: "zh_TW")) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        switch (use24Hour, seconds) {
        case (true, false): formatter.dateFormat = "HH:mm"
        case (true, true): formatter.dateFormat = "HH:mm:ss"
        case (false, false): formatter.dateFormat = "h:mm a"
        case (false, true): formatter.dateFormat = "h:mm:ss a"
        }
        return formatter.string(from: date)
    }

    static func string(
        for date: Date, use24Hour: Bool, seconds: Bool, showsDate: Bool,
        dateFormat: VirtualDateFormat = .monthDay, locale: Locale = Locale(identifier: "zh_TW")
    ) -> String {
        let timeText = time(date, use24Hour: use24Hour, seconds: seconds, locale: locale)
        return showsDate ? Self.date(date, format: dateFormat) + " " + timeText : timeText
    }
}
