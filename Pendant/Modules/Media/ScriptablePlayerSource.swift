import AppKit

/// Apple Music / Spotify: state comes from the apps' distributed notifications (no permission
/// needed); position, artwork and control go through Apple events (Automation permission, asked once).
/// The app is only ever scripted while it is running, because `tell application` would launch it.
@MainActor
final class ScriptablePlayerSource: MediaSource {
    let id: MediaSourceID
    var onSnapshot: ((PlaybackSnapshot) -> Void)?
    var onPermission: ((AutomationStatus) -> Void)?

    private let runner = AppleScriptRunner.shared
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var permission: AutomationStatus = .notDetermined
    private var askedForPermission = false
    private var lastSnapshot: PlaybackSnapshot?

    init(id: MediaSourceID) {
        self.id = id
    }

    private var appName: String { id == .appleMusic ? "Music" : "Spotify" }
    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: id.bundleIdentifier).isEmpty
    }

    // MARK: Lifecycle

    func start() {
        let name = id == .appleMusic ? MediaNotificationParser.appleMusicNotification
                                     : MediaNotificationParser.spotifyNotification
        let distributed = DistributedNotificationCenter.default()
        let source = id
        observers.append((distributed, distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            let snapshot = MediaNotificationParser.parse(source: source, userInfo: note.userInfo)
            MainActor.assumeIsolated { self?.received(snapshot) }
        }))

        let workspace = NSWorkspace.shared.notificationCenter
        let bundle = id.bundleIdentifier
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let terminated = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard terminated == bundle else { return }
            MainActor.assumeIsolated { self?.playerQuit() }
        }))

        refresh()
    }

    func stop() {
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
    }

    // MARK: State

    private func received(_ snapshot: PlaybackSnapshot?) {
        guard let snapshot else { return }
        lastSnapshot = snapshot
        onSnapshot?(snapshot)
        guard snapshot.state != .stopped else { return }
        // Position / artwork need Automation: asked on first use, i.e. the first time something plays.
        Task { await refreshPositionIfAllowed(for: snapshot) }
    }

    private func playerQuit() {
        let stopped = PlaybackSnapshot(source: id, state: .stopped, title: "", album: "", artist: "",
                                       duration: 0, position: nil, trackKey: "", receivedAt: Date())
        lastSnapshot = stopped
        onSnapshot?(stopped)
    }

    func refresh() {
        guard isRunning else { return }
        Task { await fullRefresh() }
    }

    private func ensurePermission() async -> Bool {
        guard isRunning else { return false }
        if permission == .allowed { return true }
        if permission == .denied && askedForPermission { return false }
        let status = await runner.automationStatus(bundleIdentifier: id.bundleIdentifier, ask: !askedForPermission)
        askedForPermission = true
        permission = status
        onPermission?(status)
        return status == .allowed
    }

    private func fullRefresh() async {
        guard await ensurePermission() else { return }
        let script = id == .appleMusic ? Self.musicStateScript : Self.spotifyStateScript
        guard case let .success(.list(values)) = await runner.run(script), let state = values.first?.asString else { return }
        let playback = MediaNotificationParser.parseState(state)
        guard playback != .stopped, values.count >= 6 else {
            if lastSnapshot?.state != .stopped { playerQuit() }
            return
        }
        let title = values[1].asString ?? ""
        let artist = values[2].asString ?? ""
        let album = values[3].asString ?? ""
        let rawDuration = values[4].asDouble ?? 0
        let snapshot = PlaybackSnapshot(
            source: id, state: playback, title: title, album: album, artist: artist,
            duration: id == .spotify ? rawDuration / 1000 : rawDuration,
            position: values[5].asDouble,
            trackKey: id == .spotify ? (values.count > 7 ? (values[7].asString ?? "") : "") : "\(title)|\(artist)|\(album)",
            receivedAt: Date()
        )
        lastSnapshot = snapshot
        onSnapshot?(snapshot)
    }

    private func refreshPositionIfAllowed(for snapshot: PlaybackSnapshot) async {
        guard snapshot.position == nil, await ensurePermission() else { return }
        guard case let .success(value) = await runner.run("tell application \"\(appName)\" to return player position"),
              let position = value.asDouble,
              let latest = lastSnapshot, latest.trackKey == snapshot.trackKey else { return }
        var updated = latest
        updated.position = position
        updated.receivedAt = Date()
        lastSnapshot = updated
        onSnapshot?(updated)
    }

    // MARK: Control

    func send(_ command: MediaCommand) {
        switch command {
        case .playPause: runControl("tell application \"\(appName)\" to playpause")
        case .next: runControl("tell application \"\(appName)\" to next track")
        case .previous:
            // The player's own "previous" only restarts the song once it has played for a few seconds; rewinding to the start
            // first makes it always go to the previous song.
            runControl("""
            tell application "\(appName)"
                try
                    set player position to 0
                end try
                previous track
            end tell
            """)
        }
    }

    func seek(to seconds: TimeInterval) {
        runControl("tell application \"\(appName)\" to set player position to \(String(format: "%.2f", max(seconds, 0)))")
    }

    func setVolume(_ volume: Double) {
        let percent = Int((min(max(volume, 0), 1) * 100).rounded())
        runControl("tell application \"\(appName)\" to set sound volume to \(percent)")
    }

    func volume() async -> Double? {
        guard await ensurePermission(),
              case let .success(value) = await runner.run("tell application \"\(appName)\" to return sound volume"),
              let percent = value.asDouble else { return nil }
        return min(max(percent / 100, 0), 1)
    }

    private func runControl(_ script: String) {
        Task {
            guard await ensurePermission() else { return }
            _ = await runner.run(script)
        }
    }

    // MARK: AirPlay (Apple Music's own device list; selection by index, never by name)

    func airPlayTargets() async -> [AirPlayTarget] {
        guard id == .appleMusic, await ensurePermission(),
              case let .success(.list(values)) = await runner.run(Self.musicAirPlayScript) else { return [] }
        return AirPlayTargetParser.parse(values.compactMap(\.asString))
    }

    func selectAirPlayTarget(index: Int) {
        guard id == .appleMusic, index > 0 else { return }
        runControl("tell application \"Music\" to set current AirPlay devices to {AirPlay device \(index)}")
    }

    func selectAirPlayTargets(indexes: [Int]) {
        let valid = indexes.filter { $0 > 0 }
        guard id == .appleMusic, !valid.isEmpty else { return }
        let list = valid.map { "AirPlay device \($0)" }.joined(separator: ", ")
        runControl("tell application \"Music\" to set current AirPlay devices to {\(list)}")
    }

    func setAirPlayVolume(index: Int, percent: Int) {
        guard id == .appleMusic, index > 0 else { return }
        let value = min(max(percent, 0), 100)
        runControl("tell application \"Music\" to set sound volume of AirPlay device \(index) to \(value)")
    }

    // MARK: Artwork

    func artwork(for snapshot: PlaybackSnapshot) async -> Data? {
        guard await ensurePermission() else { return nil }
        switch id {
        case .appleMusic:
            if let data = await runner.runData(Self.musicArtworkScript) { return data }
            // Streamed ("URL") tracks have no artwork in AppleScript.
            guard AppSettings.shared.onlineArtwork else { return nil }
            return await CatalogArtworkFetcher.shared.fetch(title: snapshot.title, artist: snapshot.artist, album: snapshot.album)
        case .spotify:
            guard case let .success(value) = await runner.run(Self.spotifyArtworkURLScript),
                  let urlString = value.asString else { return nil }
            return await SpotifyArtworkFetcher.shared.fetch(urlString)
        }
    }

    // MARK: Scripts (static text only)

    private static let musicStateScript = """
    tell application "Music"
        set s to player state as text
        if s is "stopped" then return {s}
        set t to current track
        return {s, name of t, artist of t, album of t, duration of t, player position}
    end tell
    """

    private static let spotifyStateScript = """
    tell application "Spotify"
        set s to player state as text
        if s is "stopped" then return {s}
        set t to current track
        return {s, name of t, artist of t, album of t, duration of t, player position, "", id of t}
    end tell
    """

    private static let musicAirPlayScript = """
    tell application "Music"
        set out to {}
        repeat with d in (get AirPlay devices)
            set deviceVolume to 0
            try
                set deviceVolume to sound volume of d
            end try
            set deviceKind to "airplay"
            set deviceVideo to false
            try
                set deviceKind to (kind of d) as text
            end try
            try
                set deviceVideo to supports video of d
            end try
            set flags to ((selected of d) as text) & "|" & ((available of d) as text)
            set end of out to (name of d) & "|" & flags & "|" & (deviceVolume as text) & "|" & deviceKind & "|" & (deviceVideo as text)
        end repeat
        return out
    end tell
    """

    private static let musicArtworkScript = """
    tell application "Music"
        try
            return data of artwork 1 of current track
        on error
            return ""
        end try
    end tell
    """

    private static let spotifyArtworkURLScript = """
    tell application "Spotify"
        try
            return artwork url of current track
        on error
            return ""
        end try
    end tell
    """
}
