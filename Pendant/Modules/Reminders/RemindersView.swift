import SwiftUI

/// Reminders page: lists with their open items, check to complete, quick add at the bottom.
struct RemindersView: View {
    let store: RemindersStore
    @State private var settings = AppSettings.shared

    private var reloadKey: String {
        [
            "\(store.access)", settings.remindersHiddenListIDs.joined(separator: ","), "\(settings.remindersShowCompleted)",
            settings.remindersSort.rawValue, "\(settings.remindersLimit)",
        ].joined(separator: "|")
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("待辦事項").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                Spacer()
                if store.access == .allowed {
                    Text("\(store.totalIncomplete)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.12)))
                }
            }
            .frame(height: 28)
            .padding(.top, ModuleHeader.topPadding(rowHeight: 28)) // on the calendar's month-label line
            content
            if store.access == .allowed { QuickAddRow(store: store) }
        }
        .padding(.bottom, 8)
        .onDisappear { store.flushCompleted() }
        .task(id: reloadKey) {
            await store.ensureAccess()
            await store.reload()
        }
    }

    @ViewBuilder private var content: some View {
        switch store.access {
        case .denied:
            AccessGuide(symbol: "checklist", text: "需要「提醒事項」權限才能顯示待辦", pane: "Privacy_Reminders")
        case .unknown, .notDetermined:
            AccessRequest(symbol: "checklist", text: "要顯示待辦事項,需要先允許存取「提醒事項」") {
                Task { await store.ensureAccess() }
            }
        case .allowed:
            if store.groups.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle").font(.system(size: 22)).foregroundStyle(.white.opacity(0.45))
                    Text("沒有待辦事項").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Iterate a snapshot with stable ids: indexing the live array crashed when it shrank mid-update.
                        ForEach(store.groups.filter { !$0.isEmpty }, id: \.first?.listID) { group in
                            if let first = group.first {
                                ListHeader(title: first.listTitle, color: Color(red: first.red, green: first.green, blue: first.blue))
                                ForEach(group) { item in
                                    // swiftlint:disable:next multiple_closures_with_trailing_closure
                                    SwipeToDelete(onDelete: { Task { await store.delete(item) } }) {
                                        ReminderRow(item: item) { done in Task { await store.setCompleted(item, done) } }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Two-finger swipe left on a row, in three stages (like Mail): (1) swiping — let go before the haptic and it springs
/// back; (2) past the first haptic the delete pill stays open, even after the fingers leave the trackpad; (3) past the
/// second haptic the pill fills the whole row and letting go deletes. The row's text stays visible (it is squeezed,
/// not covered) until the pill fills the row.
private struct SwipeToDelete<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 240
    @State private var height: CGFloat = 30
    @State private var swiping = false
    @State private var decided = false
    @State private var armed = false
    @State private var fullArmed = false
    @State private var collapsed = false
    @State private var settleTask: Task<Void, Never>?
    @State private var hovering = false

    private let arm: CGFloat = 34
    private let openWidth: CGFloat = 52
    private var full: CGFloat { max(width * 0.6, 110) }

    var body: some View {
        let amount = -offset
        let pillWidth = amount > 0 ? min(max(amount - 6, 0), width - 4) : 0
        ZStack(alignment: .trailing) {
            // The whole row (with its highlight) slides left, its left part falls out of view, while the text inside
            // is pushed back right by the same amount, so the text stays where it was until the pill covers it.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(hovering || amount > 0 ? 0.1 : 0))
                content
                    .padding(.horizontal, 6)
                    .offset(x: amount)
                    .opacity(amount > width * 0.82 ? 0 : 1)
            }
            // Flexible, not `width`: a fixed frame of the measured width could never get narrower than its first value (the
            // measurement saw the frame itself), and the list overflowed the module on both sides.
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(x: -amount)
            Button {
                HapticService.shared.play(.stateSettled)
                remove()
            } label: {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.red)
                    // Always centred in the pill until stage 3 (full swipe), where it moves to the pill's left end.
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 14)
                        .offset(x: (amount >= full ? 26 : pillWidth / 2) - 7)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: amount >= full)
                        .opacity(pillWidth > 18 ? 1 : 0)
                }
                .frame(width: pillWidth, height: 28)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
            .opacity(amount > 2 ? 1 : 0)
            .allowsHitTesting(amount > arm)
            .accessibilityLabel("刪除")
        }
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width; if !collapsed { height = proxy.size.height } }
                .onChange(of: proxy.size) { _, size in width = size.width; if !collapsed { height = size.height } }
        })
        .animation(.easeOut(duration: 0.12), value: hovering)
        .clipped()
        .onActiveHover { hovering = $0 != nil }
        .frame(height: collapsed ? 0 : nil)
        .opacity(collapsed ? 0 : 1)
        .clipped()
        .onScrollWheelPhased { deltaX, deltaY, phase in handle(deltaX, deltaY, phase) }
    }

    private func handle(_ deltaX: Double, _ deltaY: Double, _ phase: ScrollPhase) -> Bool {
        if phase.momentum { return swiping } // inertia after the fingers left: swallow it, nothing more to do
        // A gesture is claimed by its first moving event, by direction; vertical gestures stay with the list.
        if phase.began || !phase.hasPhase { decided = false }
        if !decided, deltaX != 0 || deltaY != 0 {
            swiping = abs(deltaX) > abs(deltaY)
            decided = true
        }
        if phase.ended { decided = false }
        guard swiping else { return false }
        settleTask?.cancel()
        let next = min(max(offset + deltaX, -width), 0)
        withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.9)) { offset = next }
        updateHaptics()
        if phase.ended {
            finish()
        } else if !phase.hasPhase {
            settleTask = Task { // a mouse wheel has no "fingers lifted": a short pause counts as letting go
                try? await Task.sleep(for: .milliseconds(160))
                guard !Task.isCancelled else { return }
                finish()
            }
        }
        return true
    }

    private func updateHaptics() {
        let amount = -offset
        if (amount >= arm) != armed {
            armed = amount >= arm
            if armed { HapticService.shared.play(.stateSettled) }
        }
        if (amount >= full) != fullArmed {
            fullArmed = amount >= full
            if fullArmed { HapticService.shared.play(.stateSettled) }
        }
    }

    private func finish() {
        swiping = false
        let amount = -offset
        if amount >= full {
            remove()
        } else {
            let target: CGFloat = amount >= arm ? -openWidth : 0
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { offset = target }
            armed = target != 0
            fullArmed = false
        }
    }

    private func remove() {
        swiping = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { offset = -width }
        Task {
            try? await Task.sleep(for: .milliseconds(160))
            withAnimation(.easeIn(duration: 0.22)) { collapsed = true }
            try? await Task.sleep(for: .milliseconds(230))
            onDelete()
        }
    }
}

