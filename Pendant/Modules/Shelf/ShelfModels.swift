import Foundation

/// One item on the shelf: a copy of a file or folder kept in the app's own folder.
struct ShelfItem: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    /// File name inside the shelf folder (unique there).
    var name: String
    var addedAt = Date()
    var isDirectory = false
    var bytes: Int64 = 0
}

/// Pure rules of the shelf (naming, limits, auto-clear), unit-tested.
enum ShelfRules {
    /// `name`, or `name 2.ext`, `name 3.ext` … when that name is taken.
    static func uniqueName(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let base = ext.isEmpty ? name : String(name.dropLast(ext.count + 1))
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            if !existing.contains(candidate) { return candidate }
            counter += 1
        }
    }

    /// Items older than `days` (auto-clear "after N days").
    static func expired(_ items: [ShelfItem], days: Int, now: Date = Date()) -> [ShelfItem] {
        let limit = now.addingTimeInterval(-Double(days) * 86_400)
        return items.filter { $0.addedAt < limit }
    }

    /// The machine was restarted since `lastBoot` was recorded.
    static func rebooted(lastBoot: Date?, currentBoot: Date) -> Bool {
        guard let lastBoot else { return false }
        return abs(lastBoot.timeIntervalSince(currentBoot)) > 5
    }
}
