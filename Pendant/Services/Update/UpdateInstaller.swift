import AppKit
import CryptoKit

/// Downloads, verifies and installs an update package. Nothing downloaded is ever executed: the package is checked
/// (SHA-256, bundle id, code signature, version) and only the app bundle inside it replaces the running one.
enum UpdateInstaller {
    enum UpdateError: Error, Equatable {
        case noChecksum, checksumMismatch, extractFailed, noAppInPackage, wrongBundle, wrongVersion, badSignature, replaceFailed
        case download(String)

        var message: String {
            switch self {
            case .noChecksum: "更新包缺少 SHA-256 校驗檔,已拒絕安裝"
            case .checksumMismatch: "更新包校驗碼不符,已拒絕安裝"
            case .extractFailed: "無法解開更新包"
            case .noAppInPackage: "更新包內找不到 App"
            case .wrongBundle: "更新包不是 Pendant"
            case .wrongVersion: "更新包的版本號與發佈版本不符"
            case .badSignature: "更新包的程式碼簽章驗證失敗"
            case .replaceFailed: "無法取代目前的 App(請確認有寫入權限)"
            case let .download(text): "下載失敗:\(text)"
            }
        }
    }

    // MARK: Download

    /// Downloads `url` into `folder`; `progress` gets 0…1 (file:// URLs are copied, for the debug feed).
    static func download(_ url: URL, into folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let target = folder.appendingPathComponent(url.lastPathComponent)
        if url.isFileURL {
            try FileManager.default.copyItem(at: url, to: target)
            progress(1)
            return target
        }
        guard url.scheme == "https" else { throw UpdateError.download("只允許 HTTPS") }
        let delegate = ProgressDelegate(progress)
        let (temp, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download("伺服器回應異常") }
        try FileManager.default.moveItem(at: temp, to: target)
        return target
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate {
        let report: @Sendable (Double) -> Void
        init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                        totalBytesWritten: Int64, totalBytesExpectedToWrite expected: Int64) {
            if expected > 0 { report(Double(totalBytesWritten) / Double(expected)) }
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    }

    // MARK: Verify

    /// SHA-256 of a file, read in chunks (large packages never sit in memory).
    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func verifyChecksum(of file: URL, expected: String) throws {
        guard try sha256(of: file) == expected.lowercased() else { throw UpdateError.checksumMismatch }
    }

    // MARK: Unpack

    /// Unpacks a `.zip` / `.dmg` into `folder` and returns the single `.app` inside.
    static func unpack(_ archive: URL, into folder: URL) throws -> URL {
        let output = folder.appendingPathComponent("unpacked", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        switch archive.pathExtension.lowercased() {
        case "zip":
            guard run("/usr/bin/ditto", ["-x", "-k", archive.path, output.path]) else { throw UpdateError.extractFailed }
        case "dmg":
            try copyFromDiskImage(archive, to: output)
        default:
            throw UpdateError.extractFailed
        }
        let contents = (try? FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil)) ?? []
        let apps = contents.filter { $0.pathExtension == "app" }
        guard apps.count == 1, let app = apps.first else { throw UpdateError.noAppInPackage }
        return app
    }

    private static func copyFromDiskImage(_ image: URL, to output: URL) throws {
        let mount = output.deletingLastPathComponent().appendingPathComponent("mount", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let attach = ["attach", image.path, "-nobrowse", "-readonly", "-noverify", "-mountpoint", mount.path]
        guard run("/usr/bin/hdiutil", attach) else { throw UpdateError.extractFailed }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let mounted = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []
        for item in mounted where item.pathExtension == "app" {
            let destination = output.appendingPathComponent(item.lastPathComponent).path
            guard run("/usr/bin/ditto", [item.path, destination]) else { throw UpdateError.extractFailed }
        }
    }

    /// The new bundle must be this app (same bundle id), the announced version, and carry a valid code signature.
    static func validate(app: URL, bundleID: String, expected: SemVer?, checkSignature: Bool = true) throws {
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == bundleID else { throw UpdateError.wrongBundle }
        if let expected {
            let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(SemVer.init)
            guard version == expected else { throw UpdateError.wrongVersion }
        }
        if checkSignature, !run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) { throw UpdateError.badSignature }
    }

    // MARK: Replace

    /// Swaps the installed app for the new one (the old one goes to the Trash).
    static func replace(installed: URL, with new: URL) throws {
        do {
            _ = try FileManager.default.replaceItemAt(installed, withItemAt: new, backupItemName: nil, options: [])
            refreshIconCache(of: installed)
        } catch {
            throw UpdateError.replaceFailed
        }
    }

    /// A replaced app keeps its old icon in Finder / the Dock until the system re-reads the bundle: touching it and re-registering it
    /// with Launch Services makes the new icon show (the Dock may still need a restart of itself).
    static func refreshIconCache(of app: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: app.path)
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        _ = run(lsregister, ["-f", app.path])
    }

    // MARK: Helper

    /// Runs a fixed system tool with an argument array (no shell).
    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
