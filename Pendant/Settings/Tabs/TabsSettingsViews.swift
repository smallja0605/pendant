import SwiftUI

/// The capsule's tabs as chips, with a button to add one.
struct TabChips: View {
    let registry: ModuleRegistry
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(registry.tabs) { tab in
                    Text(tab.title.isEmpty ? "(未命名)" : tab.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == tab.id ? Color.white : .primary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(selection == tab.id ? Color.accentColor : Color.primary.opacity(0.1)))
                        .contentShape(Capsule())
                        .onTapGesture { selection = tab.id }
                }
                Button {
                    selection = registry.addTab(title: "新分頁")
                } label: {
                    Label("新增分頁", systemImage: "plus").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

/// Name and delete button of the selected tab (between the tab chips and the preview bar).
struct TabNameRow: View {
    let registry: ModuleRegistry
    let tab: TabConfig
    @Binding var selection: String

    var body: some View {
        HStack {
            Text("分頁名稱")
            TextField("", text: Binding(get: { tab.title }, set: { registry.renameTab(tab.id, to: $0) }))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 260)
            Spacer()
            Button("刪除分頁", role: .destructive) {
                registry.removeTab(tab.id)
                selection = registry.tabs.first?.id ?? TabConfig.mainID
            }
            .disabled(registry.tabs.count <= 1)
        }
    }
}

/// The modules of the selected tab (any module can be in any number of tabs).
struct TabModuleChecklist: View {
    let registry: ModuleRegistry
    let tab: TabConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("加入此分頁的小工具").font(.subheadline.weight(.semibold))
            ForEach(registry.descriptors.filter(\.selectable)) { descriptor in
                Toggle(isOn: Binding(
                    get: { tab.moduleIDs.contains(descriptor.id) },
                    set: { registry.setModule(descriptor.id, in: tab.id, $0) }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: descriptor.symbolName).frame(width: 18)
                        Text(descriptor.title)
                        if !registry.isEnabled(descriptor.id) {
                            Text("(未啟用)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!descriptor.implemented)
            }
            Text("小工具要同時「已啟用」並加入某個分頁才會顯示;一個小工具可以放進多個分頁。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
