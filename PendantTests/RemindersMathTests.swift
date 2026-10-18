import Foundation
import Testing
@testable import Pendant

struct RemindersMathTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func item(_ title: String, due: Date? = nil, priority: Int = 0, done: Bool = false, hasTime: Bool = true) -> ReminderItem {
        ReminderItem(id: title, title: title, listID: "L", listTitle: "List", red: 0, green: 0, blue: 0,
                     due: due, dueHasTime: hasTime, priority: priority, isCompleted: done)
    }

    @Test func priorityMarksFollowEventKitRanges() {
        #expect(RemindersMath.priorityMarks(0) == "")
        #expect(RemindersMath.priorityMarks(1) == "!!!")
        #expect(RemindersMath.priorityMarks(4) == "!!!")
        #expect(RemindersMath.priorityMarks(5) == "!!")
        #expect(RemindersMath.priorityMarks(9) == "!")
    }

    @Test func sortByDueDatePutsUndatedLastAndCompletedAfterOpen() {
        let items = [item("c", due: nil), item("b", due: date(20)), item("done", due: date(1), done: true), item("a", due: date(19))]
        let sorted = RemindersMath.sorted(items, by: .dueDate).map(\.title)
        #expect(sorted == ["a", "b", "c", "done"])
    }

    @Test func sortByPriorityThenTitle() {
        let items = [item("z", priority: 0), item("b", priority: 9), item("a", priority: 1), item("c", priority: 1)]
        #expect(RemindersMath.sorted(items, by: .priority).map(\.title) == ["a", "c", "b", "z"])
    }

    @Test func limitKeepsOrderAcrossGroups() {
        let groups = [[item("a"), item("b"), item("c")], [item("d"), item("e")]]
        let limited = RemindersMath.limited(groups, to: 4)
        #expect(limited.map { $0.map(\.title) } == [["a", "b", "c"], ["d"]])
        #expect(RemindersMath.limited(groups, to: 0).isEmpty)
    }

    @Test func dueTextNamesTodayAndFlagsOverdue() {
        let now = date(18, 12)
        let locale = Locale(identifier: "en_US")
        let later = RemindersMath.dueText(due: date(18, 15), hasTime: true, now: now, calendar: calendar, locale: locale)
        #expect(later.overdue == false)
        #expect(later.text.hasPrefix("今天") || later.text.hasPrefix("Today"))
        let earlier = RemindersMath.dueText(due: date(18, 9), hasTime: true, now: now, calendar: calendar, locale: locale)
        #expect(earlier.overdue)
        // A date-only reminder for today is not overdue until the day is over, and shows no time.
        let allDay = RemindersMath.dueText(due: date(18), hasTime: false, now: now, calendar: calendar, locale: locale)
        #expect(!allDay.overdue)
        let yesterday = RemindersMath.dueText(due: date(17), hasTime: false, now: now, calendar: calendar, locale: locale)
        #expect(yesterday.overdue)
    }
}

struct ReminderDraftTests {
    @Test func optionsLightUpOnlyForExtras() {
        var draft = ReminderDraft()
        draft.title = "x"
        draft.due = Date()
        #expect(!draft.hasOptions)
        draft.priority = .high
        #expect(draft.hasOptions)
    }

    @Test func urlNeedsAHost() {
        var draft = ReminderDraft()
        draft.url = "apple.com"
        #expect(draft.validURL?.absoluteString == "https://apple.com")
        draft.url = "not a url"
        #expect(draft.validURL == nil)
        draft.url = ""
        #expect(draft.validURL == nil)
    }

    @Test func alertAndPriorityMapToEventKitValues() {
        #expect(ReminderEarlyAlert.oneHour.rawValue == 3600)
        #expect(ReminderPriorityChoice.high.rawValue == 1 && ReminderPriorityChoice.low.rawValue == 9)
    }
}
