import Foundation
import IOBluetooth

/// A Bluetooth device that just connected.
struct BluetoothConnection: Equatable, Sendable {
    var name: String
    var symbol: String
    var battery: Int?
}

/// Reports Bluetooth devices (headphones, mice, keyboards…) as they connect, with their name, a symbol for their kind and — when
/// the system knows it — their battery level. Only changes are reported: devices that are already connected at launch are not.
@MainActor
final class BluetoothMonitor: NSObject {
    var onConnect: ((BluetoothConnection) -> Void)?

    private var registration: IOBluetoothUserNotification?
    private var startedAt = Date.distantFuture
    private var starting = false

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

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // The registration can replay devices that are already connected right after it is made.
        guard Date().timeIntervalSince(startedAt) > 3, let name = device.name, !name.isEmpty else { return }
        let address = device.addressString ?? ""
        let major = device.deviceClassMajor, minor = device.deviceClassMinor
        Task { @MainActor [weak self] in
            // The battery level is not known the moment a device connects.
            try? await Task.sleep(for: .seconds(1.5))
            var battery = Self.battery(of: device)
            var profile: Profile?
            if battery == nil {
                profile = await Self.profile(named: name, address: address)
                battery = profile?.battery
            }
            let symbol = Self.symbol(name: name, major: major, minor: minor, profileType: profile?.type)
            self?.onConnect?(BluetoothConnection(name: name, symbol: symbol, battery: battery))
        }
    }

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
