import Foundation

/// Static description of every module the capsule knows about (requirements 4.x, 4.10, 11.3).
struct ModuleDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let symbolName: String
    let cells: CellRange
    /// False for modules that arrive in later milestones (they show a placeholder page).
    let implemented: Bool
    /// Cannot be switched on at all (Quick Apps: "coming soon").
    let selectable: Bool
    /// Enabled on first launch. Only implemented modules start enabled.
    let defaultEnabled: Bool

    private init(_ id: String, _ title: String, _ symbol: String, cells: Int, range: ClosedRange<Int> = 1...10,
                 implemented: Bool = false, selectable: Bool = true, defaultEnabled: Bool = false) {
        self.id = id
        self.title = title
        self.symbolName = symbol
        self.cells = CellRange(default: cells, range: range)
        self.implemented = implemented
        self.selectable = selectable
        self.defaultEnabled = defaultEnabled
    }

    /// Default order from requirements 11.3: media → notes → reminders → calendar → timer → mirror → shelf →
    /// shortcuts; Quick Apps is a disabled placeholder.
    static let all: [ModuleDescriptor] = [
        .init("media", "音樂", "music.note", cells: 5, range: 3...10, implemented: true, defaultEnabled: true),
        .init("notes", "筆記", "note.text", cells: 6, range: 3...10, implemented: true, defaultEnabled: true),
        .init("reminders", "待辦事項", "checklist", cells: 4, implemented: true, defaultEnabled: true),
        .init("calendar", "行事曆", "calendar", cells: 5, implemented: true, defaultEnabled: true),
        .init("timer", "計時器", "timer", cells: 4, range: 3...6, implemented: true, defaultEnabled: true),
        .init("mirror", "鏡子", "web.camera", cells: 2, range: 2...6, implemented: true, defaultEnabled: true),
        .init("shelf", "檔案中轉站", "tray.and.arrow.down", cells: 6, range: 3...10, implemented: true, defaultEnabled: true),
        .init("shortcuts", "捷徑", "sparkles", cells: 4, implemented: true),
        .init("quickApps", "快速應用", "square.grid.2x2", cells: 2, selectable: false),
    ]

    static func descriptor(for id: String) -> ModuleDescriptor? {
        all.first { $0.id == id }
    }
}

/// A tab of the open capsule (top-left switch): a name and the modules shown in it. A module may be in several tabs.
struct TabConfig: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var moduleIDs: [String]

    static let mainID = "main"

    /// 功能, 筆記, 檔案中轉站: what the capsule starts with.
    static let defaults: [TabConfig] = [
        TabConfig(id: mainID, title: "小工具", moduleIDs: ["media", "reminders", "calendar", "timer", "mirror", "shortcuts"]),
        TabConfig(id: "notes", title: "筆記", moduleIDs: ["notes"]),
        TabConfig(id: "shelf", title: "檔案中轉站", moduleIDs: ["shelf"]),
    ]
}

/// What is persisted about the module layout; `normalized` repairs anything stale or corrupt.
struct ModuleLayoutState: Equatable, Sendable {
    var order: [String]
    var enabled: Set<String>
    var cells: [String: Int]
    /// Modules that were already implemented when this state was saved. A module that becomes implemented
    /// later (a new milestone) and is enabled by default gets switched on once for existing users.
    var seenImplemented: Set<String>
    var tabs: [TabConfig] = TabConfig.defaults

    static let `default` = ModuleLayoutState(
        order: ModuleDescriptor.all.map(\.id),
        enabled: Set(ModuleDescriptor.all.filter { $0.defaultEnabled && $0.selectable }.map(\.id)),
        cells: [:],
        seenImplemented: Set(ModuleDescriptor.all.filter(\.implemented).map(\.id))
    )

    /// Drops unknown ids, appends modules that were added since the state was saved, clamps cell counts and
    /// never enables a module that cannot be enabled.
    func normalized(descriptors: [ModuleDescriptor] = ModuleDescriptor.all) -> ModuleLayoutState {
        let known = Set(descriptors.map(\.id))
        var seen = Set<String>()
        var newOrder = order.filter { known.contains($0) && seen.insert($0).inserted }
        newOrder += descriptors.map(\.id).filter { !seen.contains($0) }

        let selectable = Set(descriptors.filter(\.selectable).map(\.id))
        var newCells: [String: Int] = [:]
        for descriptor in descriptors {
            if let value = cells[descriptor.id] {
                newCells[descriptor.id] = min(max(value, descriptor.cells.range.lowerBound), descriptor.cells.range.upperBound)
            }
        }
        var newEnabled = enabled.intersection(selectable)
        let implemented = Set(descriptors.filter(\.implemented).map(\.id))
        for descriptor in descriptors where descriptor.implemented && descriptor.defaultEnabled && descriptor.selectable
            && !seenImplemented.contains(descriptor.id) {
            newEnabled.insert(descriptor.id)
        }
        // Tabs: unknown module ids and duplicate tab ids go; at least one tab always exists.
        var tabIDs = Set<String>()
        var newTabs = tabs.filter { tabIDs.insert($0.id).inserted }.map { tab -> TabConfig in
            var copy = tab
            copy.moduleIDs = tab.moduleIDs.filter { known.contains($0) }
            // The first tab was called 功能 (and may still be saved under that name).
            if copy.id == TabConfig.mainID, copy.title == "功能" { copy.title = "小工具" }
            return copy
        }
        if newTabs.isEmpty { newTabs = TabConfig.defaults }
        return ModuleLayoutState(order: newOrder, enabled: newEnabled, cells: newCells, seenImplemented: implemented, tabs: newTabs)
    }
}

/// Splits the enabled modules into pages that fit the available width (requirements 3.2).
enum ModulePager {
    /// - Returns: for each page, the indexes into `cellCounts`.
    static func pages(cellCounts: [Int], cellWidth: CGFloat, gap: CGFloat, inset: CGFloat, maxWidth: CGFloat) -> [[Int]] {
        guard !cellCounts.isEmpty else { return [] }
        var pages: [[Int]] = [[]]
        var width = 2 * inset
        for (index, cells) in cellCounts.enumerated() {
            let moduleWidth = CGFloat(cells) * cellWidth
            let needed = (pages[pages.count - 1].isEmpty ? 0 : gap) + moduleWidth
            if !pages[pages.count - 1].isEmpty, width + needed > maxWidth {
                pages.append([index])
                width = 2 * inset + moduleWidth
            } else {
                pages[pages.count - 1].append(index)
                width += needed
            }
        }
        return pages
    }

    static func contentWidth(cellCounts: [Int], cellWidth: CGFloat, gap: CGFloat, inset: CGFloat) -> CGFloat {
        guard !cellCounts.isEmpty else { return 0 }
        return CGFloat(cellCounts.reduce(0, +)) * cellWidth + CGFloat(cellCounts.count - 1) * gap + 2 * inset
    }
}
