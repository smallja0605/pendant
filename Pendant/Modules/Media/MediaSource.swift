import AppKit

enum MediaCommand: Sendable {
    case playPause, next, previous
}

/// A music player the capsule can show and control.
@MainActor
protocol MediaSource: AnyObject {
    var id: MediaSourceID { get }
    /// Called with every state change. A `.stopped` snapshot means "nothing to show".
    var onSnapshot: ((PlaybackSnapshot) -> Void)? { get set }
    /// Called when Automation permission is learned (for the permission guide).
    var onPermission: ((AutomationStatus) -> Void)? { get set }

    func start()
    func stop()
    /// Asks the player for its full state (used on launch and when the capsule opens).
    func refresh()
    func send(_ command: MediaCommand)
    func seek(to seconds: TimeInterval)
    func setVolume(_ volume: Double)
    func volume() async -> Double?
    func artwork(for snapshot: PlaybackSnapshot) async -> Data?
    /// AirPlay devices the player itself offers (Apple Music only; empty otherwise).
    func airPlayTargets() async -> [AirPlayTarget]
    func selectAirPlayTarget(index: Int)
    /// Several devices at once (Music plays to all of them).
    func selectAirPlayTargets(indexes: [Int])
    func setAirPlayVolume(index: Int, percent: Int)
}

extension MediaSource {
    func airPlayTargets() async -> [AirPlayTarget] { [] }
    func selectAirPlayTarget(index: Int) {}
    func selectAirPlayTargets(indexes: [Int]) {}
    func setAirPlayVolume(index: Int, percent: Int) {}
}
