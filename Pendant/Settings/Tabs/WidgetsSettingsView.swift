import SwiftUI

/// 4.10 Custom widgets: ordered list with switches, a live preview bar of the capsule, and the selected
/// module's own settings. Everything applies to the capsule immediately and is persisted. Reordering is live
/// (items move under the pointer, one haptic per position) and also available through hover arrows.
struct WidgetsSettingsView: View {
    @State private var registry = ModuleRegistry.shared
    @State private var selection: String? = "media"
    @State private var tabSelection = TabConfig.mainID

    private var tab: TabConfig? { registry.tabs.first { $0.id == tabSelection } ?? registry.tabs.first }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ModuleList(registry: registry, selection: $selection)
                .frame(width: 270)
            VStack(alignment: .leading, spacing: 12) {
                TabChips(registry: registry, selection: $tabSelection)
                if let tab {
                    TabNameRow(registry: registry, tab: tab, selection: $tabSelection)
                    PreviewBar(registry: registry, tabID: tab.id, selection: $selection)
                }
                Divider()
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if let tab { TabModuleChecklist(registry: registry, tab: tab) }
                        if let id = selection, let descriptor = ModuleDescriptor.descriptor(for: id) {
                            Divider()
                            ModuleDetail(registry: registry, descriptor: descriptor)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Spacer()
                    Button("還原預設") { registry.resetToDefaults(); tabSelection = TabConfig.mainID }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
    }
}

// MARK: - List

struct ModuleList: View {
    let registry: ModuleRegistry
    @Binding var selection: String?

    static let rowHeight: CGFloat = 48

    @State private var draggingID: String?
    @State private var dragY: CGFloat = 0
    @State private var grabOffset: CGFloat = 0

    var body: some View {
        let order = registry.order
        ScrollView(.vertical, showsIndicators: false) {
            // Absolute positions: the dragged row follows the pointer directly (no animation), the others spring
            // to their slots, so nothing is ever drawn twice or offset twice.
            ZStack(alignment: .topLeading) {
                ForEach(registry.descriptors) { descriptor in
                    let index = order.firstIndex(of: descriptor.id) ?? 0
                    let dragging = draggingID == descriptor.id
                    ModuleRow(
                        registry: registry, descriptor: descriptor, isSelected: selection == descriptor.id,
                        canMoveUp: index > 0, canMoveDown: index < order.count - 1
                    ) { delta in
                        if registry.move(descriptor.id, toIndex: index + delta) { HapticService.shared.play(.dragStep) }
                    }
                    .offset(y: dragging ? dragY : CGFloat(index) * Self.rowHeight)
                    .zIndex(dragging ? 1 : 0)
                    .shadow(color: .black.opacity(dragging ? 0.25 : 0), radius: 6, y: 2)
                    .transaction { if dragging { $0.animation = nil } }
                    .onTapGesture { selection = descriptor.id }
                    .gesture(drag(for: descriptor.id))
                }
            }
            .frame(maxWidth: .infinity, minHeight: CGFloat(order.count) * Self.rowHeight, alignment: .topLeading)
            .coordinateSpace(name: "moduleList")
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: order)
        }
    }

    private func drag(for id: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("moduleList"))
            .onChanged { value in
                let count = registry.order.count
                if draggingID != id {
                    draggingID = id
                    selection = id
                    grabOffset = value.startLocation.y - CGFloat(registry.order.firstIndex(of: id) ?? 0) * Self.rowHeight
                }
                let maxY = CGFloat(count - 1) * Self.rowHeight
                dragY = min(max(value.location.y - grabOffset, 0), maxY)
                let desired = min(max(Int(((dragY + Self.rowHeight / 2) / Self.rowHeight).rounded(.down)), 0), count - 1)
                if registry.move(id, toIndex: desired) { HapticService.shared.play(.dragStep) }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { draggingID = nil }
            }
    }
}

