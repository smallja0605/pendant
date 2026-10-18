import AVFoundation
import EventKit
import Foundation

enum PermissionState: Equatable, Sendable {
    case allowed, notDetermined, denied
    /// The target app is not running, so macOS cannot tell (Automation only).
    case unknown
}

enum PermissionKind: String, CaseIterable, Identifiable, Sendable {
    case calendars, reminders, camera, automationMusic, automationSpotify
    var id: String { rawValue }

    var settingsPane: String {
        switch self {
        case .calendars: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .camera: "Privacy_Camera"
        case .automationMusic, .automationSpotify: "Privacy_Automation"
        }
    }
}

/// Reads and requests the permissions the modules need (requirements 7.8). Nothing is requested at launch:
/// requests happen only when the user presses the button here or first uses a module.
@MainActor
enum PermissionsService {
    static func state(for kind: PermissionKind) async -> PermissionState {
        switch kind {
        case .calendars: return map(EKEventStore.authorizationStatus(for: .event))
        case .reminders: return map(EKEventStore.authorizationStatus(for: .reminder))
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: return .allowed
            case .notDetermined: return .notDetermined
            default: return .denied
            }
        case .automationMusic: return await automation(.appleMusic, ask: false)
        case .automationSpotify: return await automation(.spotify, ask: false)
        }
    }

    static func request(_ kind: PermissionKind) async {
        switch kind {
        case .calendars: _ = try? await EKEventStore().requestFullAccessToEvents()
        case .reminders: _ = try? await EKEventStore().requestFullAccessToReminders()
        case .camera: _ = await AVCaptureDevice.requestAccess(for: .video)
        case .automationMusic: _ = await automation(.appleMusic, ask: true)
        case .automationSpotify: _ = await automation(.spotify, ask: true)
        }
    }

    private static func automation(_ source: MediaSourceID, ask: Bool) async -> PermissionState {
        switch await AppleScriptRunner.shared.automationStatus(bundleIdentifier: source.bundleIdentifier, ask: ask) {
        case .allowed: .allowed
        case .denied: .denied
        case .notDetermined: .notDetermined
        case .notRunning: .unknown
        }
    }

    private static func map(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess: .allowed
        case .notDetermined: .notDetermined
        default: .denied // denied, restricted, write-only
        }
    }
}
