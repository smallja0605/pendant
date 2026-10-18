import AppKit
import Observation

/// Notes on disk: one JSON file per note in `~/Library/Application Support/Pendant/Notes/` (or the folder chosen
/// in settings). Edits are saved 0.5 s after the last keystroke. Note text is never logged.
@MainActor
@Observable
final class NoteStore {
    static let shared = NoteStore()

    private(set) var notes: [Note] = []
    var selectedID: UUID? {
        didSet { if let selectedID { AppSettings.shared.notesLastID = selectedID.uuidString } }
    }
    /// The note that was just deleted; "undo" brings it back for a few seconds.
    private(set) var recentlyDeleted: Note?

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var undoTask: Task<Void, Never>?
    @ObservationIgnored private var pendingSave: Set<UUID> = []

    init() { load() }

    var sortedNotes: [Note] { NoteMarkdown.sorted(notes) }
    var selected: Note? { notes.first { $0.id == selectedID } }

    // MARK: Folder

    static var defaultFolder: URL { AppPaths.subdirectory("Notes") }

    var folder: URL {
        let custom = AppSettings.shared.notesCustomPath
        guard !custom.isEmpty else { return Self.defaultFolder }
        let url = URL(fileURLWithPath: custom, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Re-reads the folder (after the storage location changed).
    func reload() {
        flushSaves()
        load()
    }

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        notes = files.filter { $0.pathExtension == "json" }.compactMap { url in
            (try? Data(contentsOf: url)).flatMap { try? decoder.decode(Note.self, from: $0) }
        }
        if AppSettings.shared.notesOpenLast, let last = UUID(uuidString: AppSettings.shared.notesLastID),
           notes.contains(where: { $0.id == last }) {
            selectedID = last
        } else {
            selectedID = sortedNotes.first?.id
        }
    }

    // MARK: Editing

    @discardableResult
    func create() -> Note {
        let note = Note()
        notes.append(note)
        selectedID = note.id
        scheduleSave(note.id, immediately: true)
        return note
    }

    func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        scheduleSave(id)
    }

    func togglePin(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].pinned.toggle()
        scheduleSave(id, immediately: true)
    }

    func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let removed = notes.remove(at: index)
        recentlyDeleted = removed
        pendingSave.remove(id)
        try? FileManager.default.removeItem(at: fileURL(for: id))
        if selectedID == id { selectedID = sortedNotes.first?.id }
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.recentlyDeleted = nil
        }
    }

    func undoDelete() {
        guard let note = recentlyDeleted else { return }
        recentlyDeleted = nil
        undoTask?.cancel()
        notes.append(note)
        selectedID = note.id
        scheduleSave(note.id, immediately: true)
    }

    func copyAll(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.text, forType: .string)
    }

    #if DEBUG
    /// In memory only (never written): sample notes for screenshots.
    func debugSeed() {
        var first = Note(text: "購物清單\n- [x] 牛奶\n- [ ] **雞蛋** 一打\n- 麵包", pinned: true)
        first.updatedAt = Date()
        let second = Note(text: "會議筆記\n下週一 10:00", updatedAt: Date().addingTimeInterval(-60))
        notes = [first, second]
        selectedID = first.id
    }
    #endif

    // MARK: Saving

    private func fileURL(for id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).json") }

    private func scheduleSave(_ id: UUID, immediately: Bool = false) {
        pendingSave.insert(id)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            if !immediately { try? await Task.sleep(for: .milliseconds(500)) }
            guard !Task.isCancelled else { return }
            self?.flushSaves()
        }
    }

    /// Writes every changed note now (also called when the app quits or the capsule closes).
    func flushSaves() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for id in pendingSave {
            guard let note = notes.first(where: { $0.id == id }), let data = try? encoder.encode(note) else { continue }
            try? data.write(to: fileURL(for: id), options: .atomic)
        }
        pendingSave.removeAll()
    }
}
