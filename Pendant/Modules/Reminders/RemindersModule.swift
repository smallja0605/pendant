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
        VStack(alignment: .leading, spacing: 10) {
            Text("要顯示的清單:").font(.system(size: 13, weight: .semibold))
            HStack {
                Button("全選") { store.selectAll() }
                Button("清除") { store.clearSelection() }
            }
            lists
            Toggle("顯示已完成", isOn: $settings.remindersShowCompleted)
            Picker("排序方式", selection: $settings.remindersSort) {
                Text("到期日").tag(ReminderSort.dueDate)
                Text("優先度").tag(ReminderSort.priority)
                Text("名稱").tag(ReminderSort.title)
            }
            .frame(maxWidth: 280)
            Stepper("最多顯示 \(settings.remindersLimit) 筆", value: $settings.remindersLimit, in: 3...100)
            Button("開啟「提醒事項」") { store.openRemindersApp() }
        }
        .task { await store.ensureAccess() }
    }

    @ViewBuilder private var lists: some View {
        if store.access == .denied {
            Text("需要「提醒事項」權限。請到「授權」分頁允許。").font(.caption).foregroundStyle(.secondary)
        } else if store.lists.isEmpty {
            Text("沒有可顯示的清單").font(.caption).foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.lists) { list in
                        Toggle(isOn: Binding(get: { store.isVisible(list.id) }, set: { store.setVisible(list.id, $0) })) {
                            HStack(spacing: 6) {
                                Circle().fill(Color(red: list.red, green: list.green, blue: list.blue)).frame(width: 8, height: 8)
                                Text(list.title).lineLimit(2)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 90)
        }
    }
}