private struct ModuleRow: View {
    let registry: ModuleRegistry
    let descriptor: ModuleDescriptor
    let isSelected: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: descriptor.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(descriptor.selectable ? Color.blue : Color.gray))
            VStack(alignment: .leading, spacing: 1) {
                Text(descriptor.title).fontWeight(.semibold)
                Text(descriptor.selectable ? "\(registry.cells(for: descriptor.id)) cells" : "即將推出…")
                    .font(.caption).foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
            Spacer(minLength: 0)
            if hovering {
                VStack(spacing: 2) {
                    ArrowButton(symbol: "chevron.up", enabled: canMoveUp) { move(-1) }
                    ArrowButton(symbol: "chevron.down", enabled: canMoveDown) { move(1) }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
            Toggle("", isOn: Binding(
                get: { registry.isEnabled(descriptor.id) },
                set: { registry.setEnabled(descriptor.id, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!descriptor.selectable)
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .opacity(descriptor.selectable ? 1 : 0.55)
        .padding(.horizontal, 10)
        .frame(height: ModuleList.rowHeight)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct ArrowButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .heavy))
                .frame(width: 20, height: 14)
                .background(RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

// MARK: - Preview bar

/// Black bar showing the enabled modules in order, widths proportional to their cells (it hugs its content, like
/// the capsule). Drag a tile to reorder it live; hovering a tile shows ◀ ▶ buttons.
private struct PreviewBar: View {
    let registry: ModuleRegistry
    let tabID: String
    @Binding var selection: String?

    /// The modules of the selected tab, in display order (read fresh: the order changes while dragging).
    private var ids: [String] {
        registry.tabs.first { $0.id == tabID }.map(registry.modules(in:)) ?? []
    }

    private let cellPoints: CGFloat = 20
    private let spacing: CGFloat = 6

    @State private var draggingID: String?
    @State private var dragX: CGFloat = 0
    @State private var grabOffset: CGFloat = 0
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
        .overlay(alignment: .leading) { arrow("chevron.left", visible: hoveringID == id && index > 0) { shift(id, -1) } }
        .overlay(alignment: .trailing) { arrow("chevron.right", visible: hoveringID == id && index < ids.count - 1) { shift(id, 1) } }
        .scaleEffect(dragging ? 1.05 : 1)
        .offset(x: dragging ? dragX : originX(of: id, in: ids))
        .zIndex(dragging ? 1 : 0)
        .transaction { if dragging { $0.animation = nil } }
        .onTapGesture { selection = id }
        .onHover { hoveringID = $0 ? id : (hoveringID == id ? nil : hoveringID) }
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
                }
                .onEnded { _ in
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

    @ViewBuilder private func arrow(_ symbol: String, visible: Bool, action: @escaping () -> Void) -> some View {
        if visible {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 30)
                    .background(Capsule().fill(.white.opacity(0.22)))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 3)
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
        }
    }
}

// MARK: - Detail

private struct ModuleDetail: View {
    let registry: ModuleRegistry
    let descriptor: ModuleDescriptor

    private var cells: Int { registry.cells(for: descriptor.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(descriptor.title).font(.headline)
            if descriptor.selectable {
                LabeledContent("寬度:") {
                    HStack {
                        HapticSlider(
                            value: Binding(get: { Double(cells) }, set: { registry.setCells(descriptor.id, Int($0.rounded())) }),
                            in: Double(descriptor.cells.range.lowerBound)...Double(descriptor.cells.range.upperBound), step: 1
                        )
                        NumberField(
                            value: Binding(get: { Double(cells) }, set: { registry.setCells(descriptor.id, Int($0.rounded())) }),
                            range: Double(descriptor.cells.range.lowerBound)...Double(descriptor.cells.range.upperBound)
                        )
                    }
                }
                if registry.tabs.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("所在分頁").font(.subheadline.weight(.semibold))
                        ForEach(registry.tabs) { tab in
                            Toggle(tab.title.isEmpty ? "(未命名)" : tab.title, isOn: Binding(
                                get: { tab.moduleIDs.contains(descriptor.id) },
                                set: { registry.setModule(descriptor.id, in: tab.id, $0) }
                            ))
                        }
                    }
                }
                if let module = registry.module(for: descriptor.id) {
                    module.makeSettingsView()
                }
                if !descriptor.implemented {
                    Text("此模組將於後續里程碑加入，目前只會顯示佔位頁面。").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("即將推出…").foregroundStyle(.secondary)
            }
        }
    }
}
