import Foundation

/// Where updates come from. A Mac that has the local update folder (the developer's: `scripts/publish-update.sh` builds into it) reads
/// only that folder and makes no network connection for updates; every other Mac reads the GitHub releases of the project.
enum UpdateConfig {
    enum Source: Equatable {
        case localFolder, github

        var title: String { self == .github ? "GitHub" : tr("本機資料夾") }
    }

    /// `~/Library/Application Support/Pendant/Updates`: holds `Pendant-X.Y.Z.zip`, its `.sha256` and `releases.json`.
    static var feedFolder: URL { AppPaths.supportDirectory.appendingPathComponent("Updates", isDirectory: true) }
    static var feedFile: URL { feedFolder.appendingPathComponent("releases.json") }
    static let checkInterval: TimeInterval = 24 * 3600

    static let repository = "smallja0605/pendant"
    static var releasesURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30") ?? URL(fileURLWithPath: "/")
    }

    static var source: Source {
        #if DEBUG
        // PENDANT_DEBUG_UPDATE_SOURCE=github: read GitHub even on a Mac that has the local folder (to exercise that path).
        if ProcessInfo.processInfo.environment["PENDANT_DEBUG_UPDATE_SOURCE"] == "github" { return .github }
        #endif
        return FileManager.default.fileExists(atPath: feedFolder.path) ? .localFolder : .github
    }

    /// A package from GitHub is downloaded only from this project's own release assets.
    static func isTrustedDownload(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.path.hasPrefix("/\(repository)/releases/download/")
    }
}
