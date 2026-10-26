import AppKit
import SwiftUI

/// Quick notes page of the expanded capsule (requirements 4.2).
@MainActor
final class NotesModule: PendantModule {
    let id = "notes"
    let displayName = "筆記"
    let symbolName = "note.text"
    let cells = CellRange(default: 6, range: 3...10)
    var isEnabled = false

    private let store = NoteStore.shared

    func makeView(size: CGSize) -> AnyView {
        AnyView(NotesView(store: store).frame(width: size.width, height: size.height))
    }

    func makeSettingsView() -> AnyView { AnyView(NotesModuleSettings()) }

    func activate() {}
    func deactivate() { store.flushSaves() }
}

private struct NotesModuleSettings: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        ModuleForm(moduleID: "notes") {
            moduleGroup("編輯") {
                SliderRow(title: "字級", value: $settings.notesFontSize, range: 10...22, unit: "pt")
                Toggle("開啟上次筆記", isOn: $settings.notesOpenLast)
            }
            moduleGroup("儲存") {
                TipRow(title: "儲存位置") {
                    HStack {
                        Text(settings.notesCustomPath.isEmpty ? "預設" : settings.notesCustomPath)
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 170)
                        Button("選擇…", action: chooseFolder)
                        if !settings.notesCustomPath.isEmpty {
                            Button("預設") { settings.notesCustomPath = ""; NoteStore.shared.reload() }
                        }
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "選擇"
        if panel.runModal() == .OK, let url = panel.url {
            settings.notesCustomPath = url.path
            NoteStore.shared.reload()
        }
    }
}
