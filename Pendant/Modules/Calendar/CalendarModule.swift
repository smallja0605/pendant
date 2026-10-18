import SwiftUI

/// Calendar page of the expanded capsule (requirements 4.5).
@MainActor
final class CalendarModule: PendantModule {
    let id = "calendar"
    let displayName = String(localized: "module.calendar", defaultValue: "行事曆")
    let symbolName = "calendar"
    let cells = CellRange(default: 5, range: 1...10)
    let requiredPermissions: [PendantPermission] = [.calendars]
    var isEnabled = false

    private let store = CalendarStore.shared

    func makeView(size: CGSize) -> AnyView {
        AnyView(CalendarView(store: store).frame(width: size.width, height: size.height))
    }

    func makeSettingsView() -> AnyView { AnyView(CalendarModuleSettings(store: store)) }

    func activate() {}
    func deactivate() {}
}
