import SwiftUI

/// 小膠囊: the tools that appear as islands : a live island demo, the tool list (drag to set
/// the priority, the first visible tool takes the main island) and the selected tool's settings.
struct SmallCapsuleSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var selection = "media"

    private static let islandTools = ["media", "timer", "shelf"]

    private struct Info {
        let title: String
        let symbol: String
    }

    private static let info: [String: Info] = [
        "media": Info(title: "音樂", symbol: "music.note"),
        "timer": Info(title: "計時器", symbol: "timer"),
        "shelf": Info(title: "檔案中轉站", symbol: "tray.and.arrow.down"),
        "reminders": Info(title: "待辦事項", symbol: "checklist"),
    ]

    /// Island tools in priority order (a stopwatch follows its timer).
    private var entries: [String] {
        var seen: [String] = []
        for id in settings.activityPriority {
            let entry = id == "stopwatch" ? "timer" : id
            if Self.islandTools.contains(entry), !seen.contains(entry) { seen.append(entry) }
        }
        return seen + Self.islandTools.filter { !seen.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) { IslandDemoView() }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
            HStack(alignment: .top, spacing: 14) {
                ToolListCard {
                    ReorderableList(
                        ids: entries + ["reminders"], movableCount: entries.count, rowHeight: 40,
                        move: reorder, onSelect: { id in if id != "reminders" { selection = id } },
                        row: { id in
                        if let info = Self.info[id] {
                            ToolRow(symbol: info.symbol, title: info.title, isSelected: selection == id,
                                    comingSoon: id == "reminders", isOn: enabled(id))
                        }
                        }
                    )
                }
                .frame(width: 216)
                DetailPane(minHeight: 300) { detail }
            }
        }
    }

    // MARK: List

    private func reorder(_ id: String, to index: Int) -> Bool {
        var order = entries
        guard let from = order.firstIndex(of: id), from != index else { return false }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: index > from ? index + 1 : index)
        settings.activityPriority = order.flatMap { $0 == "timer" ? ["timer", "stopwatch"] : [$0] } + ["reminders"]
        return true
    }

    private func enabled(_ id: String) -> Binding<Bool> {
        switch id {
        case "timer":
            Binding(get: { settings.activityRole("timer") != .hidden || settings.activityRole("stopwatch") != .hidden },
                    set: { on in
                        for key in ["timer", "stopwatch"] where (settings.activityRole(key) == .hidden) == on {
                            settings.setActivityRole(key, on ? .anyIsland : .hidden)
                        }
                    })
        default:
            Binding(get: { settings.activityRole(id) != .hidden },
                    set: { settings.setActivityRole(id, $0 ? .anyIsland : .hidden) })
        }
    }

    private func modeBinding(_ id: String) -> Binding<ActivityRole> {
        Binding(get: { settings.activityRole(id) == .hidden ? .anyIsland : settings.activityRole(id) },
                set: { settings.setActivityRole(id, $0) })
    }

    private func modePicker(_ title: String, id: String) -> some View {
        DropdownRow(title: title, selection: modeBinding(id), options: [
            (ActivityRole.anyIsland, "主島、副島"), (.mainOnly, "僅主島"), (.secondaryOnly, "僅副島"),
        ])
        .dimmed(when: settings.activityRole(id) == .hidden)
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        Form {
            moduleGroup(selection == "timer" ? "計時器" : (selection == "shelf" ? "檔案中轉站" : "基本"), first: true) {
                switch selection {
                case "timer":
                    modePicker("倒數顯示模式", id: "timer")
                    modePicker("碼錶顯示模式", id: "stopwatch")
                    Toggle("剩餘圓圈", isOn: $settings.timerRing)
                case "shelf":
                    modePicker("顯示模式", id: "shelf")
                    Toggle("數量", isOn: $settings.shelfShowsCount)
                    DropdownRow(title: "懸停資訊", selection: peekBinding, options: [
                        (PeekStyle.plain, "名稱 · 大小"), (.icon, "圖示 名稱 · 大小"), (.off, "關閉"),
                    ])
                default:
                    modePicker("顯示模式", id: "media")
                    Toggle("專輯封面", isOn: $settings.showCoverInCompact)
                    Toggle("音波圖", isOn: $settings.showWaveformInCompact)
                    Toggle("換歌顯示歌名", isOn: $settings.showTrackInfoOnChange)
                    SliderRow(title: "顯示時間", value: $settings.trackInfoSeconds, range: 1...8, step: 0.5, unit: "秒", fractionDigits: 1)
                        .dimmed(when: !settings.showTrackInfoOnChange)
                }
            }
            if selection == "media" {
                moduleGroup("音波") { CompactWaveformRows() }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.top, -8)
        .environment(\.sliderLength, 140)
        .id(selection)
    }

    private enum PeekStyle { case plain, icon, off }

    private var peekBinding: Binding<PeekStyle> {
        Binding(
            get: { !settings.shelfPeekEnabled ? .off : (settings.shelfPeekWithIcon ? .icon : .plain) },
            set: { style in
                settings.shelfPeekEnabled = style != .off
                if style != .off { settings.shelfPeekWithIcon = style == .icon }
            }
        )
    }
}
