import Foundation
import Testing
@testable import Pendant

struct SemVerTests {
    @Test func parsesTagsAndRejectsGarbage() {
        #expect(SemVer("v1.2.3")?.description == "1.2.3")
        #expect(SemVer("1.0.0-beta.2+build5")?.description == "1.0.0-beta.2")
        #expect(SemVer("1.2") == nil)
        #expect(SemVer("1.2.x") == nil)
        #expect(SemVer("1.0.0-") == nil)
        #expect(SemVer("") == nil)
    }

    @Test func ordersLikeSemverOrg() {
        let ordered = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11",
                       "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "2.0.0"].compactMap(SemVer.init)
        #expect(ordered.count == 11)
        for index in 1..<ordered.count { #expect(ordered[index - 1] < ordered[index]) }
        #expect(SemVer("v0.10.0")! > SemVer("0.9.9")!) // numeric, not textual
        #expect(SemVer("1.0.0+a") == SemVer("1.0.0+b"))
    }
}

struct UpdateRulesTests {
    private func release(_ tag: String, pre: Bool = false, draft: Bool = false, assets: [String] = ["Pendant.zip", "Pendant.zip.sha256"]) -> ReleaseInfo {
        let json = """
        {"tag_name":"\(tag)","name":"x","prerelease":\(pre),"draft":\(draft),"body":"notes","html_url":"https://github.com/o/r/releases/tag/\(tag)",
         "assets":[\(assets.map { "{\"name\":\"\($0)\",\"browser_download_url\":\"https://example.com/\($0)\",\"size\":10}" }.joined(separator: ","))]}
        """
        return ReleaseInfo.decode(Data(json.utf8))!
    }

    @Test func decodesAGitHubRelease() {
        let info = release("v1.2.0")
        #expect(info.version == SemVer("1.2.0"))
        #expect(info.archive?.name == "Pendant.zip")
        #expect(info.checksum?.name == "Pendant.zip.sha256")
        #expect(release("v1", assets: []).version == nil)
        #expect(ReleaseInfo.decode(Data("not json".utf8)) == nil)
    }

    @Test func prefersZipOverDmgAndNeedsAnArchive() {
        #expect(release("v1.0.0", assets: ["a.dmg", "a.zip"]).archive?.name == "a.zip")
        #expect(release("v1.0.0", assets: ["a.dmg"]).archive?.name == "a.dmg")
        #expect(release("v1.0.0", assets: ["notes.txt"]).archive == nil)
    }

    @Test func channelsPickTheRightRelease() {
        let list = [release("v1.0.0"), release("v1.1.0-beta.1", pre: true), release("v0.9.0"), release("v2.0.0", draft: true)]
        #expect(UpdateRules.newest(in: list, channel: .stable)?.tagName == "v1.0.0")
        #expect(UpdateRules.newest(in: list, channel: .preview)?.tagName == "v1.1.0-beta.1")
        #expect(UpdateRules.newest(in: [release("v3.0.0", assets: ["x.txt"])], channel: .stable) == nil) // nothing installable
    }

    @Test func detectsANewerVersion() {
        let current = SemVer("0.1.0")!
        #expect(UpdateRules.isNewer(release("v0.2.0"), than: current))
        #expect(!UpdateRules.isNewer(release("v0.1.0"), than: current))
        #expect(!UpdateRules.isNewer(release("v0.1.0-beta.1"), than: current))
        #expect(!UpdateRules.isNewer(release("garbage"), than: current))
    }

    @Test func checksums() {



        let hash = String(repeating: "ab", count: 32)
        #expect(UpdateRules.parseChecksum("\(hash.uppercased())  Pendant.zip\n") == hash)
        #expect(UpdateRules.parseChecksum("zzz  file") == nil)
        #expect(UpdateRules.parseChecksum("") == nil)
    }
}

struct UninstallPlanTests {
    private let home = URL(fileURLWithPath: "/Users/someone")
    private let temp = URL(fileURLWithPath: "/private/tmp/x")
    private let bundle = "com.smallja.pendant"

    @Test func removesOnlyTheAppsOwnFolders() {
        let all = UninstallPlan.targets(home: home, bundleID: bundle, keepNotes: false, supportChildren: ["Notes", "Shelf"], temp: temp)
        #expect(all.map(\.path) == [
            "/Users/someone/Library/Application Support/Pendant",
            "/Users/someone/Library/Preferences/com.smallja.pendant.plist",
            "/Users/someone/Library/Caches/com.smallja.pendant",
            "/private/tmp/x/pendant-drag",
        ])
        for url in all { #expect(UninstallPlan.isSafe(url, home: home, bundleID: bundle, temp: temp)) }
    }

