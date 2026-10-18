import AppKit
import Observation
import SwiftUI

/// Aggregates the players into one "now playing" state for the capsule (compact + expanded).
@MainActor
@Observable
final class MediaController {
    private(set) var nowPlaying: NowPlaying?
    private(set) var artwork: NSImage?
    /// Counts track changes (not the first track after nothing played): the compact capsule shows the song line for each.
    private(set) var trackChangeToken = 0
    private(set) var artworkColor: Color?
    /// True when Automation permission was refused for the player currently shown.
    private(set) var automationDenied = false
    /// Number of popovers currently shown; the capsule stays open while any is.
    private(set) var openPopoverCount = 0
    var isPopoverOpen: Bool { openPopoverCount > 0 }

    var preference: MediaSourcePreference { AppSettings.shared.mediaSourcePreference }
    var showsArtworkGlow: Bool { AppSettings.shared.artworkGlow }

    /// A setting that changes which player is shown (or how) changed: re-evaluate.
    func settingsChanged() { reselect(now: Date()) }

    @ObservationIgnored private let sources: [MediaSourceID: any MediaSource]
    @ObservationIgnored private var states: [MediaSourceID: PlaybackSnapshot] = [:]
    @ObservationIgnored private var lastChange: [MediaSourceID: Date] = [:]
    @ObservationIgnored private var denied: Set<MediaSourceID> = []
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    /// After our own play/pause the player may still report the old state once; ignore that echo.
    @ObservationIgnored private var pendingToggle: PendingToggle?

    private struct PendingToggle {
        var source: MediaSourceID
        var expected: PlaybackState
        var until: Date
    }
    @ObservationIgnored private let runner = AppleScriptRunner.shared

    init(sources: [any MediaSource]) {
        self.sources = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
    }

    @ObservationIgnored private var started = false
    /// While a simulated track is shown (settings → 模擬觸發) the real players' reports are ignored.
    @ObservationIgnored private var simulatedUntil = Date.distantPast

    func start() {
        guard !started else { return }
        started = true
        for source in sources.values {
            let id = source.id
            source.onSnapshot = { [weak self] snapshot in self?.handle(snapshot) }
            source.onPermission = { [weak self] status in self?.permissionChanged(id, status) }
            source.start()
        }
    }

    func stop() {
        guard started else { return }
        started = false
        sources.values.forEach { $0.stop() }
        artworkTask?.cancel()
        states.removeAll()
        clear()
    }

    /// Called when the capsule opens: re-syncs position (drift) and retries missing artwork.
    func refresh() {
        guard let nowPlaying else { return }
        sources[nowPlaying.source]?.refresh()
        if artwork == nil { loadArtwork(for: nowPlaying.snapshot) }
    }

    // MARK: State

    private func permissionChanged(_ id: MediaSourceID, _ status: AutomationStatus) {
        if status == .denied { denied.insert(id) } else if status == .allowed { denied.remove(id) }
        automationDenied = nowPlaying.map { denied.contains($0.source) } ?? false
    }

    func handle(_ incoming: PlaybackSnapshot) {
        let now = Date()
        guard now > simulatedUntil else { return }
        var snapshot = incoming
        if let pending = pendingToggle {
            if now > pending.until || snapshot.source != pending.source || snapshot.state == .stopped {
                pendingToggle = nil
            } else if snapshot.state == pending.expected {
                pendingToggle = nil
            } else {
                snapshot.state = pending.expected // stale echo of the previous state: keep the optimistic one
            }
        }
        if snapshot.state == .stopped {
            states.removeValue(forKey: snapshot.source)
        } else {
            states[snapshot.source] = snapshot
        }
        lastChange[snapshot.source] = now
        reselect(now: now)
    }