private struct ListHeader: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let setCompleted: (Bool) -> Void

    var body: some View {
        let color = Color(red: item.red, green: item.green, blue: item.blue)
        HStack(spacing: 8) {
            Button { setCompleted(!item.isCompleted) } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(item.isCompleted ? color : .white.opacity(0.55))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hapticOnHover()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    let marks = RemindersMath.priorityMarks(item.priority)
                    if !marks.isEmpty { Text(marks).font(.system(size: 11, weight: .heavy)).foregroundStyle(.orange) }
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(item.isCompleted ? 0.4 : 1))
                        .strikethrough(item.isCompleted)
                        .lineLimit(1)
                }
                if let due = item.due {
                    let info = RemindersMath.dueText(due: due, hasTime: item.dueHasTime, now: Date())
                    Text(info.text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(info.overdue ? Color.red.opacity(0.9) : .white.opacity(0.45))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 26)
    }
}

/// Title + Enter (or the send button) adds a reminder to the default list; the calendar button picks an
/// optional due date.
private struct QuickAddRow: View {
    let store: RemindersStore
    @State private var draft = ReminderDraft()
    @State private var popover = AnchoredPopover()
    @State private var optionsPopover = AnchoredPopover()
    @FocusState private var focused: Bool

    private var title: String { draft.title }
    private var canSend: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var dueBinding: Binding<Date?> { Binding(get: { draft.due }, set: { draft.due = $0 }) }

    var body: some View {
        // Two rows in one box: the title on top, the controls underneath (date, options on the left, send on the right).
        VStack(spacing: 2) {
            TextField(text: $draft.title, prompt: Text("新增待辦⋯").foregroundStyle(.white.opacity(0.45))) { EmptyView() }
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
                .focused($focused)
                .onSubmit(submit)
                .frame(height: 22)
            HStack(spacing: 6) {
                Button {
                    popover.toggle(size: .zero, autoSize: true) { _ in
                        AnyView(DuePicker(due: dueBinding, includeTime: $draft.includeTime))
                    }
                } label: {
                    Image(systemName: draft.due == nil ? "calendar" : "calendar.badge.clock")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(draft.due == nil ? .white.opacity(0.6) : Color.blue)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(PopoverAnchor(popover: popover))
                .hapticOnHover()
                Button {
                    optionsPopover.toggle(size: .zero, autoSize: true) { _ in
                        AnyView(ReminderOptionsView(draft: $draft, lists: store.lists))
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(draft.hasOptions ? Color.blue : .white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(PopoverAnchor(popover: optionsPopover))
                .hapticOnHover()
                .accessibilityLabel("更多選項")
                Spacer(minLength: 0)
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(canSend ? Color.white : .white.opacity(0.25))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .hapticOnHover()
                .accessibilityLabel("新增待辦")
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(focused ? 0.16 : 0.09)))
        #if DEBUG
        .task {
            // PENDANT_DEBUG_DUE=1 opens the due-date popover shortly after the page appears (visual check).
            guard let mode = ProcessInfo.processInfo.environment["PENDANT_DEBUG_DUE"] else { return }
            try? await Task.sleep(for: .seconds(1.2))
            if mode == "options" {
                draft.due = Date()
                optionsPopover.toggle(size: .zero, autoSize: true) { _ in
                    AnyView(ReminderOptionsView(draft: $draft, lists: store.lists))
                }
                return
            }
            popover.toggle(size: .zero, autoSize: true) { _ in
                AnyView(DuePicker(due: dueBinding, includeTime: $draft.includeTime))
            }
        }
        #endif
    }

    private func submit() {
        guard canSend else { return }
        let pending = draft
        draft = ReminderDraft()
        popover.close()
        optionsPopover.close()
        Task { await store.add(pending) }
    }
}

/// Graphical date picker scaled up to fill a 250 pt-wide popover (the size the user liked), with a small margin
/// and no empty space below; the popover sizes itself to this view.
private struct DuePicker: View {
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
