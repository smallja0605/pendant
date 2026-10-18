import SwiftUI

/// Everything beyond title and date for a new reminder, laid out like the Calendar / Reminders apps' own sheet:
/// notes and URL, date and time, urgent, repeat, early alert, list and priority. Shown in an `NSPopover`.
struct ReminderOptionsView: View {
    @Binding var draft: ReminderDraft
    let lists: [ReminderListInfo]

    static let width: CGFloat = 300

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                group {
                    TextField("附註", text: $draft.notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(.vertical, 9)
                    divider
                    TextField("URL", text: $draft.url).textFieldStyle(.plain).padding(.vertical, 9)
                }
                header("日期與時間")
                group {
                    toggleRow("calendar", "日期", subtitle: draft.due.map { $0.formatted(date: .abbreviated, time: .omitted) },
                              isOn: Binding(get: { draft.due != nil }, set: { draft.due = $0 ? (draft.due ?? Date()) : nil }))
                    if draft.due != nil {
                        divider
                        DatePicker("", selection: Binding(get: { draft.due ?? Date() }, set: { draft.due = $0 }),
                                   displayedComponents: .date)
                            .labelsHidden().padding(.vertical, 6)
                        divider
                        toggleRow("clock", "時間", subtitle: draft.includeTime ? draft.due?.formatted(date: .omitted, time: .shortened) : nil,
                                  isOn: $draft.includeTime)
                        if draft.includeTime {
                            DatePicker("", selection: Binding(get: { draft.due ?? Date() }, set: { draft.due = $0 }),
                                       displayedComponents: .hourAndMinute)
                                .labelsHidden().padding(.bottom, 6)
                        }
                    }
                    divider
                    toggleRow("alarm", "緊急", subtitle: nil, isOn: $draft.urgent)
                }
                note("將此提醒事項標示為緊急,到期時立即提醒(未設日期時會自動設為今天)。")
                group {
                    pickerRow("repeat", "重複", selection: $draft.repeatRule, options: ReminderRepeat.allCases, title: \.title)
                    divider
                    pickerRow("bell", "提前提醒", selection: $draft.earlyAlert, options: ReminderEarlyAlert.allCases, title: \.title)
                }
                header("整理功能")
                group {
                    listRow
                    divider
                    pickerRow("exclamationmark", "重要性", selection: $draft.priority,
                              options: ReminderPriorityChoice.allCases, title: \.title)
                }
                note("標籤、旗標、位置、訊息觸發與影像無法透過 EventKit 設定,因此沒有提供。")
            }
            .font(.system(size: 12.5))
            .foregroundStyle(.white)
            .padding(12)
        }
        .frame(width: Self.width, height: 440)
        // Urgent / repeat / early alert only mean something with a due date: choosing one sets today.
        .onChange(of: draft.urgent) { _, on in
            guard on else { return }
            if draft.due == nil { draft.due = Date() }
            draft.includeTime = true
        }
        .onChange(of: draft.repeatRule) { _, rule in if rule != .never, draft.due == nil { draft.due = Date() } }
        .onChange(of: draft.earlyAlert) { _, alert in
            guard alert != .none else { return }
            if draft.due == nil { draft.due = Date() }
            draft.includeTime = true
        }
    }

    // MARK: Pieces

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.1)))
    }

    private var divider: some View { Divider().overlay(.white.opacity(0.12)) }

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.55)).padding(.leading, 4)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).padding(.horizontal, 4)
    }

    private func toggleRow(_ symbol: String, _ title: String, subtitle: String?, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(.white.opacity(0.7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)) }
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.vertical, 8)
    }

    private func pickerRow<Value: Hashable>(
        _ symbol: String, _ title: String, selection: Binding<Value>, options: [Value], title label: KeyPath<Value, String>
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(.white.opacity(0.7))
            Text(title)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { Text($0[keyPath: label]).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 6)
    }

    private var listRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet").frame(width: 20).foregroundStyle(.white.opacity(0.7))
            Text("列表")
            Spacer()
            Picker("", selection: Binding(get: { draft.listID ?? "" }, set: { draft.listID = $0.isEmpty ? nil : $0 })) {
                Text("預設").tag("")
                ForEach(lists) { list in
                    Label {
                        Text(list.title)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(Color(red: list.red, green: list.green, blue: list.blue))
                    }
                    .tag(list.id)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 6)
    }
}
