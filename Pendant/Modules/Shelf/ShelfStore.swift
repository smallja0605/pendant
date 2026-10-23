import AppKit
import Observation
import QuickLookThumbnailing

/// The drop shelf (requirements 4.6): copies of dropped files in `…/Application Support/Pendant/Shelf/`.
/// Copying in and out never touches the originals and runs off the main thread. File names are never logged.
@MainActor
@Observable
final class ShelfStore {
    static let shared = ShelfStore()

    private(set) var items: [ShelfItem] = []
    var selection: Set<UUID> = []
    /// Files still being copied in (progress indicator).
    private(set) var pendingCopies = 0
    /// Set when a drop was refused because of the limits; shown briefly.
    private(set) var limitMessage: String?
    private(set) var lastDropAt = Date.distantPast
    /// Files that just arrived (they are uncovered with an animation for a moment).
    private(set) var freshIDs: Set<UUID> = []

    @ObservationIgnored private let folder = AppPaths.subdirectory("Shelf")
    @ObservationIgnored private var thumbnails: [UUID: NSImage] = [:]
    @ObservationIgnored private var messageTask: Task<Void, Never>?

    private var indexURL: URL { folder.appendingPathComponent(".index.json") }

    init() { load() }

    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }

    func url(for item: ShelfItem) -> URL { folder.appendingPathComponent(item.name) }
    func urls(for ids: Set<UUID>) -> [URL] { items.filter { ids.contains($0.id) }.map(url(for:)) }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let stored = try? JSONDecoder().decode([ShelfItem].self, from: data) else { return }
        items = stored.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
        if items.count != stored.count { save() }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { try? data.write(to: indexURL, options: .atomic) }
    }

    // MARK: Adding

    /// Copies the dropped files / folders in. The originals stay where they are.
    func add(urls: [URL]) {
        lastDropAt = Date()
        let settings = AppSettings.shared
        for source in urls where source.isFileURL {
            let size = Self.size(of: source)
            let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let name = ShelfRules.uniqueName(source.lastPathComponent, existing: Set(items.map(\.name)).union(reservedNames))
            reservedNames.insert(name)
            pendingCopies += 1
            let destination = folder.appendingPathComponent(name)
            Task {
                let ok = await Self.copy(source, to: destination)
                pendingCopies -= 1
                reservedNames.remove(name)
                if ok {
                    let item = ShelfItem(name: name, isDirectory: isDirectory, bytes: size)
                    freshIDs.insert(item.id)
                    items.append(item)
                    save()
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        freshIDs.remove(item.id)
                    }
                }
            }
        }
    }

    @ObservationIgnored private var reservedNames: Set<String> = []

    private func showMessage(_ text: String) {
        limitMessage = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.limitMessage = nil
        }
    }

    // MARK: Removing

    func remove(_ ids: Set<UUID>) {
        for item in items where ids.contains(item.id) { try? FileManager.default.removeItem(at: url(for: item)) }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        ids.forEach { thumbnails[$0] = nil }
        save()
    }

    func clear() { remove(Set(items.map(\.id))) }

    // MARK: Using

    func copyToPasteboard(_ ids: Set<UUID>) {
        let urls = urls(for: ids.isEmpty ? Set(items.map(\.id)) : ids)
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    func airDrop(_ ids: Set<UUID>) {
        let urls = urls(for: ids.isEmpty ? Set(items.map(\.id)) : ids)
        Self.sendViaAirDrop(urls)
    }

    static func sendViaAirDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
    }

    /// Fresh copies for a drag out of the shelf, so the destination can never move the shelf's own file
    /// (a drag within one volume would default to "move" in Finder). They are removed again later.
    func dragCopies(for ids: Set<UUID>) -> [URL] {
        let root = Self.dragRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return urls(for: ids).compactMap { source in
            let target = root.appendingPathComponent(source.lastPathComponent)
            return (try? FileManager.default.copyItem(at: source, to: target)) != nil ? target : nil
        }
    }

    private static var dragRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("pendant-drag", isDirectory: true) }

    /// Deletes drag copies left over from earlier sessions.
    func cleanDragCopies() { try? FileManager.default.removeItem(at: Self.dragRoot) }

    // MARK: Selection

    func select(_ id: UUID, extend: Bool, toggle: Bool, anchor: inout UUID?) {
        if extend, let anchorID = anchor, let from = items.firstIndex(where: { $0.id == anchorID }),
           let to = items.firstIndex(where: { $0.id == id }) {
            selection = Set(items[min(from, to)...max(from, to)].map(\.id))
        } else if toggle {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else {
            selection = [id]
            anchor = id
        }
    }

    func selectAll() { selection = Set(items.map(\.id)) }

    // MARK: Thumbnails

    func thumbnail(for item: ShelfItem) async -> NSImage? {
        if let cached = thumbnails[item.id] { return cached }
        let request = QLThumbnailGenerator.Request(fileAt: url(for: item), size: CGSize(width: 96, height: 96),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .all)
        let image = (try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request))?.nsImage
            ?? NSWorkspace.shared.icon(forFile: url(for: item).path)
        thumbnails[item.id] = image
        return image
    }

    // MARK: Auto clear (4.6 settings)

    /// At launch: "after N days" and "on restart".
    func applyAutoClearAtLaunch() {
        let settings = AppSettings.shared
        let boot = Self.bootTime
        switch settings.shelfAutoClear {
        case .afterDays: remove(Set(ShelfRules.expired(items, days: settings.shelfAutoClearDays).map(\.id)))
        case .onReboot:
            let last = UserDefaults.standard.object(forKey: AppSettings.prefix + "shelfLastBoot") as? Date
            if ShelfRules.rebooted(lastBoot: last, currentBoot: boot) { clear() }
        default: break
        }
        UserDefaults.standard.set(boot, forKey: AppSettings.prefix + "shelfLastBoot")
    }

    /// When the app quits (also what a log-out does): "on log-out" clears the shelf.
    func applyAutoClearAtQuit() {
        if AppSettings.shared.shelfAutoClear == .onLogout { clear() }
        cleanDragCopies()
    }

    private static var bootTime: Date {
        var value = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &value, &size, nil, 0) == 0 else { return .distantPast }
        return Date(timeIntervalSince1970: TimeInterval(value.tv_sec))
    }

    // MARK: File work (off the main thread)

    private nonisolated static func copy(_ source: URL, to destination: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try FileManager.default.copyItem(at: source, to: destination)
                    continuation.resume(returning: true)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Size of a file, or of everything inside a folder.
    nonisolated static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        guard (try? url.resourceValues(forKeys: Set(keys)).isDirectory) == true else {
            return Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
        while let file = enumerator?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
