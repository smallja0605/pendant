import Foundation
import Testing
@testable import Pendant

struct CalendarMathTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private let all = CalendarMath.Filter(showPast: true, showAllDay: true, showMultiDay: true)

    @Test func dayOffsetsMoveByCalendarDays() {
        let today = date(18, 15, 30)
        #expect(CalendarMath.day(offset: 0, from: today, calendar: calendar) == date(18))
        #expect(CalendarMath.day(offset: -7, from: today, calendar: calendar) == date(11))
        let november = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        #expect(CalendarMath.day(offset: 14, from: today, calendar: calendar) == november)
    }

    @Test func eventMustIntersectTheDay() {
        let now = date(18, 8)
        #expect(CalendarMath.includes(.init(start: date(18, 9), end: date(18, 10), isAllDay: false), on: date(18), now: now, filter: all, calendar: calendar))
        #expect(!CalendarMath.includes(.init(start: date(19, 9), end: date(19, 10), isAllDay: false), on: date(18), now: now, filter: all, calendar: calendar))
        // Ends exactly at midnight: belongs to the previous day only.
        #expect(!CalendarMath.includes(.init(start: date(17, 22), end: date(18, 0), isAllDay: false), on: date(18), now: now, filter: all, calendar: calendar))
        #expect(CalendarMath.includes(.init(start: date(17, 22), end: date(18, 0), isAllDay: false), on: date(17), now: now, filter: all, calendar: calendar))
    }

    @Test func pastEventsOfTodayCanBeHidden() {
        let now = date(18, 12)
        let hidePast = CalendarMath.Filter(showPast: false, showAllDay: true, showMultiDay: true)
        #expect(!CalendarMath.includes(.init(start: date(18, 9), end: date(18, 10), isAllDay: false), on: date(18), now: now, filter: hidePast, calendar: calendar))
        #expect(CalendarMath.includes(.init(start: date(18, 13), end: date(18, 14), isAllDay: false), on: date(18), now: now, filter: hidePast, calendar: calendar))
        // Other days are never "past" for this rule; all-day events are not over until the day ends.
        #expect(CalendarMath.includes(.init(start: date(17, 9), end: date(17, 10), isAllDay: false), on: date(17), now: now, filter: hidePast, calendar: calendar))
        #expect(CalendarMath.includes(.init(start: date(18), end: date(19), isAllDay: true), on: date(18), now: now, filter: hidePast, calendar: calendar))
    }

    @Test func allDayAndMultiDayFilters() {
        let now = date(18, 8)
        let noAllDay = CalendarMath.Filter(showPast: true, showAllDay: false, showMultiDay: true)
        #expect(!CalendarMath.includes(.init(start: date(18), end: date(19), isAllDay: true), on: date(18), now: now, filter: noAllDay, calendar: calendar))

        let noMulti = CalendarMath.Filter(showPast: true, showAllDay: true, showMultiDay: false)
        #expect(!CalendarMath.includes(.init(start: date(17, 20), end: date(19, 9), isAllDay: false), on: date(18), now: now, filter: noMulti, calendar: calendar))
        #expect(CalendarMath.includes(.init(start: date(18, 9), end: date(18, 10), isAllDay: false), on: date(18), now: now, filter: noMulti, calendar: calendar))
        // A single all-day event is not "multi-day"; a three-day all-day event is.
        #expect(CalendarMath.includes(.init(start: date(18), end: date(19), isAllDay: true), on: date(18), now: now, filter: noMulti, calendar: calendar))
        #expect(!CalendarMath.includes(.init(start: date(17), end: date(20), isAllDay: true), on: date(18), now: now, filter: noMulti, calendar: calendar))
    }

    @Test func labelsAreLocalised() {
        let locale = Locale(identifier: "en_US")
        #expect(CalendarMath.monthLabel(date(18), locale: locale) == "Oct")
        #expect(CalendarMath.weekdayLabel(date(18), locale: locale) == "Sun")
        #expect(CalendarMath.monthLabel(date(18), locale: Locale(identifier: "zh_TW")) == "10月")
    }

    @Test func monthRangeCoversTheWholeMonthAroundToday() {
        let today = date(18)   // Oct 18, 2026: Oct 1 … Oct 31
        let range = CalendarMath.monthRange(today: today, calendar: calendar)
        #expect(range == -17...13)
        let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 10))!
        #expect(CalendarMath.monthRange(today: february, calendar: calendar) == -9...18)
    }
}
