import Foundation

/// Where updates come from: a folder on this Mac. The app makes no network connection at all; `scripts/publish-update.sh`
/// builds a new version into that folder, and the installed app picks it up from there.
enum UpdateConfig {
    /// `~/Library/Application Support/Pendant/Updates`: holds `Pendant-X.Y.Z.zip`, its `.sha256` and `releases.json`.
    static var feedFolder: URL { AppPaths.supportDirectory.appendingPathComponent("Updates", isDirectory: true) }
    static var feedFile: URL { feedFolder.appendingPathComponent("releases.json") }
    static let checkInterval: TimeInterval = 24 * 3600
}
