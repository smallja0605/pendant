import Foundation
import os

/// Central loggers. Never log user content (song titles, notes, event titles, calendar names).
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.smallja.pendant"
    static let app = Logger(subsystem: subsystem, category: "app")
    #if DEBUG
    private static let traceLogger = Logger(subsystem: subsystem, category: "trace")
    #endif

    /// Interaction trace (debug builds only): state names and geometry numbers, never user content.
    /// Read with: log show --last 1m --predicate 'subsystem == "com.smallja.pendant" AND category == "trace"'
    static func trace(_ message: @autoclosure () -> String) {
        #if DEBUG
        let text = message()
        traceLogger.notice("\(text, privacy: .public)")
        #endif
    }
}
