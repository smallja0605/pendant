import SwiftUI

/// Calendar page: month label + magnified date strip on top, the selected day's events below.
struct CalendarView: View {
    let store: CalendarStore
    @State private var position = 0.0
    @State private var settings = AppSettings.shared

    private var selectedOffset: Int { min(max(Int(position.rounded()), range.lowerBound), range.upperBound) }
    private var range: ClosedRange<Int> {
        settings.calendarWholeMonth
            ? CalendarMath.monthRange(today: today)
            : -settings.calendarDaysBehind...settings.calendarDaysAhead
    }
    private var today: Date { CalendarMath.startOfDay(Date()) }

    /// Anything that changes which events are listed.
    private var reloadKey: String {
        [
            "\(selectedOffset)", "\(store.access)", settings.calendarHiddenIDs.joined(separator: ","),
            "\(settings.calendarShowPast)\(settings.calendarShowAllDay)\(settings.calendarShowMultiDay)",
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(CalendarMath.monthLabel(CalendarMath.day(offset: selectedOffset, from: today)))
                    .font(.system(size: Tuning.shared.calMonthSize, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, alignment: .leading)
                    .contentTransition(.numericText())
                    .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { position = 0 } }
                    .accessibilityLabel("回到今天")
                DayStrip(today: today, range: range, position: $position)
            }
            .padding(.top, 8)
            content
        }
        .task(id: reloadKey) {
            await store.ensureAccess()
            store.loadEvents(for: CalendarMath.day(offset: selectedOffset, from: today))
        }
        .onChange(of: range) { _, newRange in
            position = min(max(position, Double(newRange.lowerBound)), Double(newRange.upperBound))
        }
    }

    @ViewBuilder private var content: some View {
        switch store.access {
        case .denied:
            AccessGuide(symbol: "calendar", text: "需要「行事曆」權限才能顯示行程", pane: "Privacy_Calendars")
        case .unknown, .notDetermined:
            AccessRequest(symbol: "calendar", text: "要顯示行程,需要先允許存取「行事曆」") {
                Task { await store.ensureAccess() }
            }
        case .allowed:
            if store.events.isEmpty {
                EmptyDay(isToday: selectedOffset == 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(store.events) { event in
                            EventRow(event: event) { store.open(event) }
                        }
                    }
                    .padding(.bottom, 14) // lets the last row scroll clear of the fade
                }
                // Rows fade out towards the bottom instead of being cut off by the capsule's edge, and the list
                // ends a margin above the edge.
                .mask(
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 22)
                    }
                )
                .padding(.bottom, 10)
            }
        }
    }
}

private struct EmptyDay: View {
    let isToday: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            Text(isToday ? "今天沒有任何行程" : "這天沒有任何行程")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 8)
    }
}

private struct EventRow: View {
    let event: CalendarEventItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Color(red: event.red, green: event.green, blue: event.blue))
                    .frame(width: 3, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title.isEmpty ? "(無標題)" : event.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(CalendarMath.timeText(start: event.start, end: event.end, isAllDay: event.isAllDay))
                        if !event.location.isEmpty {
                            Label(event.location, systemImage: "mappin")
                                .labelStyle(.titleAndIcon)
                                .lineLimit(1)
                        }
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.1 : 0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onActiveHover { hovering = $0 != nil }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Shown when a permission was refused: explanation and a shortcut to System Settings.
struct AccessGuide: View {
    let symbol: String
    let text: String
    let pane: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
            Text(text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
            Button("開啟系統設定") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.16)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 8)
    }
}

/// Shown before the permission has been decided: explains why and lets the user trigger the system prompt.
struct AccessRequest: View {
    let symbol: String
    let text: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(.white.opacity(0.4))
            Text(text).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.65)).multilineTextAlignment(.center)
            Button("允許存取", action: action)
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(.white))
                .hapticOnHover()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 8)
    }
}
