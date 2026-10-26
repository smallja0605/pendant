import SwiftUI

/// Reminders page: lists with their open items, check to complete, quick add at the bottom.
struct RemindersView: View {
    let store: RemindersStore
    /// The detailed page: the list on the left, a tall box for a new item on the right.
    var focused = false
    @State private var settings = AppSettings.shared
    @State private var registry = ModuleRegistry.shared
    @State private var focusSettings = FocusCapsuleSettings.shared
    /// The page's body is the new-item box instead of the list (the + button in the header; 擠換).
    @State private var adding = false
    /// The box stays mounted while it swaps out, so it can fade away.
    @State private var addMounted = false

    private var reloadKey: String {
        [
            "\(store.access)", settings.remindersHiddenListIDs.joined(separator: ","), "\(settings.remindersShowCompleted)",
            settings.remindersSort.rawValue, "\(settings.remindersLimit)",
        ].joined(separator: "|")
    }

    var body: some View {
        Group {
            if focused { split } else { page }
        }
        .padding(.bottom, focused ? 20 : 8)
        .overlay(alignment: .bottom) {
            if focused, focusSettings.remindersHandle != 2 { HeightGrip(hidesUntilHover: focusSettings.remindersHandle == 1) }
        }
        .onDisappear {
            store.flushCompleted()
            adding = false
            addMounted = false
        }
        .task(id: reloadKey) {
            await store.ensureAccess()
            await store.reload()
        }
        #if DEBUG
        .task {
            // PENDANT_DEBUG_REMINDER_ADD=1 presses the + a few seconds after the page appears (visual check of 擠換).
            guard ProcessInfo.processInfo.environment["PENDANT_DEBUG_REMINDER_ADD"] != nil else { return }
            try? await Task.sleep(for: .seconds(3.5))
            setAdding(true)
        }
        #endif
    }