    private func reselect(now: Date) {
        let picked = MediaArbiter.pick(
            states: states.mapValues(\.state),
            current: nowPlaying?.source,
            lastChange: lastChange,
            preference: preference
        )
        guard let picked, let snapshot = states[picked] else {
            clear()
            return
        }

        let previous = nowPlaying
        let trackChanged = previous?.snapshot.trackKey != snapshot.trackKey || previous?.source != snapshot.source
        let anchor: TimeInterval?
        if let reported = snapshot.position {
            anchor = reported
        } else if trackChanged {
            anchor = snapshot.state == .playing ? 0 : nil
        } else {
            anchor = previous?.position(at: now)
        }
        nowPlaying = NowPlaying(snapshot: snapshot, anchorPosition: anchor, anchorDate: snapshot.receivedAt)
        automationDenied = denied.contains(picked)

        if trackChanged {
            if previous != nil { trackChangeToken += 1 }
            // The old cover stays until the new one is ready (or turns out to be missing): no placeholder flash while
            // skipping tracks, the cover view animates the swap.
            if now > simulatedUntil { loadArtwork(for: snapshot) }
        }
    }

    /// Nothing is playing: drop every trace of the previous track.
    private func clear() {
        artworkTask?.cancel()
        nowPlaying = nil
        artwork = nil
        artworkColor = nil
        automationDenied = false
    }

    // MARK: Artwork (retried for a few seconds: Apple Music often has none for the first track)

    private func loadArtwork(for snapshot: PlaybackSnapshot) {
        artworkTask?.cancel()
        guard let source = sources[snapshot.source] else { return }
        let useCache = AppSettings.shared.artworkCache
        artworkTask = Task { [weak self] in
            // A track seen before: its cover is applied at once, no lookup at all.
            if useCache, let cached = await ArtworkCache.shared.load(snapshot.trackKey),
               let decoded = await Task.detached(priority: .userInitiated, operation: { DecodedArtwork(cached) }).value,
               !Task.isCancelled {
                self?.applyArtwork(decoded, trackKey: snapshot.trackKey)
                return
            }
            // Skipping through tracks quickly only asks for the cover of the one it lands on.
            try? await Task.sleep(for: .seconds(0.15))
            for (attempt, delay) in [0.0, 0.8, 2.0, 4.0, 7.0].enumerated() {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, self?.nowPlaying?.snapshot.trackKey == snapshot.trackKey else { return }
                if let data = await source.artwork(for: snapshot),
                   let decoded = await Task.detached(priority: .userInitiated, operation: { DecodedArtwork(data) }).value {
                    self?.applyArtwork(decoded, trackKey: snapshot.trackKey)
                    if useCache { await ArtworkCache.shared.store(data, for: snapshot.trackKey) }
                    return
                }
                // The first attempt found nothing: the previous track's cover must not stay on this one.
                if attempt == 0, self?.nowPlaying?.snapshot.trackKey == snapshot.trackKey {
                    self?.artwork = nil
                    self?.artworkColor = nil
                }
            }
        }
    }

    private func applyArtwork(_ decoded: DecodedArtwork, trackKey: String) {
        guard nowPlaying?.snapshot.trackKey == trackKey else { return }
        artwork = decoded.image
        artworkColor = decoded.color
    }

