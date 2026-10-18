import Foundation
import IOKit.ps
import Observation

/// Charge of the internal battery (nil on a Mac without one), read from the system's power-source list. It refreshes when the
/// system reports a power-source change (plug / unplug / level steps) — no timer.
@MainActor
@Observable
final class BatteryMonitor {
    static let shared = BatteryMonitor()

    struct Reading: Equatable {
        var percent: Int
        var charging: Bool
        var pluggedIn: Bool
    }

    private(set) var reading: Reading?
    @ObservationIgnored private var source: CFRunLoopSource?

    func start() {
        guard source == nil else { return }
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let created = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        source = created
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
    }

    func refresh() {
        reading = Self.read()
    }

    private static func read() -> Reading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for item in list {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            return Reading(
                percent: min(max(Int((Double(current) / Double(maximum) * 100).rounded()), 0), 100),
                charging: charging, pluggedIn: state == kIOPSACPowerValue
            )
        }
        return nil
    }

    /// SF Symbol for a charge level.
    static func symbol(percent: Int) -> String {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}
