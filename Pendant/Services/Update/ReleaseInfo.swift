import Foundation

struct ReleaseAsset: Decodable, Equatable, Sendable {
    let name: String
    let url: URL
    let size: Int

    enum CodingKeys: String, CodingKey {
        case name, size
        case url = "browser_download_url"
    }
}

/// A release as the updater needs it (GitHub release JSON shape, written by `scripts/publish-update.sh`).
struct ReleaseInfo: Decodable, Equatable, Sendable {
    typealias Asset = ReleaseAsset

    let tagName: String
    let name: String?
    let prerelease: Bool
    let draft: Bool
    let body: String?
    let htmlURL: URL?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case name, prerelease, draft, body, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }

    var version: SemVer? { SemVer(tagName) }

    /// The update package: a `.zip` (preferred) or a `.dmg`.
    var archive: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".zip") } ?? assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }

    /// The `.sha256` file that belongs to the package (same base name, else the only `.sha256` asset).
    var checksum: Asset? {
        let checksums = assets.filter { $0.name.lowercased().hasSuffix(".sha256") }
        if let archive, let match = checksums.first(where: { $0.name.hasPrefix(archive.name) }) { return match }
        return checksums.count == 1 ? checksums.first : nil
    }

    static func decode(_ data: Data) -> ReleaseInfo? { try? JSONDecoder().decode(ReleaseInfo.self, from: data) }
    static func decodeList(_ data: Data) -> [ReleaseInfo] { (try? JSONDecoder().decode([ReleaseInfo].self, from: data)) ?? [] }
}

/// Which release counts as "the newest" for a channel, and whether it is newer than what is running.
enum UpdateRules {
    enum Channel: String, CaseIterable, Sendable { case stable, preview }

    /// Newest installable release among `releases` (drafts never; pre-releases only on the preview channel).
    static func newest(in releases: [ReleaseInfo], channel: Channel) -> ReleaseInfo? {
        releases
            .filter { release in
                guard let version = release.version, release.archive != nil, !release.draft else { return false }
                return channel == .preview || (!release.prerelease && !version.isPrerelease)
            }
            .max { ($0.version ?? .zero) < ($1.version ?? .zero) }
    }

    static func isNewer(_ release: ReleaseInfo, than current: SemVer) -> Bool {
        guard let version = release.version else { return false }
        return version > current
    }

    /// The first token of a `.sha256` file (`<hex>  filename`), lower-cased; nil if it is not 64 hex digits.
    static func parseChecksum(_ text: String) -> String? {
        guard let token = text.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)?.lowercased(),
              token.count == 64, token.allSatisfy(\.isHexDigit) else { return nil }
        return token
    }
}