    /// Brings the player app forward (click on the cover in the expanded capsule).
    func openPlayerApp() {
        guard let source = nowPlaying?.source,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func popoverVisibilityChanged(_ shown: Bool) {
        openPopoverCount = max(openPopoverCount + (shown ? 1 : -1), 0)
    }

    // MARK: Outputs (AirPlay targets from Apple Music + CoreAudio output devices)

    struct Outputs: Equatable {
        var airPlay: [AirPlayTarget] = []
        var devices: [AudioOutputDevice] = []
    }

    func loadOutputs() async -> Outputs {
        var outputs = Outputs(devices: AudioOutputDevices.list())
        if let source = sources[.appleMusic], states[.appleMusic] != nil || nowPlaying?.source == .appleMusic {
            outputs.airPlay = await source.airPlayTargets()
        }
        return outputs
    }

    func selectAirPlay(_ target: AirPlayTarget) {
        sources[.appleMusic]?.selectAirPlayTarget(index: target.index)
    }

    /// Plays to exactly these AirPlay devices (1-based Music indexes).
    func setAirPlayTargets(_ indexes: [Int]) {
        sources[.appleMusic]?.selectAirPlayTargets(indexes: indexes)
    }

    func setAirPlayVolume(_ index: Int, percent: Int) {
        sources[.appleMusic]?.setAirPlayVolume(index: index, percent: percent)
    }

    func selectOutput(_ device: AudioOutputDevice) {
        AudioOutputDevices.setDefault(device.id)
    }

    // MARK: Controls (optimistic UI update, then the real notification confirms)

    func togglePlayPause() {
        guard var current = nowPlaying else { return }
        let now = Date()
        let position = current.position(at: now)
        current.snapshot.state = current.isPlaying ? .paused : .playing
        current.anchorPosition = current.hasKnownPosition ? position : nil
        current.anchorDate = now
        nowPlaying = current
        states[current.source]?.state = current.snapshot.state
        pendingToggle = PendingToggle(source: current.source, expected: current.snapshot.state, until: now.addingTimeInterval(1.2))
        sources[current.source]?.send(.playPause)
    }

    func next() {
        guard let source = nowPlaying?.source else { return }
        sources[source]?.send(.next)
    }

    func previous() {
        guard let source = nowPlaying?.source else { return }
        sources[source]?.send(.previous)
    }

    func seek(to seconds: TimeInterval) {
        guard var current = nowPlaying else { return }
        let clamped = min(max(seconds, 0), current.snapshot.duration > 0 ? current.snapshot.duration : seconds)
        current.anchorPosition = clamped
        current.anchorDate = Date()
        nowPlaying = current
        sources[current.source]?.seek(to: clamped)
    }

    /// App volume for Apple Music / Spotify; falls back to the system output volume.
    func volume() async -> Double {
        if let source = nowPlaying?.source, let value = await sources[source]?.volume() { return value }
        if case let .success(value) = await runner.run("output volume of (get volume settings)"),
           let percent = value.asDouble { return min(max(percent / 100, 0), 1) }
        return 0.5
    }

    func setVolume(_ volume: Double) {
        let clamped = min(max(volume, 0), 1)
        if let source = nowPlaying?.source, !automationDenied {
            sources[source]?.setVolume(clamped)
        } else {
            let percent = Int((clamped * 100).rounded())
            Task { _ = await runner.run("set volume output volume \(percent)") }
        }
    }

    /// Shows a made-up track without any player (the settings' simulation panel and PENDANT_DEBUG_MEDIA); the next real
    /// report from a player replaces it.
    func simulate(title: String, artist: String, album: String = "", playing: Bool, key: String, colors: [NSColor]) {
        let snapshot = PlaybackSnapshot(
            source: .appleMusic, state: playing ? .playing : .paused, title: title, album: album, artist: artist,
            duration: 202, position: 0, trackKey: key, receivedAt: Date()
        )
        simulatedUntil = Date().addingTimeInterval(120)
        states[.appleMusic] = snapshot
        lastChange[.appleMusic] = Date()
        reselect(now: Date())
        let size = NSSize(width: 300, height: 300)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: colors)?.draw(in: rect, angle: 45)
            return true
        }
        applyArtwork(DecodedArtwork(image: image), trackKey: key)
    }

    /// Drops the simulated track and lets the real players speak again.
    func endSimulation() {
        guard simulatedUntil > Date() else { return }
        simulatedUntil = .distantPast
        states.removeValue(forKey: .appleMusic)
        lastChange.removeValue(forKey: .appleMusic)
        reselect(now: Date())
        sources.values.forEach { $0.refresh() }
    }

    #if DEBUG
    func debugInject(playing: Bool) {
        simulate(title: "歌曲名稱", artist: "歌手名稱", album: "專輯名稱",
                 playing: playing, key: "debug", colors: [.systemPink, .systemOrange, .systemPurple])
    }
    #endif
}
