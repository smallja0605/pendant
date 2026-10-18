import SwiftUI

/// Per-module settings (requirements 4.5, reference: settings-widgets.png): calendars to show with colour
/// check boxes, the three listing switches, how many days the strip covers, and a shortcut to Calendar.
struct CalendarModuleSettings: View {
    let store: CalendarStore
    @State private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendars to show:").font(.system(size: 13, weight: .semibold))
            HStack {
                Button("Select All") { store.selectAll() }
                Button("Clear") { store.clearSelection() }
            }
            calendarList
            Toggle("顯示今日已結束的行程", isOn: $settings.calendarShowPast)
            Toggle("顯示全天行程", isOn: $settings.calendarShowAllDay)
            Toggle("顯示跨日行程", isOn: $settings.calendarShowMultiDay)
            Toggle("顯示整個月份", isOn: $settings.calendarWholeMonth)
            Group {
                daysRow("往前顯示天數", value: $settings.calendarDaysBehind)
                daysRow("往後顯示天數", value: $settings.calendarDaysAhead)
            }
            .disabled(settings.calendarWholeMonth)
            .opacity(settings.calendarWholeMonth ? 0.45 : 1)
            LabeledContent("其他日曆設定:") {
                Button("行事曆設置") { store.openCalendarApp() }
            }
        }
        .task { await store.ensureAccess() }
    }

    @ViewBuilder private var calendarList: some View {
        if store.access == .denied {
            Text("需要「行事曆」權限。請到「授權」分頁允許。").font(.caption).foregroundStyle(.secondary)
        } else if store.calendars.isEmpty {
            Text("沒有可顯示的日曆").font(.caption).foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.calendars) { calendar in
                        CalendarCheckRow(calendar: calendar, isOn: Binding(
                            get: { store.isVisible(calendar.id) }, set: { store.setVisible(calendar.id, $0) }
                        ))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 96)
        }
    }

    private func daysRow(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            HStack {
                HapticSlider(
                    value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                    in: 0...60, step: 1
                )
                NumberField(value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                            range: 0...60, width: 48)
            }
        }
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
