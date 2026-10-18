import Foundation

/// What the middle part of a virtual notch (a screen without a physical one) shows.
enum VirtualMiddle: String, CaseIterable, Sendable { case clock, none }

/// What a side part of a virtual notch shows while no activity (music, timer, shelf…) takes it over.
enum VirtualSide: String, CaseIterable, Sendable { case battery, none }

/// The text the virtual notch's clock shows for a date: pure, so it is testable.
enum VirtualClockFormat {
    static func string(for date: Date, use24Hour: Bool, seconds: Bool, showsDate: Bool, locale: Locale = .current) -> String {
        let time: String
        switch (use24Hour, seconds) {
        case (true, false): time = "HH:mm"
        case (true, true): time = "HH:mm:ss"
        case (false, false): time = "h:mm a"
        case (false, true): time = "h:mm:ss a"
        }
        let pattern = showsDate ? "MMMd EEE " + time : time
        let formatter = DateFormatter()
        formatter.locale = locale
        if showsDate {
            // "MMMd EEE" localised by the template, then the time pattern appended literally.
            formatter.setLocalizedDateFormatFromTemplate("MMMd EEE")
            let datePart = formatter.string(from: date)
            formatter.dateFormat = time
            return datePart + " " + formatter.string(from: date)
        }
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
