import AppKit

/// Quitting and restarting the app itself.
@MainActor
enum AppControl {
    static func quit() {
        NSApp.terminate(nil)
    }

    /// Starts a second instance of this app and quits the current one once it is up (the settings window comes back with it).
    static func restart() {
        SettingsWindowController.shared.rememberForRestart()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
