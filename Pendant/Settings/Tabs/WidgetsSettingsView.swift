import SwiftUI

/// 大膠囊: a live, sortable model of the capsule (tabs on top, tools in a row), the tool list and the selected tool's settings.
/// Drag a tool to reorder it, drop it on a tab to move it there; clicking a tool selects it in the list.
struct WidgetsSettingsView: View {
    @State private var registry = ModuleRegistry.shared
    @State private var selection: String? = "media"
    @State private var tabSelection = TabConfig.mainID
    @State private var tabFrames: [String: CGRect] = [:]
    @State private var dropTab: String?

    private var tab: TabConfig? { registry.tabs.first { $0.id == tabSelection } ?? registry.tabs.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            demo
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    ToolListCard {
                        ReorderableList(
                            ids: registry.order, rowHeight: 40,
                            move: { id, index in registry.move(id, toIndex: index) },
                            onSelect: { id in
                                guard ModuleDescriptor.descriptor(for: id)?.selectable == true else { return }
                                selection = id
                                if let home = registry.primaryTabID(of: id) { tabSelection = home }
                            },
                            row: { id in
                            if let descriptor = ModuleDescriptor.descriptor(for: id) {
                                let index = registry.order.firstIndex(of: id) ?? 0
                                ToolRow(symbol: descriptor.symbolName, title: descriptor.title, isSelected: selection == id,
                                        comingSoon: !descriptor.selectable,
                                        arrows: descriptor.selectable ? (index > 0, index < registry.order.count - 1) : nil,
                                        onArrow: { delta in
                                            if registry.move(id, toIndex: index + delta) { HapticService.shared.play(.dragStep) }
                                        },
                                        isOn: Binding(get: { registry.isEnabled(id) }, set: { registry.setEnabled(id, $0) }))
                            }
                            }
                        )
                    }
                    Button("還原預設") { registry.resetToDefaults(); tabSelection = TabConfig.mainID }
                        .controlSize(.small)
                }
                .frame(width: 216)
                DetailPane(minHeight: 400) {
                    if let id = selection, ModuleDescriptor.descriptor(for: id)?.selectable == true,
                       let module = registry.module(for: id) {
                        module.makeSettingsView().id(id)
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }

    private var demo: some View {
        VStack(spacing: 8) {
            TabChips(registry: registry, selection: $tabSelection, dropTab: dropTab)
            if let tab, tab.id != TabConfig.mainID { TabNameRow(registry: registry, tab: tab, selection: $tabSelection) }
            if let tab {
                PreviewBar(
                    registry: registry, tabID: tab.id, selection: $selection, tabFrames: tabFrames, dropTab: $dropTab,
                    onMoveToTab: { id, target in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            registry.moveModule(id, toTab: target)
                            tabSelection = target
                        }
                    }
                )
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.07)))
        .coordinateSpace(name: "bigDemo")
        .onPreferenceChange(TabPillFrames.self) { tabFrames = $0 }
    }
}

// MARK: - Preview bar

/// Black bar showing the enabled modules in order, widths proportional to their cells (it hugs its content, like
/// the capsule). Drag a tile to reorder it live; hovering a tile shows ◀ ▶ buttons.
private struct PreviewBar: View {
    let registry: ModuleRegistry
    let tabID: String
    @Binding var selection: String?
    let tabFrames: [String: CGRect]
    @Binding var dropTab: String?
    let onMoveToTab: (String, String) -> Void

    /// The modules of the selected tab, in display order (read fresh: the order changes while dragging).
    private var ids: [String] {
        registry.tabs.first { $0.id == tabID }.map(registry.modules(in:)) ?? []
    }

    private let cellPoints: CGFloat = 28
    private let spacing: CGFloat = 6

    @State private var draggingID: String?
    @State private var dragX: CGFloat = 0
    @State private var grabOffset: CGFloat = 0
    @State private var rowFrame = CGRect.zero
    @State private var hoveringID: String?

    private func width(_ id: String) -> CGFloat { max(CGFloat(registry.cells(for: id)) * cellPoints, 56) }

    /// Left edge of `id` inside the tile row for `ids`.
    private func originX(of id: String, in ids: [String]) -> CGFloat {
        var offset: CGFloat = 0
        for other in ids {
            if other == id { return offset }
            offset += width(other) + spacing
        }
        return 0
    }

    private func rowWidth(_ ids: [String]) -> CGFloat {
        ids.reduce(0) { $0 + width($1) } + spacing * CGFloat(max(ids.count - 1, 0))
    }

