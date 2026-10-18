import Foundation

enum ReminderSort: String, CaseIterable, Sendable {
    case dueDate, priority, title
}

/// A reminder as the UI needs it (plain values, safe to pass around).
struct ReminderItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let listID: String
    let listTitle: String
    let red: Double
    let green: Double
    let blue: Double
    let due: Date?
    /// False when the reminder has a date but no time of day.
    let dueHasTime: Bool
    /// EventKit priority: 0 none, 1–4 high, 5 medium, 6–9 low.
    let priority: Int
    let isCompleted: Bool
}

/// Pure ordering / formatting helpers for the reminders module.
enum RemindersMath {
    /// "!!!" / "!!" / "!" or "" for no priority.
    static func priorityMarks(_ priority: Int) -> String {
        switch priority {
        case 1...4: "!!!"
        case 5: "!!"
        case 6...9: "!"
        default: ""
        }
    }

    /// Lower rank = more urgent (no priority sorts last).
    static func priorityRank(_ priority: Int) -> Int {
        switch priority {
        case 1...4: 0
        case 5: 1
        case 6...9: 2
        default: 3
        }
    }

    /// Orders items inside a list: incomplete first, then by the chosen mode; undated reminders go last
    /// when sorting by date.
    static func sorted(_ items: [ReminderItem], by sort: ReminderSort) -> [ReminderItem] {
        items.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            switch sort {
            case .dueDate:
                switch (lhs.due, rhs.due) {
                case let (left?, right?) where left != right: return left < right
                case (nil, _?): return false
                case (_?, nil): return true
                default: break
                }
            case .priority:
                let (left, right) = (priorityRank(lhs.priority), priorityRank(rhs.priority))
                if left != right { return left < right }
            case .title:
                break
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    /// Caps the total number of rows shown across all lists, keeping each list's order.
    static func limited(_ groups: [[ReminderItem]], to limit: Int) -> [[ReminderItem]] {
        var remaining = max(limit, 0)
        var result: [[ReminderItem]] = []
        for group in groups where remaining > 0 {
            let taken = Array(group.prefix(remaining))
            remaining -= taken.count
            if !taken.isEmpty { result.append(taken) }
        }
        return result
    }

    /// Due-date text and whether it is overdue. Date-only reminders show no time; today and tomorrow are
    /// named, anything else uses a short date.
    static func dueText(
        due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> (text: String, overdue: Bool) {
        let overdue = hasTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
        let time = DateFormatter()
        time.locale = locale
        time.timeStyle = .short
        time.dateStyle = .none
        let timePart = hasTime ? time.string(from: due) : ""

        let day: String
        if calendar.isDate(due, inSameDayAs: now) {
            day = String(localized: "reminders.today", defaultValue: "今天")
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            day = String(localized: "reminders.tomorrow", defaultValue: "明天")
        } else {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("Md")
            day = formatter.string(from: due)
        }
        return (timePart.isEmpty ? day : "\(day) \(timePart)", overdue)
    }
}

// MARK: - New reminder (quick add + options)

enum ReminderRepeat: String, CaseIterable, Sendable {
    case never, daily, weekly, biweekly, monthly, yearly

    var title: String {
        switch self {
        case .never: "永不"
        case .daily: "每天"
        case .weekly: "每週"
        case .biweekly: "每兩週"
        case .monthly: "每月"
        case .yearly: "每年"
        }
    }
}

/// "Early reminder": an alert this long before the due date.
enum ReminderEarlyAlert: Int, CaseIterable, Sendable {
    case none = 0, fiveMinutes = 300, fifteenMinutes = 900, thirtyMinutes = 1800
    case oneHour = 3600, twoHours = 7200, oneDay = 86400, twoDays = 172_800

    var title: String {
        switch self {
        case .none: "無"
        case .fiveMinutes: "5 分鐘前"
        case .fifteenMinutes: "15 分鐘前"
        case .thirtyMinutes: "30 分鐘前"
        case .oneHour: "1 小時前"
        case .twoHours: "2 小時前"
        case .oneDay: "1 天前"
        case .twoDays: "2 天前"
        }
    }
}

enum ReminderPriorityChoice: Int, CaseIterable, Sendable {
    /// Values are EventKit priorities: 0 none, 9 low, 5 medium, 1 high.
    case none = 0, low = 9, medium = 5, high = 1

    var title: String {
        switch self {
        case .none: "無"
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}

/// Everything the "new reminder" row can set. Tags, flags, location triggers, message triggers and images are not
/// available through EventKit, so they are not offered.
struct ReminderDraft: Equatable, Sendable {
    var title = ""
    var due: Date?
    var includeTime = false
    var notes = ""
    var url = ""
    /// Alert at the due time ("urgent").
    var urgent = false
    var repeatRule: ReminderRepeat = .never
    var earlyAlert: ReminderEarlyAlert = .none
    /// nil = the default list.
    var listID: String?
    var priority: ReminderPriorityChoice = .none

    /// Something besides title and date is set (the options button lights up).
    var hasOptions: Bool {
        !notes.isEmpty || !url.isEmpty || urgent || repeatRule != .never || earlyAlert != .none || listID != nil || priority != .none
    }

    /// Valid web URL typed by the user, if any.
    var validURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
              parsed.host?.contains(".") == true else { return nil }
        return parsed
    }
}
