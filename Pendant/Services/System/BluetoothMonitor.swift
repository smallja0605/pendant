import Foundation
import IOBluetooth
import ObjectiveC

/// The device object travels from IOBluetooth's queue to the main actor; it is only read there.
private struct UncheckedDevice: @unchecked Sendable {
    let device: IOBluetoothDevice
}

/// A Bluetooth device that just connected.
struct BluetoothConnection: Equatable, Sendable {
    var name: String
    var symbol: String
    var battery: Int?
    /// The level is the one seen the last time this device was connected (the system gave none this time).
    var isLastKnown = false
}

/// Reports Bluetooth devices (headphones, mice, keyboards…) as they connect, with their name, a symbol for their kind and — when
/// the system knows it — their battery level. Only changes are reported: devices that are already connected at launch are not.
@MainActor
final class BluetoothMonitor: NSObject {
    /// Called the moment a device connects (no battery yet), and once more when its battery level / kind is known.
    var onConnect: ((BluetoothConnection) -> Void)?
    var onDetails: ((BluetoothConnection) -> Void)?

    private var registration: IOBluetoothUserNotification?
    private var startedAt = Date.distantFuture
    private var starting = false
    private var lastReported: [String: Date] = [:]

    func start() {
        guard registration == nil, !starting else { return }
        // Not under the test runner (the permission question would block it), and not before the app has finished launching.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        starting = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, starting, registration == nil else { return }
            starting = false
            startedAt = Date()
            registration = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
        }
    }

    func stop() {
        starting = false
        registration?.unregister()
        registration = nil
    }

    /// IOBluetooth calls this on its own queue (not the main actor's, which the class would trap on): hop to the main actor first.
    @objc private nonisolated func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let box = UncheckedDevice(device: device)
        Task { @MainActor [weak self] in self?.handleConnect(box.device) }
    }

    private func handleConnect(_ device: IOBluetoothDevice) {
        // The registration can replay devices that are already connected right after it is made.
        guard Date().timeIntervalSince(startedAt) > 3, let name = device.name, !name.isEmpty else { return }
        let address = device.addressString ?? ""
        #if DEBUG
        Self.debugDump(device)
        #endif
        let major = device.deviceClassMajor, minor = device.deviceClassMinor
        // The card must not wait for the battery: show it at once, fill the level in when it is known.
        let firstSymbol = Self.symbol(name: name, major: major, minor: minor, profileType: nil)
        // The device's own level is there the moment it connects (the system also sends this notification twice, a few ms apart).
        guard Date().timeIntervalSince(lastReported[name] ?? .distantPast) > 2 else { return }
        lastReported[name] = Date()
        let fresh = Self.battery(of: device)
        if let fresh { Self.remember(fresh, for: address) }
        let remembered = fresh == nil ? Self.remembered(for: address) : nil
        let first = BluetoothConnection(name: name, symbol: firstSymbol, battery: fresh ?? remembered, isLastKnown: remembered != nil)
        onConnect?(first)
        Task { @MainActor [weak self] in
            // The level is 0 when the device connects and shows up a little later: look again for a few seconds, then ask
            // `system_profiler` once (it knows the level of some devices the property does not).
            var battery = fresh
            for _ in 0..<16 where battery == nil {
                try? await Task.sleep(for: .milliseconds(500))
                battery = Self.battery(of: device)
            }
            if battery == nil {
                let profile = await Self.profile(named: name, address: address)
                battery = profile?.battery
                let symbol = Self.symbol(name: name, major: major, minor: minor, profileType: profile?.type)
                if let level = battery { Self.remember(level, for: address) }
                let shown = battery ?? remembered
                let details = BluetoothConnection(name: name, symbol: symbol, battery: shown, isLastKnown: battery == nil && shown != nil)
                if details != first { self?.onDetails?(details) }
            } else if let level = battery {
                Self.remember(level, for: address)
                self?.onDetails?(BluetoothConnection(name: name, symbol: first.symbol, battery: level))
            }
        }
    }

    // MARK: Last known level

    private static let rememberedKey = "bluetoothLastBattery"

    private static func remember(_ level: Int, for address: String) {
        guard !address.isEmpty else { return }
        var levels = UserDefaults.standard.dictionary(forKey: rememberedKey) as? [String: Int] ?? [:]
        levels[address] = level
        UserDefaults.standard.set(levels, forKey: rememberedKey)
    }

    private static func remembered(for address: String) -> Int? {
        (UserDefaults.standard.dictionary(forKey: rememberedKey) as? [String: Int])?[address]
    }

    #if DEBUG
    /// PENDANT_DEBUG_BT=<file>: writes when a device connected and every battery-like property it has (to find where a level lives).
    private static func debugDump(_ device: IOBluetoothDevice) {
        guard let path = ProcessInfo.processInfo.environment["PENDANT_DEBUG_BT"] else { return }
        var lines = ["\(Date().timeIntervalSince1970) connected \(device.name ?? "?")"]
        var count: UInt32 = 0
        var classType: AnyClass? = type(of: device)
        while let current = classType, current != NSObject.self {
            if let list = class_copyPropertyList(current, &count) {
                for index in 0..<Int(count) {
                    let name = String(cString: property_getName(list[index]))
                    guard name.lowercased().contains("batt") else { continue }
                    lines.append("  \(name) = \(String(describing: device.value(forKey: name)))")
                }
                free(list)
            }
            classType = class_getSuperclass(current)
        }
        try? (lines.joined(separator: "\n") + "\n").appendingToFile(path)
        // Does the level ever show up, and only on a freshly made object?
        let address = device.addressString ?? ""
        Task { @MainActor in
            for second in 1...12 {
                try? await Task.sleep(for: .seconds(1))
                let fresh = IOBluetoothDevice(addressString: address)
                let old = (device.value(forKey: "batteryPercentSingle") as? Int) ?? -1
                let new = (fresh?.value(forKey: "batteryPercentSingle") as? Int) ?? -1
                try? "  +\(second)s old=\(old) fresh=\(new)\n".appendingToFile(path)
            }
        }
    }
    #endif

    // MARK: Kind

    // swiftlint:disable:next cyclomatic_complexity
    static func symbol(name: String, major: UInt32, minor: UInt32, profileType: String?) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods max") { return "airpods.max" }
        if lower.contains("airpods") { return "airpods" }
        let type = (profileType ?? "").lowercased()
        if lower.contains("trackpad") || type.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if lower.contains("mouse") || lower.contains("滑鼠") || type.contains("mouse") { return "computermouse.fill" }
        if lower.contains("keyboard") || lower.contains("鍵盤") || type.contains("keyboard") { return "keyboard.fill" }
        if type.contains("headphone") || type.contains("headset") { return "headphones" }
        if type.contains("speaker") { return "hifispeaker.fill" }
        if type.contains("gamepad") || type.contains("controller") { return "gamecontroller.fill" }
        switch major {
        case 4: // audio / video
            switch minor {
            case 5, 7, 8: return "hifispeaker.fill"
            case 4: return "mic.fill"
            default: return "headphones"
            }
        case 5: // peripheral: bits 6–7 say keyboard / pointing device
            switch minor & 0xC0 {
            case 0x40: return "keyboard.fill"
            case 0x80, 0xC0: return "computermouse.fill"
            default: return "gamecontroller.fill"
            }
        case 2: return "iphone"
        case 1: return "laptopcomputer"
        case 7: return "applewatch"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    // MARK: Battery

    /// The level the device reports itself (private properties, read only when they exist).
    private static func battery(of device: IOBluetoothDevice) -> Int? {
        func value(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)), let number = device.value(forKey: key) as? NSNumber else { return nil }
            let level = number.intValue
            return (1...100).contains(level) ? level : nil
        }
        if let single = value("batteryPercentSingle") ?? value("batteryPercentCombined") { return single }
        let sides = [value("batteryPercentLeft"), value("batteryPercentRight")].compactMap { $0 }
        return sides.min()
    }

    struct Profile {
        var battery: Int?
        var type: String?
    }

    /// What `system_profiler` knows about a connected device (level and kind), found by address or name.
    private static func profile(named name: String, address: String) async -> Profile? {
        await Task.detached(priority: .utility) { () -> Profile? in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let blocks = root["SPBluetoothDataType"] as? [[String: Any]],
                  let connected = blocks.first?["device_connected"] as? [[String: [String: Any]]] else { return nil }
            let normalized = address.replacingOccurrences(of: "-", with: ":").lowercased()
            for entry in connected {
                for (deviceName, info) in entry {
                    let sameAddress = (info["device_address"] as? String)?.lowercased() == normalized
                    guard sameAddress || deviceName == name else { continue }
                    let levels = ["device_batteryLevelMain", "device_batteryLevelLeft", "device_batteryLevelRight"]
                        .compactMap { (info[$0] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
                    return Profile(battery: levels.min(), type: info["device_minorType"] as? String)
                }
            }
            return nil
        }.value
    }
}

#if DEBUG
private extension String {
    func appendingToFile(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(utf8))
            try handle.close()
        } else {
            try write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#endif
