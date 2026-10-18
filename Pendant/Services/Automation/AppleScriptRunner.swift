import AppKit
import CoreServices

/// Plain-data result of an AppleScript run, so it can cross concurrency domains.
enum ScriptValue: Sendable, Equatable {
    case none
    case text(String)
    case list([ScriptValue])

    var asDouble: Double? {
        guard case let .text(raw) = self else { return nil }
        return Double(raw.replacingOccurrences(of: ",", with: "."))
    }

    var asString: String? {
        guard case let .text(raw) = self else { return nil }
        return raw
    }
}

struct ScriptFailure: Error, Sendable, Equatable {
    /// `NSAppleScriptErrorNumber` (e.g. -1743 = not authorised, -600 = application not running).
    let code: Int
}

enum AutomationStatus: Sendable, Equatable {
    case allowed, denied, notDetermined, notRunning
}

/// Runs AppleScript on one serial queue (NSAppleScript is not thread-safe).
/// Only static, app-authored script text is ever passed in; user content (titles, notes) is never
/// interpolated into scripts. Numeric arguments are formatted by the caller.
final class AppleScriptRunner: @unchecked Sendable {
    static let shared = AppleScriptRunner()
    private let queue = DispatchQueue(label: "com.smallja.pendant.applescript", qos: .userInitiated)

    func run(_ source: String) async -> Result<ScriptValue, ScriptFailure> {
        await withCheckedContinuation { continuation in
            queue.async {
                var errorInfo: NSDictionary?
                let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? -1
                    continuation.resume(returning: .failure(ScriptFailure(code: code)))
                } else {
                    continuation.resume(returning: .success(Self.convert(descriptor)))
                }
            }
        }
    }

    /// For scripts that return binary data (artwork). Returns nil on any failure or empty result.
    func runData(_ source: String) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                var errorInfo: NSDictionary?
                let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
                guard errorInfo == nil, let data = descriptor?.data, !data.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    /// Checks (and, with `ask`, may prompt for) permission to send Apple events to an app.
    func automationStatus(bundleIdentifier: String, ask: Bool) async -> AutomationStatus {
        await withCheckedContinuation { continuation in
            queue.async {
                let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
                guard let desc = target.aeDesc else {
                    continuation.resume(returning: .notRunning)
                    return
                }
                let status = AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask)
                let mapped: AutomationStatus = switch Int(status) {
                case 0: .allowed
                case -1743: .denied
                case -1744: .notDetermined
                default: .notRunning
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    private static func convert(_ descriptor: NSAppleEventDescriptor?) -> ScriptValue {
        guard let descriptor else { return .none }
        if descriptor.descriptorType == typeAEList {
            let items = (0..<descriptor.numberOfItems).compactMap { index in
                descriptor.atIndex(index + 1).map(convert)
            }
            return .list(items)
        }
        if let text = descriptor.stringValue { return .text(text) }
        return .none
    }
}
