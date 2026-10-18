import SwiftUI

/// Allowed / default width of a module, measured in grid cells.
struct CellRange: Equatable, Sendable {
    var `default`: Int
    var range: ClosedRange<Int>
}

/// Permissions a module may need. Requested lazily on first use, never at launch.
enum PendantPermission: String, Sendable, CaseIterable {
    case calendars, reminders, camera, automation
}

/// Whether an island is the main one (next to the notch) or a secondary one.
enum IslandRole: Sendable { case main, secondary }

/// Abstraction for every feature module (media, notes, ...). See requirements 4.x.
@MainActor
protocol PendantModule: AnyObject, Identifiable where ID == String {
    var id: String { get }
    var displayName: String { get }
    var symbolName: String { get }
    var cells: CellRange { get }
    var supportsCompact: Bool { get }
    var requiredPermissions: [PendantPermission] { get }
    var isEnabled: Bool { get set }

    /// Default level among the live activities (lower = higher level); the user's order in settings wins.
    var activityPriority: Int { get }

    func makeView(size: CGSize) -> AnyView
    /// The module's own, more detailed page, shown alone in a wider capsule (nil: its normal page, wider).
    func makeFocusView(size: CGSize) -> AnyView?
    /// Width of that page in cells.
    var focusCells: Int { get }
    /// Content of this module's island while it is a live activity (3.5). `nil`: the generic icon is used.
    func makeCompactView(role: IslandRole) -> AnyView?
    func makeSettingsView() -> AnyView

    /// Start listening / allocate resources. Called when the module becomes enabled.
    func activate()
    /// Stop listening and release resources. Called when the module is disabled.
    func deactivate()
}

extension PendantModule {
    var supportsCompact: Bool { false }
    func makeFocusView(size: CGSize) -> AnyView? { nil }
    var focusCells: Int { min(cells.default + 4, 10) }
    var activityPriority: Int { 100 }
    func makeCompactView(role: IslandRole) -> AnyView? { nil }
    var requiredPermissions: [PendantPermission] { [] }
    func makeSettingsView() -> AnyView { AnyView(ModuleForm(moduleID: id) {}) }
}
