import SwiftUI

/// The settings of one big-capsule tool as a grouped form: the rows every tool has (page, width) first, then its own.
struct ModuleForm<Content: View>: View {
    let moduleID: String
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            Section {
                ModuleLayoutRows(moduleID: moduleID)
                content
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.top, -20) // the grouped form's own top space: its first card lines up with the tool list beside it
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