    @Test func keepingNotesSparesTheNotesFolder() {
        let kept = UninstallPlan.targets(home: home, bundleID: bundle, keepNotes: true, supportChildren: ["Notes", "Shelf"], temp: temp)
        #expect(!kept.contains { $0.lastPathComponent == "Notes" })
        #expect(kept.contains { $0.lastPathComponent == "Shelf" })
        #expect(!kept.contains { $0.lastPathComponent == "Pendant" })
    }

    @Test func refusesEverythingElse() {
        func safe(_ path: String) -> Bool { UninstallPlan.isSafe(URL(fileURLWithPath: path), home: home, bundleID: bundle, temp: temp) }
        #expect(!safe("/Users/someone"))
        #expect(!safe("/Users/someone/Library"))
        #expect(!safe("/Users/someone/Library/Application Support"))
        #expect(!safe("/Users/someone/Library/Application Support/Pendant/../Other"))
        #expect(!safe("/Users/someone/Library/Application Support/Other App"))
        #expect(!safe("/Users/someone/Library/Preferences/com.apple.finder.plist"))
        #expect(!safe("/Users/someone/Documents/Notes"))
        #expect(!safe("/"))
        #expect(safe("/Users/someone/Library/Application Support/Pendant/Shelf/file.txt"))
    }
}

struct UpdateInstallerTests {
    /// A minimal unsigned "app" with the given version, zipped like a release asset.
    private func makePackage(version: String, in folder: URL) throws -> (app: URL, zip: URL) {
        let app = folder.appendingPathComponent("Fake.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "com.test.fake", "CFBundleShortVersionString": version, "CFBundleName": "Fake"]
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        let zip = folder.appendingPathComponent("Fake-\(version).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
        try process.run()
        process.waitUntilExit()
        return (app, zip)
    }

    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pendant-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func downloadVerifyUnpackValidateAndReplace() async throws {
        let root = try tempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("release", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let package = try makePackage(version: "0.2.0", in: source)

        // "download" (a local file URL stands in for the GitHub asset)
        let work = root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let downloaded = try await UpdateInstaller.download(package.zip, into: work) { _ in }
        let hash = try UpdateInstaller.sha256(of: downloaded)
        #expect(hash.count == 64)
        try UpdateInstaller.verifyChecksum(of: downloaded, expected: hash.uppercased())
        #expect(throws: UpdateInstaller.UpdateError.checksumMismatch) {
            try UpdateInstaller.verifyChecksum(of: downloaded, expected: String(repeating: "0", count: 64))
        }

        let unpacked = try UpdateInstaller.unpack(downloaded, into: work)
        try UpdateInstaller.validate(app: unpacked, bundleID: "com.test.fake", expected: SemVer("0.2.0"), checkSignature: false)
        #expect(throws: UpdateInstaller.UpdateError.wrongBundle) {
            try UpdateInstaller.validate(app: unpacked, bundleID: "com.other.app", expected: nil, checkSignature: false)
        }
        #expect(throws: UpdateInstaller.UpdateError.wrongVersion) {
            try UpdateInstaller.validate(app: unpacked, bundleID: "com.test.fake", expected: SemVer("9.9.9"), checkSignature: false)
        }
        #expect(throws: UpdateInstaller.UpdateError.badSignature) { // unsigned: the real check refuses it
            try UpdateInstaller.validate(app: unpacked, bundleID: "com.test.fake", expected: nil)
        }

        // replace an "installed" old version
        let installFolder = root.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: installFolder, withIntermediateDirectories: true)
        let old = try makePackage(version: "0.1.0", in: installFolder).app
        try UpdateInstaller.replace(installed: old, with: unpacked)
        let installedVersion = Bundle(url: old)?.infoDictionary?["CFBundleShortVersionString"] as? String
        #expect(installedVersion == "0.2.0")
    }

    @Test func aPackageWithoutAnAppIsRefused() throws {
        let root = try tempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("empty.zip")
        try Data().write(to: file)
        #expect(throws: UpdateInstaller.UpdateError.extractFailed) { try UpdateInstaller.unpack(file, into: root) }
    }
}

