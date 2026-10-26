import SwiftUI

/// The settings of one big-capsule tool as a grouped form: 基本 first (the rows every tool has — page and width — and the tool's own basic
/// ones), then one card per group (`Section("音波") { … }`), each with a small title.
struct ModuleForm<Basic: View, Content: View>: View {
    let moduleID: String
    @ViewBuilder let basic: Basic
    @ViewBuilder let content: Content

    init(moduleID: String, @ViewBuilder basic: () -> Basic = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.moduleID = moduleID
        self.basic = basic()
        self.content = content()
    }

    var body: some View {
        Form {
            moduleGroup("基本", first: true) {
                ModuleLayoutRows(moduleID: moduleID)
                basic
            }
            content
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        // The grouped form's own space around its card (20 pt): the card lines up with the tool list and the preview above it.
        .padding(.top, -20)
        .padding(.horizontal, -20)
        .environment(\.sliderLength, 140)
    }
}

/// 所在分頁 and 寬度.
struct ModuleLayoutRows: View {
    let moduleID: String
    @State private var registry = ModuleRegistry.shared

    var body: some View {
        if let descriptor = ModuleDescriptor.descriptor(for: moduleID) {
            let range = descriptor.cells.range
            DropdownRow(
                title: "所在分頁",
                selection: Binding(
                    get: { registry.primaryTabID(of: moduleID) ?? TabConfig.mainID },
                    set: { tab in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { registry.moveModule(moduleID, toTab: tab) }
                    }
                ),
                options: registry.tabs.map { ($0.id, $0.title.isEmpty ? "(未命名)" : $0.title) }
            )
            SliderRow(
                title: "寬度",
                value: Binding(get: { Double(registry.cells(for: moduleID)) }, set: { registry.setCells(moduleID, Int($0.rounded())) }),
                range: Double(range.lowerBound)...Double(range.upperBound), unit: "格"
            )
        }
    }
}

/// One titled card of a tool's settings. The grouped form leaves a wide gap above every section title and between a title and its card:
/// both are pulled in (the first title keeps its place under the preview, only the gap to its card shrinks).
func moduleGroup<Content: View>(_ title: String, first: Bool = false, @ViewBuilder content: () -> Content) -> some View {
    Section {
        content()
    } header: {
        // The negative top padding closes the wide gap above the title; the offset puts the title back next to its card.
        Text(title).padding(.top, first ? 0 : -20).padding(.bottom, -7).offset(y: first ? 0 : 20)
    }
}
