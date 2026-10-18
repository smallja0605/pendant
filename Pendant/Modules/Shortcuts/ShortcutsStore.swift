import Foundation
import Observation

/// The user's Shortcuts (Shortcuts.app) through the `shortcuts` command line tool: list them and run one by name.
/// The tool is started with an argument array (no shell), and names are never logged.
@MainActor
@Observable
final class ShortcutsStore {
    static let shared = ShortcutsStore()
    private static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    enum RunState: Equatable { case running, done, failed }

    private(set) var names: [String] = []
    private(set) var isLoading = false
    private(set) var loaded = false
    private(set) var states: [String: RunState] = [:]

    var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: Self.tool.path) }

    func visibleNames(hidden: [String]) -> [String] { names.filter { !hidden.contains($0) } }

    func refresh() {
        guard isAvailable, !isLoading else { return }
        isLoading = true
        Task {
            let output = await Self.runTool(["list"])
            names = (output ?? "").split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            isLoading = false
            loaded = true
        }
    }

    func run(_ name: String) {
        guard states[name] != .running else { return }
        states[name] = .running
        Task {
            let output = await Self.runTool(["run", name])
            states[name] = output == nil ? .failed : .done
            try? await Task.sleep(for: .seconds(1.6))
            if states[name] != .running { states[name] = nil }
        }
    }

    /// Runs the tool off the main thread; nil when it failed to start or exited with an error.
    private nonisolated static func runTool(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = tool
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0 ? String(bytes: data, encoding: .utf8) ?? "" : nil)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
