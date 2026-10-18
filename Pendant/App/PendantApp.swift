import SwiftUI

@main
struct PendantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        LegacyDefaultsMigration.run() // before anything reads a setting
    }

    var body: some Scene {
        // A scene is required; the real settings window is `SettingsWindowController` (AppKit).
        Settings { EmptyView() }
    }
}
