import SwiftUI

/// Notes page: the list of notes on the left (pinned first), the editor on the right. Opening the capsule puts the
/// cursor in the note, so you can type right away.
struct NotesView: View {
    let store: NoteStore
    @Environment(\.capsuleExpanded) private var isExpanded
    @State private var settings = AppSettings.shared
    @State private var commands = NoteEditorCommands()
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            list.frame(width: 104)
            editor
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .onDisappear { store.flushSaves() }
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 4) {
            HStack {
                Text("筆記").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                Spacer()
                IconButton(symbol: "square.and.pencil", help: "新增筆記") { store.create() }
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(store.sortedNotes) { note in
                        NoteRow(note: note, selected: note.id == store.selectedID) { store.selectedID = note.id }
                    }
                }
            }
            if store.recentlyDeleted != nil {
                Button { store.undoDelete() } label: {
                    Label("復原刪除", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 10.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.14)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.recentlyDeleted != nil)
    }

    // MARK: Editor

    @ViewBuilder private var editor: some View {
        if let note = store.selected {
            VStack(spacing: 4) {
                HStack(spacing: 2) {
                    IconButton(symbol: "bold", help: "粗體") { commands.bold() }
                    IconButton(symbol: "list.bullet", help: "清單") { commands.prefixLines("- ") }
                    IconButton(symbol: "checklist", help: "待辦") { commands.prefixLines("- [ ] ") }
                    Spacer()
                    IconButton(symbol: copied ? "checkmark" : "doc.on.doc", help: "複製全文") {
                        store.copyAll(note.id)
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            copied = false
                        }
                    }
                    IconButton(symbol: note.pinned ? "pin.fill" : "pin", help: "釘選", tint: note.pinned ? .orange : nil) {
                        store.togglePin(note.id)
                    }
                    IconButton(symbol: "trash", help: "刪除") { store.delete(note.id) }
                }
                NoteTextEditor(
                    noteID: note.id, text: note.text, fontSize: CGFloat(settings.notesFontSize), wantsFocus: isExpanded,
                    onChange: { store.update(note.id, text: $0) }, commands: commands
                )
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.07)))
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "note.text").font(.system(size: 24)).foregroundStyle(.white.opacity(0.35))
                Button("新增筆記") { store.create() }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct NoteRow: View {
    let note: Note
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if note.pinned { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.orange) }
                Text(note.title.isEmpty ? "新筆記" : note.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(note.title.isEmpty ? .white.opacity(0.4) : .white)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(selected ? 0.2 : (hovering ? 0.1 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onActiveHover { hovering = $0 != nil }
    }
}

/// Small round-cornered icon button used in the notes toolbar.
struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint ?? .white.opacity(0.8))
                .frame(width: 24, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(hovering ? 0.14 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onActiveHover { hovering = $0 != nil }
        .accessibilityLabel(help)
    }
}
