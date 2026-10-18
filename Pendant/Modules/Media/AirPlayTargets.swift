import Foundation
import IOKit.ps

/// An AirPlay device as Apple Music lists it (HomePod, speakers, Apple TV, "this computer").
struct AirPlayTarget: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case computer, airPlay, bluetooth }

    /// 1-based position in Music's `AirPlay devices` list; used to select it (no user text in scripts).
    let index: Int
    let name: String
    var isSelected: Bool
    /// The device's own volume, 0–100 (nil if Music does not report one).
    var volume: Int?
    var kind: Kind = .airPlay
    var supportsVideo = false
    var id: Int { index }

    /// SF Symbol that fits the device: Mac, HomePod (mini), Apple TV, AirPods / earbuds, headphones, speaker.
    var symbolName: String {
        let lower = name.lowercased()
        switch kind {
        case .computer: return MacHardware.symbolName
        case .bluetooth:
            if lower.contains("airpods pro") { return "airpodspro" }
            if lower.contains("airpods") { return lower.contains("max") ? "airpodsmax" : "airpods" }
            if lower.contains("buds") || lower.contains("耳機") { return "earbuds" }
            return "headphones"
        case .airPlay:
            if lower.contains("homepod mini") { return "homepodmini.fill" }
            if lower.contains("homepod") { return "homepod.fill" }
            if lower.contains("apple tv") || supportsVideo { return "appletv.fill" }
            return "homepodmini.fill" // an audio-only AirPlay target is almost always a HomePod / smart speaker
        }
    }
}

/// Laptop or desktop symbol for "this Mac".
enum MacHardware {
    static let symbolName: String = {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return "desktopcomputer" }
        let hasBattery = list.contains { source in
            let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
            return description?[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }
        return hasBattery ? "laptopcomputer" : "desktopcomputer"
    }()
}

enum AirPlayTargetParser {
    /// Each entry looks like `Name|true|true`, `Name|true|true|55` or `Name|true|true|55|kind|video`
    /// (name, selected, available[, volume[, kind, supports video]]). Names may contain "|".
    static func parse(_ entries: [String]) -> [AirPlayTarget] {
        entries.enumerated().compactMap { offset, entry in
            var parts = entry.components(separatedBy: "|")
            var kind = AirPlayTarget.Kind.airPlay
            var video = false
            if parts.count >= 6, ["true", "false"].contains(parts[parts.count - 1].lowercased()) {
                video = parts[parts.count - 1].lowercased() == "true"
                let rawKind = parts[parts.count - 2].lowercased()
                kind = rawKind.contains("comp") ? .computer : (rawKind.contains("blue") ? .bluetooth : .airPlay)
                parts.removeLast(2)
            }
            var volume: Int?
            if parts.count >= 4, let value = Int(parts[parts.count - 1].trimmingCharacters(in: .whitespaces)) {
                volume = min(max(value, 0), 100)
                parts.removeLast()
            }
            guard parts.count >= 3 else { return nil }
            let available = parts[parts.count - 1].lowercased() == "true"
            let selected = parts[parts.count - 2].lowercased() == "true"
            let name = parts.dropLast(2).joined(separator: "|")
            guard available || selected, !name.isEmpty else { return nil }
            return AirPlayTarget(index: offset + 1, name: name, isSelected: selected, volume: volume,
                                 kind: kind, supportsVideo: video)
        }
    }
}
