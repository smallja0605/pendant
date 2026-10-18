import Foundation

/// Folders the app owns under `~/Library/Application Support/Pendant/` (notes, shelf).
enum AppPaths {
    static let folderName = "Pendant"
    /// The folder's name before the app was renamed; its contents are moved over once at launch.
    static let legacyFolderName = "smallja's Nook"

    /// Moves the old Application Support folder to the new name (notes and shelf files keep working). Does nothing when
    /// there is no old folder or the new one already exists.
    static func migrateLegacyFolder() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = base.appendingPathComponent(legacyFolderName, isDirectory: true)
        let new = base.appendingPathComponent(folderName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: new.path) else { return }
        try? FileManager.default.moveItem(at: old, to: new)
    }

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// A named sub-folder of the support directory, created if missing.
    static func subdirectory(_ name: String) -> URL {
        let url = supportDirectory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
