import SwiftUI

/// Month calendar for picking a day: month title with ◀ ● ▶, weekday row, 7 × 6 grid. Drawn by hand (instead of the
/// system date picker) so there is no frame around it and the selection highlight is centred on its day number.
struct CalendarPicker: View {
    @Binding var date: Date
    @State private var shownMonth = Date()
    @State private var hoveredDay: Date?

    private static let cell = CGSize(width: 34, height: 30)
    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(shownMonth, format: .dateTime.year().month(.wide))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                navButton("chevron.left") { shift(-1) }
                navButton("circle.fill", size: 7) { shownMonth = Date() }
                navButton("chevron.right") { shift(1) }
            }
            .padding(.horizontal, 6)
            HStack(spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                        .frame(width: Self.cell.width)
                }
            }
            Divider().overlay(.white.opacity(0.15))
            VStack(spacing: 0) {
                ForEach(weeks, id: \.self) { week in
                    HStack(spacing: 0) { ForEach(week, id: \.self) { day in dayCell(day) } }
                }
            }
        }
        .frame(width: Self.cell.width * 7)
        .onAppear { shownMonth = date }
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = calendar.isDate(day, equalTo: shownMonth, toGranularity: .month)
        let selected = calendar.isDate(day, inSameDayAs: date)
        let today = calendar.isDateInToday(day)
        let hovering = hoveredDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        return Text("\(calendar.component(.day, from: day))")
            .font(.system(size: 14, weight: selected ? .bold : .medium).monospacedDigit())
            .foregroundStyle(today ? Color.blue : .white.opacity(inMonth ? 1 : 0.28))
            .frame(width: Self.cell.width, height: Self.cell.height)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.white.opacity(selected ? 0.24 : (hovering ? 0.12 : 0)))
                    .padding(2)
            )
            .contentShape(Rectangle())
            .onTapGesture { select(day) }
            .onActiveHover { hoveredDay = $0 != nil ? day : (hovering ? nil : hoveredDay) }
    }

    private func navButton(_ symbol: String, size: CGFloat = 11, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .bold)).foregroundStyle(.white.opacity(0.6))
                .frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayLabels: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Six weeks covering the shown month.
    private var weeks: [[Date]] {
        guard let month = calendar.dateInterval(of: .month, for: shownMonth),
              let start = calendar.dateInterval(of: .weekOfMonth, for: month.start)?.start else { return [] }
        return (0..<6).map { week in
            (0..<7).compactMap { calendar.date(byAdding: .day, value: week * 7 + $0, to: start) }
        }
    }

    private func shift(_ months: Int) {
        shownMonth = calendar.date(byAdding: .month, value: months, to: shownMonth) ?? shownMonth
    }

    /// Picks the day, keeping the time of day of the current value.
    private func select(_ day: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = time.hour
        parts.minute = time.minute
        date = calendar.date(from: parts) ?? day
        if !calendar.isDate(day, equalTo: shownMonth, toGranularity: .month) { shownMonth = day }
    }
}