    var body: some View {
        // Many tiles shrink the whole bar to fit the available width instead of running out of the window.
        GeometryReader { proxy in
            let natural = (ids.isEmpty ? 160 : rowWidth(ids)) + 16
            let scale = min(1, proxy.size.width / max(natural, 1))
            bar(ids)
                .frame(width: proxy.size.width / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: proxy.size.width, height: 70 * scale, alignment: .topLeading)
        }
        .frame(height: 70)
    }

    private func bar(_ ids: [String]) -> some View {
        HStack {
            Spacer(minLength: 0)
            ZStack(alignment: .topLeading) {
                if ids.isEmpty {
                    Text("沒有啟用的小工具").font(.caption).foregroundStyle(.white.opacity(0.6)).frame(minWidth: 160, minHeight: 54)
                }
                ForEach(ids, id: \.self) { id in
                    if let descriptor = ModuleDescriptor.descriptor(for: id) {
                        tile(descriptor, ids: ids)
                    }
                }
            }
            .coordinateSpace(name: "previewRow")
            .background(GeometryReader { proxy in
                Color.clear.onAppear { rowFrame = proxy.frame(in: .named("bigDemo")) }
                    .onChange(of: proxy.frame(in: .named("bigDemo"))) { _, new in rowFrame = new }
            })
            .frame(width: ids.isEmpty ? nil : rowWidth(ids), height: 54, alignment: .topLeading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: ids)
            Spacer(minLength: 0)
        }
    }

    private func tile(_ descriptor: ModuleDescriptor, ids: [String]) -> some View {
        let id = descriptor.id
        let dragging = draggingID == id
        let index = ids.firstIndex(of: id) ?? 0
        return VStack(spacing: 3) {
            Image(systemName: descriptor.symbolName).font(.system(size: 13, weight: .semibold))
            Text(descriptor.title).font(.system(size: 10, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(.white)
        .frame(width: width(id), height: 54)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(selection == id ? 0.28 : 0.12)))
        .overlay(alignment: .leading) { arrow("chevron.left", visible: hoveringID == id && index > 0 && !dragging) { shift(id, -1) } }
        .overlay(alignment: .trailing) {
            arrow("chevron.right", visible: hoveringID == id && index < ids.count - 1 && !dragging) { shift(id, 1) }
        }
        .onHover { hoveringID = $0 ? id : (hoveringID == id ? nil : hoveringID) }
        .scaleEffect(dragging ? 1.05 : 1)
        .offset(x: dragging ? dragX : originX(of: id, in: ids))
        .zIndex(dragging ? 1 : 0)
        .transaction { if dragging { $0.animation = nil } }
        .onTapGesture { selection = id }
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("previewRow"))
                .onChanged { value in
                    if draggingID != id {
                        draggingID = id
                        selection = id
                        grabOffset = value.startLocation.x - originX(of: id, in: ids)
                    }
                    dragX = min(max(value.location.x - grabOffset, 0), max(rowWidth(ids) - width(id), 0))
                    reorder(id)
                    let point = CGPoint(x: rowFrame.minX + value.location.x, y: rowFrame.minY + value.location.y)
                    dropTab = tabFrames.first { $0.value.insetBy(dx: -6, dy: -8).contains(point) }?.key
                }
                .onEnded { _ in
                    if let target = dropTab { onMoveToTab(id, target) }
                    dropTab = nil
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { draggingID = nil }
                }
        )
    }

    /// Swaps with a neighbour whenever the dragged tile's centre passes the neighbour's centre.
    private func reorder(_ id: String) {
        for _ in 0..<ids.count {
            let ids = self.ids
            guard let index = ids.firstIndex(of: id) else { return }
            let dragged = dragX + width(id) / 2
            if index + 1 < ids.count, dragged > originX(of: ids[index + 1], in: ids) + width(ids[index + 1]) / 2,
               registry.shift(id, by: 1, within: ids) {
                HapticService.shared.play(.dragStep)
            } else if index > 0, dragged < originX(of: ids[index - 1], in: ids) + width(ids[index - 1]) / 2,
                      registry.shift(id, by: -1, within: ids) {
                HapticService.shared.play(.dragStep)
            } else {
                return
            }
        }
    }

    private func shift(_ id: String, _ delta: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if registry.shift(id, by: delta, within: ids) { HapticService.shared.play(.dragStep) }
        }
    }

    /// Fades in and out with the pointer (always laid out, so it never pops).
    private func arrow(_ symbol: String, visible: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 18, height: 30)
                .background(Capsule().fill(.white.opacity(0.22)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 3)
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.8)
        .allowsHitTesting(visible)
        .animation(.easeOut(duration: 0.28), value: visible)
    }
}
