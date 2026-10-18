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
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("字體大小") {
                HStack {
                    HapticSlider(value: $settings.notesFontSize, in: 10...22, step: 1)
                    Text("\(Int(settings.notesFontSize)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
            }
            Toggle("預設開啟最後編輯的筆記", isOn: $settings.notesOpenLast)
            LabeledContent("儲存位置") {
                HStack {
                    Text(settings.notesCustomPath.isEmpty ? "預設(Application Support)" : settings.notesCustomPath)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).frame(maxWidth: 170)
                    Button("選擇…", action: chooseFolder)
                    if !settings.notesCustomPath.isEmpty {
                        Button("預設") { settings.notesCustomPath = ""; NoteStore.shared.reload() }
                    }
                }
            }
            Text("筆記自動儲存(停止輸入 0.5 秒後),每則一個檔案。支援 **粗體**、「- 」清單與「- [ ]」待辦(點方框勾選)。")
                .font(.caption).foregroundStyle(.secondary)
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
