import AppKit
import EventKit
import Observation

struct ReminderListInfo: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let red: Double
    let green: Double
    let blue: Double
}

/// EventKit access for the reminders module (requirements 4.3): permission, lists, items, completion and
/// quick add. Refreshes on `EKEventStoreChanged` only.
@MainActor
@Observable
final class RemindersStore {
    enum Access: Equatable { case unknown, notDetermined, denied, allowed }

    static let shared = RemindersStore()

    private(set) var access: Access = .unknown
    private(set) var lists: [ReminderListInfo] = []
    /// Items grouped by list, already filtered, sorted and capped.
    private(set) var groups: [[ReminderItem]] = []
    private(set) var totalIncomplete = 0

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var recentlyCompleted: Set<String> = []
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var settings: AppSettings { .shared }
    #if DEBUG
    @ObservationIgnored private var fakeData = false
    #endif

    init() {
        refreshAccess()
    }

    // MARK: Permission

    func refreshAccess() {
        #if DEBUG
        if fakeData { return }
        #endif
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: access = .allowed
        case .notDetermined: access = .notDetermined
        default: access = .denied
        }
        if access == .allowed { startObserving(); reloadLists() }
    }

    func ensureAccess() async {
        refreshAccess()
        guard access == .notDetermined else { return }
        _ = try? await store.requestFullAccessToReminders()
        refreshAccess()
    }

    private func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadLists()
                Task { await self?.reload() }
            }
        }
    }

    // MARK: Lists

    private func reloadLists() {
        guard access == .allowed else { lists = []; return }
        lists = store.calendars(for: .reminder).map { calendar in
            let rgb = Self.rgb(calendar.color)
            return ReminderListInfo(id: calendar.calendarIdentifier, title: calendar.title, red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
    }

    func isVisible(_ id: String) -> Bool { !settings.remindersHiddenListIDs.contains(id) }

    func setVisible(_ id: String, _ visible: Bool) {
        var hidden = Set(settings.remindersHiddenListIDs)
        if visible { hidden.remove(id) } else { hidden.insert(id) }
        settings.remindersHiddenListIDs = hidden.sorted()
    }

    func selectAll() { settings.remindersHiddenListIDs = [] }

    func clearSelection() { settings.remindersHiddenListIDs = lists.map(\.id).sorted() }

    // MARK: Items

    func reload() async {
        #if DEBUG
        if fakeData { loadFake(); return }
        #endif
        guard access == .allowed else { groups = []; totalIncomplete = 0; return }
        let visible = store.calendars(for: .reminder).filter { isVisible($0.calendarIdentifier) }
        guard !visible.isEmpty else { groups = []; totalIncomplete = 0; return }

        var items = await fetch(store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: visible))
        let incomplete = items.count
        // Just-checked reminders stay in the list (struck through) until the page is left.
        for id in recentlyCompleted where !items.contains(where: { $0.id == id }) {
            if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.isCompleted,
               visible.contains(where: { $0.calendarIdentifier == reminder.calendar.calendarIdentifier }) {
                items.append(Self.item(from: reminder))
            }
        }
        if settings.remindersShowCompleted {
            let since = Calendar.current.date(byAdding: .day, value: -14, to: Date())
            let completed = store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: Date(), calendars: visible)
            items += await fetch(completed)
        }
        apply(items, incomplete: incomplete)
    }

    private func apply(_ items: [ReminderItem], incomplete: Int) {
        let order = lists.map(\.id)
        let byList = Dictionary(grouping: items, by: \.listID)
        let ordered = byList.keys.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        let sorted = ordered.map { RemindersMath.sorted(byList[$0] ?? [], by: settings.remindersSort) }
        groups = RemindersMath.limited(sorted, to: settings.remindersLimit)
        totalIncomplete = incomplete
    }

    /// Converts EventKit objects to plain values on EventKit's own callback thread. The callback must not be
    /// main-actor isolated (it runs on EventKit's queue, which trapped the isolation check), hence the nonisolated helper.
    private func fetch(_ predicate: NSPredicate) async -> [ReminderItem] {
        await withCheckedContinuation { continuation in
            Self.startFetch(store, predicate, continuation)
        }
    }

    private nonisolated static func startFetch(
        _ store: EKEventStore, _ predicate: NSPredicate, _ continuation: CheckedContinuation<[ReminderItem], Never>
    ) {
        store.fetchReminders(matching: predicate) { reminders in
            continuation.resume(returning: (reminders ?? []).map(Self.item(from:)))
        }
    }

    private nonisolated static func item(from reminder: EKReminder) -> ReminderItem {
        let components = reminder.dueDateComponents
        let rgb = Self.rgb(reminder.calendar.color)
        return ReminderItem(
            id: reminder.calendarItemIdentifier, title: reminder.title ?? "", listID: reminder.calendar.calendarIdentifier,
            listTitle: reminder.calendar.title, red: rgb.red, green: rgb.green, blue: rgb.blue,
            due: components.flatMap { Calendar.current.date(from: $0) }, dueHasTime: components?.hour != nil,
            priority: reminder.priority, isCompleted: reminder.isCompleted
        )
    }

    // MARK: Changes

    func setCompleted(_ item: ReminderItem, _ completed: Bool) async {
        #if DEBUG
        if fakeData { return }
        #endif
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = completed
        try? store.save(reminder, commit: true)
        if completed { recentlyCompleted.insert(item.id) } else { recentlyCompleted.remove(item.id) }
        await reload()
    }

    /// Deletes a reminder (swipe action).
    func delete(_ item: ReminderItem) async {
        #if DEBUG
        if fakeData {
            groups = groups.map { $0.filter { $0.id != item.id } }.filter { !$0.isEmpty }
            return
        }
        #endif
        recentlyCompleted.remove(item.id)
        if let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder {
            try? store.remove(reminder, commit: true)
        }
        await reload()
    }

    /// The reminders page was left: checked items disappear for good.
    func flushCompleted() {
        guard !recentlyCompleted.isEmpty else { return }
        recentlyCompleted = []
        Task { await reload() }
    }

    /// Quick add: title, optional date and the options of `ReminderDraft`, into the chosen (or default) list.
    func add(_ draft: ReminderDraft) async {
        let trimmed = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, access == .allowed else { return }
        let reminder = EKReminder(eventStore: store)
        reminder.title = trimmed
        reminder.calendar = draft.listID.flatMap { id in store.calendars(for: .reminder).first { $0.calendarIdentifier == id } }
            ?? store.defaultCalendarForNewReminders()
            ?? store.calendars(for: .reminder).first { isVisible($0.calendarIdentifier) }
        if !draft.notes.isEmpty { reminder.notes = draft.notes }
        reminder.url = draft.validURL
        reminder.priority = draft.priority.rawValue
        if let due = draft.due {
            let units: Set<Calendar.Component> = draft.includeTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(units, from: due)
            if let rule = Self.recurrenceRule(draft.repeatRule) { reminder.addRecurrenceRule(rule) }
            if draft.urgent { reminder.addAlarm(EKAlarm(relativeOffset: 0)) }
            if draft.earlyAlert != .none { reminder.addAlarm(EKAlarm(relativeOffset: -TimeInterval(draft.earlyAlert.rawValue))) }
        }
        try? store.save(reminder, commit: true)
        await reload()
    }

    private static func recurrenceRule(_ choice: ReminderRepeat) -> EKRecurrenceRule? {
        let (frequency, interval): (EKRecurrenceFrequency, Int)
        switch choice {
        case .never: return nil
        case .daily: (frequency, interval) = (.daily, 1)
        case .weekly: (frequency, interval) = (.weekly, 1)
        case .biweekly: (frequency, interval) = (.weekly, 2)
        case .monthly: (frequency, interval) = (.monthly, 1)
        case .yearly: (frequency, interval) = (.yearly, 1)
        }
        return EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: nil)
    }

    func openRemindersApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double
    }

    private nonisolated static func rgb(_ color: NSColor?) -> RGB {
        guard let converted = color?.usingColorSpace(.sRGB) else { return RGB(red: 0.5, green: 0.5, blue: 0.5) }
        return RGB(
            red: Double(converted.redComponent), green: Double(converted.greenComponent), blue: Double(converted.blueComponent)
        )
    }

    #if DEBUG
    /// Visual checks only (PENDANT_DEBUG_REMINDERS=fake): fake permission and items, EventKit untouched.
    func enableFakeData() {
        fakeData = true
        access = .allowed
        lists = [ReminderListInfo(id: "w", title: "工作", red: 0.2, green: 0.6, blue: 1),
                 ReminderListInfo(id: "h", title: "生活", red: 0.3, green: 0.8, blue: 0.4)]
    }

    private func loadFake() {
        let now = Date()
        func make(_ title: String, _ list: Int, _ due: TimeInterval?, _ priority: Int = 0) -> ReminderItem {
            let info = lists[list]
            return ReminderItem(id: title, title: title, listID: info.id, listTitle: info.title, red: info.red, green: info.green,
                                blue: info.blue, due: due.map { now.addingTimeInterval($0) }, dueHasTime: true,
                                priority: priority, isCompleted: false)
        }
        apply([make("交付 M6 設計稿", 0, 3_600, 1), make("回覆客戶信件", 0, -7_200, 5), make("買牛奶", 1, 86_400), make("整理桌面", 1, nil)],
              incomplete: 4)
    }
    #endif
}
