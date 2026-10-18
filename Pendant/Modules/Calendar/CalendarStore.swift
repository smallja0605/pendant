import AppKit
import EventKit
import Observation

/// A calendar the user can show or hide (requirements 4.5). Names are personal data and never logged.
struct CalendarInfo: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let sourceTitle: String
    let red: Double
    let green: Double
    let blue: Double
}

struct CalendarEventItem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String
    let red: Double
    let green: Double
    let blue: Double
}

/// EventKit access for the calendar module: permission, calendar list and the events of one day.
/// Refreshes on `EKEventStoreChanged` only (no polling).
@MainActor
@Observable
final class CalendarStore {
    enum Access: Equatable { case unknown, notDetermined, denied, allowed }

    static let shared = CalendarStore()

    private(set) var access: Access = .unknown
    private(set) var calendars: [CalendarInfo] = []
    private(set) var events: [CalendarEventItem] = []
    private(set) var loadedDay: Date?

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var dayInView: Date?
    #if DEBUG
    @ObservationIgnored private var fakeData = false
    #endif

    var settings: AppSettings { .shared }

    init() {
        refreshAccess()
    }

    #if DEBUG
    /// Visual checks only (PENDANT_DEBUG_CALENDAR=fake): fake permission and events, EventKit untouched.
    func enableFakeData() {
        fakeData = true
        access = .allowed
    }
    #endif

    // MARK: Permission

    func refreshAccess() {
        #if DEBUG
        if fakeData { return }
        #endif
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .allowed
        case .notDetermined: access = .notDetermined
        default: access = .denied
        }
        if access == .allowed { startObserving(); reloadCalendars() }
    }

    /// Asks for full access the first time the calendar is used; harmless when already decided.
    func ensureAccess() async {
        refreshAccess()
        guard access == .notDetermined else { return }
        _ = try? await store.requestFullAccessToEvents()
        refreshAccess()
    }

    private func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeChanged() }
        }
    }

    private func storeChanged() {
        reloadCalendars()
        if let dayInView { loadEvents(for: dayInView) }
    }

    // MARK: Calendars

    private func reloadCalendars() {
        guard access == .allowed else { calendars = []; return }
        calendars = store.calendars(for: .event)
            .map { calendar in
                let rgb = Self.rgb(calendar.color)
                return CalendarInfo(id: calendar.calendarIdentifier, title: calendar.title,
                                    sourceTitle: calendar.source?.title ?? "", red: rgb.red, green: rgb.green, blue: rgb.blue)
            }
            .sorted { ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title) }
    }

    func isVisible(_ id: String) -> Bool { !settings.calendarHiddenIDs.contains(id) }

    func setVisible(_ id: String, _ visible: Bool) {
        var hidden = Set(settings.calendarHiddenIDs)
        if visible { hidden.remove(id) } else { hidden.insert(id) }
        settings.calendarHiddenIDs = hidden.sorted()
    }

    func selectAll() { settings.calendarHiddenIDs = [] }

    func clearSelection() { settings.calendarHiddenIDs = calendars.map(\.id).sorted() }

    // MARK: Events

    /// Loads the events of `day` honouring the visible calendars and the filters; call again when settings change.
    func loadEvents(for day: Date) {
        dayInView = day
        #if DEBUG
        if fakeData {
            let start = CalendarMath.startOfDay(day)
            let hour: (Double) -> Date = { start.addingTimeInterval($0 * 3600) }
            let weekdayIsEven = Calendar.current.component(.day, from: day) % 2 == 0
            events = weekdayIsEven ? [] : [
                CalendarEventItem(id: "a", title: "團隊週會", start: hour(10), end: hour(11), isAllDay: false, location: "會議室 B",
                                  red: 0.2, green: 0.6, blue: 1),
                CalendarEventItem(id: "b", title: "午餐", start: hour(12.5), end: hour(13.5), isAllDay: false, location: "",
                                  red: 0.3, green: 0.8, blue: 0.4),
                CalendarEventItem(id: "c", title: "生日", start: start, end: start.addingTimeInterval(86_400), isAllDay: true,
                                  location: "", red: 1, green: 0.5, blue: 0.3),
            ]
            loadedDay = day
            return
        }
        #endif
        guard access == .allowed else { events = []; loadedDay = day; return }
        let visible = store.calendars(for: .event).filter { isVisible($0.calendarIdentifier) }
        guard !visible.isEmpty else { events = []; loadedDay = day; return }

        let start = CalendarMath.startOfDay(day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
        let filter = CalendarMath.Filter(
            showPast: settings.calendarShowPast, showAllDay: settings.calendarShowAllDay, showMultiDay: settings.calendarShowMultiDay
        )
        let now = Date()
        events = store.events(matching: predicate)
            .filter {
                CalendarMath.includes(.init(start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay), on: day, now: now, filter: filter)
            }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
            .map { event in
                let rgb = Self.rgb(event.calendar.color)
                return CalendarEventItem(
                    id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "", start: event.startDate,
                    end: event.endDate, isAllDay: event.isAllDay, location: event.location ?? "",
                    red: rgb.red, green: rgb.green, blue: rgb.blue
                )
            }
        loadedDay = day
    }

    /// Opens the event in the Calendar app (falls back to just opening the app).
    func open(_ event: CalendarEventItem) {
        if let url = URL(string: "ical://ekevent/\(event.id)?method=show&options=more"), NSWorkspace.shared.open(url) { return }
        openCalendarApp()
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double
    }

    private static func rgb(_ color: NSColor?) -> RGB {
        guard let converted = color?.usingColorSpace(.sRGB) else { return RGB(red: 0.5, green: 0.5, blue: 0.5) }
        return RGB(
            red: Double(converted.redComponent), green: Double(converted.greenComponent), blue: Double(converted.blueComponent)
        )
    }
}
