import AppKit
import Observation

/// Checks the update source (the local folder or the GitHub releases, see `UpdateConfig.source`) at launch and every 24 hours, tells
/// the user about a newer version and (optionally) installs it. Automatic checks fail silently; only a check the user asked for
/// reports errors.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle, checking, upToDate
        case available(ReleaseInfo)
        case downloading(Double)
        case installing
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    @ObservationIgnored private var scheduler: Task<Void, Never>?
    @ObservationIgnored private let currentVersion: SemVer
    private var settings: AppSettings { .shared }

    init(currentVersion: SemVer? = nil) {
        self.currentVersion = currentVersion ?? Self.bundleVersion
    }

    static var bundleVersion: SemVer {
        #if DEBUG
        // PENDANT_DEBUG_VERSION=0.0.1 pretends to be an old version (to exercise the update flow).
        if let fake = ProcessInfo.processInfo.environment["PENDANT_DEBUG_VERSION"].flatMap(SemVer.init) { return fake }
        #endif
        return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(SemVer.init) ?? .zero
    }

    var availableRelease: ReleaseInfo? { if case let .available(release) = state { release } else { nil } }

    // MARK: Schedule

    /// At launch (a little later, not to compete with start-up) and then every 24 hours.
    func startScheduling() {
        scheduler?.cancel()
        scheduler = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                if let self, settings.autoCheckUpdates { await check(userInitiated: false) }
                try? await Task.sleep(for: .seconds(UpdateConfig.checkInterval))
            }
        }
    }

    // MARK: Check

    func check(userInitiated: Bool) async {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        state = .checking
        do {
            let release = try await fetchNewest()
            lastChecked = Date()
            if let release, UpdateRules.isNewer(release, than: currentVersion) {
                state = .available(release)
                if !userInitiated, settings.autoInstallUpdates { await install() }
            } else {
                state = userInitiated ? .upToDate : .idle
            }
        } catch {
            state = userInitiated ? .failed("無法讀取更新來源") : .idle
        }
    }

    private func fetchNewest() async throws -> ReleaseInfo? {
        let channel = UpdateRules.Channel(rawValue: settings.updateChannel) ?? .stable
        if UpdateConfig.source == .github, !usesDebugFeed {
            var request = URLRequest(url: UpdateConfig.releasesURL, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Pendant/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return UpdateRules.newest(in: ReleaseInfo.decodeList(data), channel: channel)
        }
        var feed = UpdateConfig.feedFile
        #if DEBUG
        // PENDANT_DEBUG_UPDATE_FEED=/path/to/releases.json: another feed file (to exercise the update flow).
        if let path = ProcessInfo.processInfo.environment["PENDANT_DEBUG_UPDATE_FEED"] { feed = URL(fileURLWithPath: path) }
        #endif
        // No feed yet simply means there is nothing newer.
        guard let data = FileManager.default.contents(atPath: feed.path) else { return nil }
        return UpdateRules.newest(in: ReleaseInfo.decodeList(data), channel: channel)
    }

    /// PENDANT_DEBUG_UPDATE_FEED (debug builds only) points the check at another feed file.
    private var usesDebugFeed: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["PENDANT_DEBUG_UPDATE_FEED"] != nil
        #else
        false
        #endif
    }

    // MARK: Install

    func install() async {
        guard case let .available(release) = state, let archive = release.archive, let checksum = release.checksum else {
            if case .available = state { state = .failed(UpdateInstaller.UpdateError.noChecksum.message) }
            return
        }
        // A package from GitHub must carry the developer's signature; the developer's own local feed may be unsigned.
        let needsSignature = UpdateConfig.source == .github
        if needsSignature, release.signature == nil {
            state = .failed(UpdateInstaller.UpdateError.noSignature.message)
            return
        }
        let downloads = [archive.url, checksum.url] + (release.signature.map { [$0.url] } ?? [])
        if UpdateConfig.source == .github, !downloads.allSatisfy(UpdateConfig.isTrustedDownload) {
            state = .failed("更新包不是來自 Pendant 的官方發佈,已拒絕安裝")
            return
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("pendant-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            state = .downloading(0)
            let package = try await UpdateInstaller.download(archive.url, into: work) { fraction in
                Task { @MainActor in UpdateChecker.shared.reportProgress(fraction) }
            }
            let sumFile = try await UpdateInstaller.download(checksum.url, into: work) { _ in }
            let sumText = String(bytes: (try? Data(contentsOf: sumFile)) ?? Data(), encoding: .utf8) ?? ""
            guard let expected = UpdateRules.parseChecksum(sumText) else { throw UpdateInstaller.UpdateError.noChecksum }
            state = .installing
            try UpdateInstaller.verifyChecksum(of: package, expected: expected)
            if let signatureAsset = release.signature {
                let signatureFile = try await UpdateInstaller.download(signatureAsset.url, into: work) { _ in }
                let signatureText = String(bytes: (try? Data(contentsOf: signatureFile)) ?? Data(), encoding: .utf8) ?? ""
                // The digest that is signed is the one of the file that was really downloaded, not the one in the checksum file.
                let digest = try UpdateInstaller.sha256(of: package)
                guard UpdateSignature.verify(signatureBase64: signatureText, version: "\(release.version ?? .zero)", sha256: digest) else {
                    throw UpdateInstaller.UpdateError.signatureMismatch
                }
            }
            let app = try UpdateInstaller.unpack(package, into: work)
            try UpdateInstaller.validate(app: app, bundleID: Bundle.main.bundleIdentifier ?? "", expected: release.version)
            try UpdateInstaller.replace(installed: Bundle.main.bundleURL, with: app)
            try? FileManager.default.removeItem(at: work)
            relaunch()
        } catch let error as UpdateInstaller.UpdateError {
            Log.app.error("update refused: \(error.message, privacy: .public)")
            state = .failed(error.message)
            try? FileManager.default.removeItem(at: work)
        } catch {
            state = .failed(UpdateInstaller.UpdateError.download("請稍後再試").message)
            try? FileManager.default.removeItem(at: work)
        }
    }

    private func reportProgress(_ fraction: Double) {
        if case .downloading = state { state = .downloading(fraction) }
    }

    private func relaunch() {
        SettingsWindowController.shared.rememberForRestart() // the settings window comes back after the restart
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
