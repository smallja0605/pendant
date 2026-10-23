import Foundation
import os

/// Central loggers. Never log user content (song titles, notes, event titles, calendar names).
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.smallja.pendant"
    static let app = Logger(subsystem: subsystem, category: "app")
    #if DEBUG
    private static let traceLogger = Logger(subsystem: subsystem, category: "trace")
    #endif

    /// The names of the few functions that called this one (function names only, never user content): for logging why something closed.
    static func callers(_ count: Int = 5) -> String {
        Thread.callStackSymbols.dropFirst(2).prefix(count).map { line in
            line.split(separator: " ", maxSplits: 3).last.map(String.init) ?? ""
        }.joined(separator: " <- ")
    }

    /// The open capsule is closing (state names and function names only): for finding out why it closed.
    static func collapsed(to state: CapsuleState) {
        app.info("capsule closed to \(String(describing: state), privacy: .public), from: \(callers(), privacy: .public)")
    }

    /// Interaction trace (debug builds only): state names and geometry numbers, never user content.
    /// Read with: log show --last 1m --predicate 'subsystem == "com.smallja.pendant" AND category == "trace"'
    static func trace(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        traceLogger.notice("\(text, privacy: .public)")
        #endif
    }
}
