import Foundation

/// Pure date logic for the calendar module (testable without EventKit).
enum CalendarMath {
    struct Filter: Equatable, Sendable {
        var showPast: Bool
        var showAllDay: Bool
        var showMultiDay: Bool
    }

    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func day(offset: Int, from today: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: startOfDay(today, calendar: calendar)) ?? today
    }

    /// The time span of one event.
    struct Span: Equatable, Sendable {
        let start: Date
        let end: Date
        let isAllDay: Bool
    }

    /// Whether an event is listed for `day` under the user's filters (requirements 4.5).
    static func includes(_ span: Span, on day: Date, now: Date, filter: Filter, calendar: Calendar = .current) -> Bool {
        let (start, end, isAllDay) = (span.start, span.end, span.isAllDay)
        let dayStart = startOfDay(day, calendar: calendar)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        // Must intersect the day (an event ending exactly at midnight does not belong to the next day).
        guard start < dayEnd, end > dayStart || start == end && start >= dayStart else { return false }

        if isAllDay, !filter.showAllDay { return false }
        let lastMoment = end > start ? end.addingTimeInterval(-1) : end
        let spansDays = startOfDay(start, calendar: calendar) != startOfDay(lastMoment, calendar: calendar)
        if spansDays, !isAllDay || spansMoreThanOneDay(start: start, end: end, calendar: calendar), !filter.showMultiDay { return false }
        if !filter.showPast, !isAllDay, calendar.isDate(day, inSameDayAs: now), end <= now { return false }
        return true
    }

    private static func spansMoreThanOneDay(start: Date, end: Date, calendar: Calendar) -> Bool {
        let first = startOfDay(start, calendar: calendar)
        let last = startOfDay(end.addingTimeInterval(-1), calendar: calendar)
        return first != last
    }

    /// "10月" / "Oct" for the strip's big month label.
    static func monthLabel(_ date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    /// "週日" / "Sun".
    static func weekdayLabel(_ date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }

    /// Offsets (relative to `today`) of the first and last day of today's month: the strip can cover the whole month.
    static func monthRange(today: Date, calendar: Calendar = .current) -> ClosedRange<Int> {
        let start = startOfDay(today, calendar: calendar)
        guard let interval = calendar.dateInterval(of: .month, for: start) else { return 0...0 }
        let first = calendar.dateComponents([.day], from: start, to: interval.start).day ?? 0
        let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? start
        let last = calendar.dateComponents([.day], from: start, to: lastDay).day ?? 0
        return first...last
    }

    static func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDateInWeekend(date)
    }

    /// Time line of an event row: "09:00–10:30", "全天" for all-day events.
    static func timeText(start: Date, end: Date, isAllDay: Bool, locale: Locale = .current) -> String {
        if isAllDay { return String(localized: "calendar.allDay", defaultValue: "全天") }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }
}
