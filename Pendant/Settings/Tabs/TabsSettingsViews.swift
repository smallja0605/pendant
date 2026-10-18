import SwiftUI

/// Where each tab pill of the big-capsule demo is (in the demo's coordinate space): a dragged tool is dropped onto one of them.
struct TabPillFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

/// The capsule's tabs as pills, with a "+" to add one. A tool dragged over a pill (`dropTab`) lights it up.
struct TabChips: View {
    let registry: ModuleRegistry
    @Binding var selection: String
    let dropTab: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(registry.tabs) { tab in
                    let isDrop = dropTab == tab.id
                    Text(tab.title.isEmpty ? "(未命名)" : tab.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == tab.id || isDrop ? Color.white : .primary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(selection == tab.id || isDrop ? Color.accentColor : Color.primary.opacity(0.12)))
                        .scaleEffect(isDrop ? 1.08 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDrop)
                        .contentShape(Capsule())
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { selection = tab.id } }
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: TabPillFrames.self, value: [tab.id: proxy.frame(in: .named("bigDemo"))])
                        })
                }
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = registry.addTab(title: "新分頁") }
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 24)
                        .background(Capsule().fill(Color.primary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Name and delete button of the selected tab (not shown for the first tab).
struct TabNameRow: View {
    let registry: ModuleRegistry
    let tab: TabConfig
    @Binding var selection: String

    var body: some View {
        HStack {
            TextField("分頁名稱", text: Binding(get: { tab.title }, set: { registry.renameTab(tab.id, to: $0) }))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 200)
            Button("刪除分頁", role: .destructive) {
                registry.removeTab(tab.id)
                selection = registry.tabs.first?.id ?? TabConfig.mainID
            }
            .disabled(registry.tabs.count <= 1)
        }
    }
}