struct LegacyDefaultsMigrationTests {
    @Test func copiesOnlyTheAppsOwnKeysOnce() {
        let old = ["settings.hoverDelay": 0.5, "tuning.cellWidth": 80.0, "modules.layout": Data([1]),
                   "NSWindow Frame x": "junk", "AppleLanguages": ["zh"]] as [String: Any]
        #expect(Set(LegacyDefaultsMigration.migratedValues(from: old).keys) == ["settings.hoverDelay", "tuning.cellWidth", "modules.layout"])

        let suite = "pendant-migration-\(UUID().uuidString)"
        let legacy = "pendant-legacy-\(UUID().uuidString)"
        let target = UserDefaults(suiteName: suite)!
        UserDefaults(suiteName: legacy)!.set(0.9, forKey: "settings.hoverDelay")
        UserDefaults(suiteName: legacy)!.set(true, forKey: "unrelated")
        target.set(0.2, forKey: "settings.collapseDelay")
        LegacyDefaultsMigration.run(defaults: target, oldDomain: legacy)
        #expect(target.double(forKey: "settings.hoverDelay") == 0.9)
        #expect(target.object(forKey: "unrelated") == nil)
        target.set(0.1, forKey: "settings.hoverDelay") // later changes are not overwritten by a second run
        LegacyDefaultsMigration.run(defaults: target, oldDomain: legacy)
        #expect(target.double(forKey: "settings.hoverDelay") == 0.1)
        target.removePersistentDomain(forName: suite)
        UserDefaults(suiteName: legacy)?.removePersistentDomain(forName: legacy)
    }
}

struct NumberFieldTests {
    @Test func keepsOnlyNumericCharacters() {
        #expect(NumberField.filter("12abc3", allowNegative: false, allowDecimal: false) == "123")
        #expect(NumberField.filter("-5", allowNegative: false, allowDecimal: false) == "5")
        #expect(NumberField.filter("-5", allowNegative: true, allowDecimal: false) == "-5")
        #expect(NumberField.filter("1-2", allowNegative: true, allowDecimal: false) == "12")
        #expect(NumberField.filter("1.5.2", allowNegative: false, allowDecimal: true) == "1.52")
        #expect(NumberField.filter("1.5", allowNegative: false, allowDecimal: false) == "15")
        #expect(NumberField.filter("１２", allowNegative: false, allowDecimal: false) == "") // full-width digits are not accepted
    }

    @Test func formatsWithTheRequestedDigits() {
        #expect(NumberField.format(12.6, 0) == "13")
        #expect(NumberField.format(0.5, 3) == "0.500")
    }
}

struct UpdateSourceTests {
    @Test func onlyTheProjectsOwnReleaseAssetsAreTrusted() {
        let base = "https://github.com/\(UpdateConfig.repository)/releases/download/v0.4.15/"
        #expect(UpdateConfig.isTrustedDownload(URL(string: base + "Pendant-0.4.15.zip")!))
        #expect(!UpdateConfig.isTrustedDownload(URL(string: "http://github.com/\(UpdateConfig.repository)/releases/download/v1/a.zip")!))
        #expect(!UpdateConfig.isTrustedDownload(URL(string: "https://github.com/someone/else/releases/download/v1/a.zip")!))
        #expect(!UpdateConfig.isTrustedDownload(URL(string: "https://evil.example/\(UpdateConfig.repository)/releases/download/v1/a.zip")!))
        #expect(!UpdateConfig.isTrustedDownload(URL(fileURLWithPath: "/tmp/a.zip")))
    }
}

struct FullscreenDetectorTests {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test func aWindowCoveringTheWholeScreenIsFullscreen() {
        #expect(FullscreenDetector.topWindowIsFullscreen(frames: [screen], screen: screen))
        #expect(FullscreenDetector.topWindowIsFullscreen(frames: [CGRect(x: -1, y: -1, width: 1922, height: 1082)], screen: screen))
    }

    @Test func aMaximizedWindowBelowTheMenuBarIsNot() {
        #expect(!FullscreenDetector.topWindowIsFullscreen(frames: [CGRect(x: 0, y: 30, width: 1920, height: 1050)], screen: screen))
        #expect(!FullscreenDetector.topWindowIsFullscreen(frames: [CGRect(x: 100, y: 100, width: 800, height: 600)], screen: screen))
    }

    @Test func theFrontmostBigWindowDecides() {
        let normal = CGRect(x: 200, y: 150, width: 1200, height: 800)
        let palette = CGRect(x: 50, y: 60, width: 200, height: 300)
        #expect(!FullscreenDetector.topWindowIsFullscreen(frames: [normal, screen], screen: screen)) // the full one is behind
        #expect(FullscreenDetector.topWindowIsFullscreen(frames: [palette, screen], screen: screen)) // a small one in front is ignored
        #expect(!FullscreenDetector.topWindowIsFullscreen(frames: [], screen: screen))
    }

    @Test func downloadNamesMustBePlainFileNames() {
        #expect(UpdateInstaller.safeFileName("Pendant-0.4.16.zip") == "Pendant-0.4.16.zip")
        for bad in ["", ".", "..", "a/b.zip", "..\\evil.zip"] { #expect(UpdateInstaller.safeFileName(bad) == nil, "\(bad)") }
    }
}
