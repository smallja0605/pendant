import SwiftUI

/// Runs macOS Shortcuts (requirements 4.7).
@MainActor
final class ShortcutsModule: PendantModule {
    let id = "shortcuts"
    let displayName = "捷徑"
    let symbolName = "sparkles"
    let cells = CellRange(default: 4, range: 3...8)
    var isEnabled = false

    private let store = ShortcutsStore.shared

    func makeView(size: CGSize) -> AnyView {
        AnyView(ShortcutsView(store: store).frame(width: size.width, height: size.height))
    }

    func makeSettingsView() -> AnyView { AnyView(ShortcutsModuleSettings(store: store)) }

    func activate() { store.refresh() }
    func deactivate() {}
}

private struct ShortcutsModuleSettings: View {
    let store: ShortcutsStore
    @State private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("排列", selection: $settings.shortcutsGrid) {
                Text("圖示格狀").tag(true)
                Text("清單").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            HStack {
                Text("要顯示的捷徑").font(.subheadline.weight(.semibold))
                Spacer()
                Button("全選") { settings.shortcutsHidden = [] }
                Button("清除") { settings.shortcutsHidden = store.names }
                Button("重新整理") { store.refresh() }
            }
            if store.names.isEmpty {
                Text(store.loaded ? "沒有捷徑" : "讀取中…").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.names, id: \.self) { name in
                Toggle(name, isOn: Binding(
                    get: { !settings.shortcutsHidden.contains(name) },
                    set: { shown in
                        settings.shortcutsHidden.removeAll { $0 == name }
                        if !shown { settings.shortcutsHidden.append(name) }
                    }
                ))
            }
        }
        .onAppear { store.refresh() }
    }
}
