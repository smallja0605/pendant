import SwiftUI

/// Reminders page of the expanded capsule (requirements 4.3).
@MainActor
final class RemindersModule: PendantModule {
    let id = "reminders"
    let displayName = String(localized: "module.reminders", defaultValue: "待辦事項")
    let symbolName = "checklist"
    let cells = CellRange(default: 4, range: 2...10)
    let requiredPermissions: [PendantPermission] = [.reminders]
    var isEnabled = false

    private let store = RemindersStore.shared

    func makeView(size: CGSize) -> AnyView {
        AnyView(RemindersView(store: store).frame(width: size.width, height: size.height))
    }

    func makeSettingsView() -> AnyView { AnyView(RemindersModuleSettings(store: store)) }

    func activate() {}
    func deactivate() {}
}

private struct RemindersModuleSettings: View {
    let store: RemindersStore
    @State private var settings = AppSettings.shared

    var body: some View {
        ModuleForm(moduleID: "reminders") {
            TipRow(title: "清單") {
                HStack {
                    Button("全選") { store.selectAll() }
                    Button("清除") { store.clearSelection() }
                }
            }
            listRows
            Toggle("已完成", isOn: $settings.remindersShowCompleted)
            DropdownRow(title: "排序", selection: $settings.remindersSort, options: [
                (ReminderSort.dueDate, "到期日"), (.priority, "優先度"), (.title, "名稱"),
            ])
            SliderRow(title: "顯示筆數", value: Binding(get: { Double(settings.remindersLimit) },
                                                      set: { settings.remindersLimit = Int($0.rounded()) }),
                      range: 3...100, unit: "筆")
            TipRow(title: "") { Button("開啟提醒事項") { store.openRemindersApp() } }
        }
        .task { await store.ensureAccess() }
    }

    @ViewBuilder private var listRows: some View {
        if store.access == .denied {
            Text("需要「提醒事項」權限").foregroundStyle(.secondary)
        } else if store.lists.isEmpty {
            Text("沒有可顯示的清單").foregroundStyle(.secondary)
        } else {
            ForEach(store.lists) { list in
                Toggle(isOn: Binding(get: { store.isVisible(list.id) }, set: { store.setVisible(list.id, $0) })) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(red: list.red, green: list.green, blue: list.blue)).frame(width: 8, height: 8)
                        Text(list.title).lineLimit(2)
                    }
                }
            }
        }
    }
}
