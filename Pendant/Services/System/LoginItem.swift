import ServiceManagement

/// "Launch at login" through `SMAppService.mainApp` (requirements 7.1).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error description when the system refuses (e.g. app not in /Applications, unsigned).
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
}
