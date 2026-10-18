import Foundation

/// Hides macOS's own volume / brightness pop-up (`OSDUIHelper`, an on-demand helper the system starts when a media key is
/// pressed) so only the notch HUD shows: the helper is simply stopped as soon as a change is noticed, and the system starts it
/// again the next time it is needed. A fixed command with fixed arguments (no shell, nothing user-supplied), no permission.
enum SystemHUDBlocker {
    private nonisolated(unsafe) static var lastRun = Date.distantPast

    static func suppress() {
        let now = Date()
        guard now.timeIntervalSince(lastRun) > 0.05 else { return }
        lastRun = now
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            process.arguments = ["-x", "OSDUIHelper"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}
