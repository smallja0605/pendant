import SwiftUI

/// Per-module settings (requirements 4.5, reference: settings-widgets.png): calendars to show with colour
/// check boxes, the three listing switches, how many days the strip covers, and a shortcut to Calendar.
struct CalendarModuleSettings: View {
    let store: CalendarStore
    @State private var settings = AppSettings.shared

    var body: some View {
        ModuleForm(moduleID: "calendar") {
            moduleGroup("顯示內容") {
                TipRow(title: "日曆") {
                    HStack {
                        Button("全選") { store.selectAll() }
                        Button("清除") { store.clearSelection() }
                    }
                }
                calendarRows
                Toggle("已結束行程", isOn: $settings.calendarShowPast)
                Toggle("全天行程", isOn: $settings.calendarShowAllDay)
                Toggle("跨日行程", isOn: $settings.calendarShowMultiDay)
            }
            moduleGroup("日期範圍") {
                Toggle("整月", isOn: $settings.calendarWholeMonth)
                daysRow("往前天數", value: $settings.calendarDaysBehind).dimmed(when: settings.calendarWholeMonth)
                daysRow("往後天數", value: $settings.calendarDaysAhead).dimmed(when: settings.calendarWholeMonth)
            }
            moduleGroup("其他") {
                TipRow(title: "") { Button("開啟行事曆") { store.openCalendarApp() } }
            }
        }
        .task { await store.ensureAccess() }
    }

    @ViewBuilder private var calendarRows: some View {
        if store.access == .denied {
            Text("需要「行事曆」權限").foregroundStyle(.secondary)
        } else if store.calendars.isEmpty {
            Text("沒有可顯示的日曆").foregroundStyle(.secondary)
        } else {
            ForEach(store.calendars) { calendar in
                CalendarCheckRow(calendar: calendar, isOn: Binding(
                    get: { store.isVisible(calendar.id) }, set: { store.setVisible(calendar.id, $0) }
                ))
            }
        }
    }

    private func daysRow(_ title: String, value: Binding<Int>) -> some View {
        SliderRow(title: title, value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                  range: 0...60, unit: "天")
    }
}

/// Colour square that doubles as the check box; long names wrap or truncate instead of breaking the layout.
private struct CalendarCheckRow: View {
    let calendar: CalendarInfo
    @Binding var isOn: Bool

    var body: some View {
        let color = Color(red: calendar.red, green: calendar.green, blue: calendar.blue)
        Button { isOn.toggle() } label: {
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? color : color.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(color, lineWidth: 1.5))
                    .overlay(
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white).opacity(isOn ? 1 : 0)
                    )
                    .frame(width: 16, height: 16)
                Text(calendar.title)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendar.title)
        .accessibilityValue(isOn ? "已勾選" : "未勾選")
    }
}