    private var countBadge: some View {
        Text("\(store.totalIncomplete)")
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.12)))
    }

    private var page: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Text("待辦事項").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                FocusEnterButton().padding(.leading, 2)
                Spacer()
                if store.access == .allowed {
                    addButton.padding(.trailing, 8)
                    countBadge
                }
            }
            .frame(height: 28)
            .padding(.top, ModuleHeader.topPadding(rowHeight: 28)) // on the calendar's month-label line
            // 擠換: the list and the new-item box take each other's place (the old one blurs out as the new one comes in).
            ZStack {
                content
                    .modifier(SqueezeSwap(isShown: !adding))
                    .allowsHitTesting(!adding)
                if addMounted {
                    QuickAddRow(store: store, tall: true, autoFocus: true, onDone: { setAdding(false) })
                        .padding(.bottom, 2)
                        .modifier(SqueezeSwap(isShown: adding))
                        .allowsHitTesting(adding)
                }
            }
        }
    }

    /// The + in the header: opens the new-item box; turns into a × to go back to the list.
    private var addButton: some View {
        Button { setAdding(!adding) } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .rotationEffect(.degrees(adding ? 45 : 0))
                .frame(width: 26, height: 22)
                .background(Capsule().fill(.white.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hapticOnHover()
        .accessibilityLabel(adding ? "回到清單" : "新增待辦")
    }

    private func setAdding(_ on: Bool) {
        if on { addMounted = true }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { adding = on }
        guard !on else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            if !adding { addMounted = false }
        }
    }

    private var split: some View {
        GeometryReader { proxy in
            let divider: CGFloat = 20
            let room = max(proxy.size.width - divider, 1)
            let listWidth = room * registry.focusSplit
            HStack(spacing: 0) {
                // The count sits on the category's own line (top right), not on a line of its own.
                content
                    .overlay(alignment: .topTrailing) {
                        if store.access == .allowed { countBadge.padding(.top, 2) }
                    }
                    .padding(.top, 6)
                    .frame(width: listWidth)
                SplitDivider(room: room)
                    .frame(width: divider)
                if store.access == .allowed {
                    QuickAddRow(store: store, tall: true, usesPageDefaults: true)
                        .padding(.top, 6)
                        .frame(width: room - listWidth)
                }
            }
        }
        .padding(.bottom, 12) // the height handle sits under the boxes
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
                    // The category line stays at the top while its items scroll, and gives way to the next category.
                    LazyVStack(alignment: .leading, spacing: 2, pinnedViews: [.sectionHeaders]) {
                        // Iterate a snapshot with stable ids: indexing the live array crashed when it shrank mid-update.
                        ForEach(store.groups.filter { !$0.isEmpty }, id: \.first?.listID) { group in
                            if let first = group.first {
                                Section {
                                    ForEach(group) { item in
                                        // swiftlint:disable:next multiple_closures_with_trailing_closure
                                        SwipeToDelete(onDelete: { Task { await store.delete(item) } }) {
                                            ReminderRow(item: item) { done in Task { await store.setCompleted(item, done) } }
                                        }
                                    }
                                } header: {
                                    ListHeader(title: first.listTitle, color: Color(red: first.red, green: first.green, blue: first.blue))
                                }
                            }
                        }
                    }
                }
            }
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
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black) // pinned: the items scroll under it
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
    /// Fills the height it is given, and the title can run over several lines (the detailed page).
    var tall = false
    /// Puts the cursor in the title field shortly after the box appears (the page's new-item box).
    var autoFocus = false
    /// A new item starts with the priority / due date / list chosen in 設定 › 獨立膠囊 › 待辦事項 (the detailed page's box).
    var usesPageDefaults = false
    /// Called after an item was added or Esc was pressed.
    var onDone: (() -> Void)?
    @State private var draft = ReminderDraft()
    @State private var popover = AnchoredPopover()
    @State private var optionsPopover = AnchoredPopover()
    @FocusState private var focused: Bool

    /// An empty draft, with the page's defaults when this is the detailed page's box.
    private func freshDraft() -> ReminderDraft {
        var draft = ReminderDraft()
        guard usesPageDefaults else { return draft }
        let settings = FocusCapsuleSettings.shared
        draft.priority = [.none, .low, .medium, .high][min(max(settings.remindersDefaultPriority, 0), 3)]
        let today = Calendar.current.startOfDay(for: Date())
        switch settings.remindersDefaultDue {
        case 1: draft.due = today
        case 2: draft.due = Calendar.current.date(byAdding: .day, value: 1, to: today)
        case 3:
            draft.due = Date().addingTimeInterval(3600)
            draft.includeTime = true
        default: break
        }
        if !settings.remindersDefaultList.isEmpty, store.lists.contains(where: { $0.id == settings.remindersDefaultList }) {
            draft.listID = settings.remindersDefaultList
        }
        return draft
    }

    private var title: String { draft.title }
    private var canSend: Bool { !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var dueBinding: Binding<Date?> { Binding(get: { draft.due }, set: { draft.due = $0 }) }

    var body: some View {
        // Two rows in one box: the title on top, the controls underneath (date, options on the left, send on the right).
        VStack(spacing: 2) {
            let prompt = Text("新增待辦⋯").foregroundStyle(.white.opacity(0.45))
            TextField(text: $draft.title, prompt: prompt, axis: tall ? .vertical : .horizontal) {
                EmptyView()
            }
            .textFieldStyle(.plain)
            .font(.system(size: tall ? 14 : 12.5))
            .foregroundStyle(.white)
            .focused($focused)
            .onSubmit(submit)
            .frame(maxWidth: .infinity, maxHeight: tall ? .infinity : 22, alignment: .topLeading)
            .frame(height: tall ? nil : 22)
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
        .onExitCommand { onDone?() }
        .onAppear { if draft == ReminderDraft() { draft = freshDraft() } }
        .task {
            guard autoFocus else { return }
            try? await Task.sleep(for: .milliseconds(250))
            focused = true
        }
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
        draft = freshDraft()
        popover.close()
        optionsPopover.close()
        Task { await store.add(pending) }
        onDone?()
    }
}
