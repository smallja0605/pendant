import SwiftUI

/// Graphical date picker scaled up to fill a 250 pt-wide popover (the size the user liked), with a small margin
/// and no empty space below; the popover sizes itself to this view.
struct DuePicker: View {
    @Binding var due: Date?
    @Binding var includeTime: Bool
    @State private var date = Date()

    var body: some View {
        VStack(spacing: 6) {
            CalendarPicker(date: $date)
                .onChange(of: date) { _, newValue in due = newValue }
            if includeTime {
                DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            HStack {
                Toggle("包含時間", isOn: $includeTime)
                Spacer()
                Button("清除") { due = nil }
            }
        }
        .padding(10)
        .fixedSize()
        .onAppear { date = due ?? Date(); due = due ?? date }
    }
}
