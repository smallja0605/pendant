import Foundation

/// What uninstalling removes, and the check that nothing outside the app's own Library folders is ever touched
/// (requirements 4.11, 13.3). Pure functions, unit-tested.
enum UninstallPlan {
    static let supportFolderName = "Pendant"
    static let notesFolderName = "Notes"

    /// Everything to delete. With `keepNotes` the notes folder inside Application Support stays.
    static func targets(home: URL, bundleID: String, keepNotes: Bool, supportChildren: [String], temp: URL) -> [URL] {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let support = library.appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(supportFolderName, isDirectory: true)
        var result: [URL] = []
        if keepNotes {
            result += supportChildren.filter { $0 != notesFolderName }.map { support.appendingPathComponent($0) }
        } else {
            result.append(support)
        }
        result.append(library.appendingPathComponent("Preferences").appendingPathComponent("\(bundleID).plist"))
        result.append(library.appendingPathComponent("Caches").appendingPathComponent(bundleID, isDirectory: true))
        result.append(temp.appendingPathComponent("pendant-drag", isDirectory: true))
        return result
    }

    /// True only for the whitelisted locations (compared after resolving `..` and symlinks); never the Library or home
    /// folder itself, and never anything containing a `..` component.
    static func isSafe(_ url: URL, home: URL, bundleID: String, temp: URL) -> Bool {
        guard !url.pathComponents.contains("..") else { return false }
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        let library = home.appendingPathComponent("Library").standardizedFileURL.resolvingSymlinksInPath()
        let support = library.appendingPathComponent("Application Support/\(supportFolderName)").path
        if target == support || target.hasPrefix(support + "/") { return true }
        if target == library.appendingPathComponent("Preferences/\(bundleID).plist").path { return true }
        if target == library.appendingPathComponent("Caches/\(bundleID)").path { return true }
        return target == temp.appendingPathComponent("pendant-drag").standardizedFileURL.resolvingSymlinksInPath().path
    }
}
