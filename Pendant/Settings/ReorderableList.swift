import SwiftUI

/// A vertical list whose first `movableCount` rows can be dragged to a new place: the dragged row follows the pointer, the others
/// spring into their slots, and every position change gives one haptic tick.
struct ReorderableList<ID: Hashable, Row: View>: View {
    let ids: [ID]
    var movableCount: Int?
    var rowHeight: CGFloat = 40
    /// Moves `id` to `index`; returns whether the order changed.
    let move: (ID, Int) -> Bool
    let onSelect: (ID) -> Void
    @ViewBuilder let row: (ID) -> Row

    @State private var draggingID: ID?
    @State private var dragY: CGFloat = 0
    @State private var grabOffset: CGFloat = 0

    private var movable: Int { min(movableCount ?? ids.count, ids.count) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(ids, id: \.self) { id in
                let index = ids.firstIndex(of: id) ?? 0
                let dragging = draggingID == id
                row(id)
                    .frame(height: rowHeight)
                    .scaleEffect(dragging ? 1.03 : 1)
                    .offset(y: dragging ? dragY : CGFloat(index) * rowHeight)
                    .zIndex(dragging ? 1 : 0)
                    .shadow(color: .black.opacity(dragging ? 0.3 : 0), radius: 7, y: 2)
                    .transaction { if dragging { $0.animation = nil } }
                    .onTapGesture { onSelect(id) }
                    .gesture(index < movable ? drag(for: id) : nil)
            }
        }
        .frame(maxWidth: .infinity, minHeight: CGFloat(ids.count) * rowHeight, alignment: .topLeading)
        .coordinateSpace(name: "reorderList")
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: ids)
    }

    private func drag(for id: ID) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("reorderList"))
            .onChanged { value in
                if draggingID != id {
                    draggingID = id
                    onSelect(id)
                    grabOffset = value.startLocation.y - CGFloat(ids.firstIndex(of: id) ?? 0) * rowHeight
                }
                let maxY = CGFloat(movable - 1) * rowHeight
                dragY = min(max(value.location.y - grabOffset, 0), maxY)
                let desired = min(max(Int(((dragY + rowHeight / 2) / rowHeight).rounded(.down)), 0), movable - 1)
                if move(id, desired) { HapticService.shared.play(.dragStep) }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { draggingID = nil }
            }
    }
}

/// One row of a settings tool list: icon, name, switch; the selected row sits on a Liquid Glass plate (macOS 26+, else a light fill),
/// the one under the pointer on a fainter fill.
struct ToolRow: View {
    let symbol: String
    let title: String
    let isSelected: Bool
    var comingSoon = false
    /// Up / down arrows shown while the pointer is over the row (nil: none).
    var arrows: (up: Bool, down: Bool)?
    var onArrow: (Int) -> Void = { _ in }
    var isOn: Binding<Bool>?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(comingSoon ? Color.gray : Color.blue))
            Text(title).fontWeight(.medium).lineLimit(1)
            if comingSoon { Text("(即將推出)").font(.caption).foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary) }
            Spacer(minLength: 0)
            if let isOn, !comingSoon { Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small) }
        }
        .foregroundStyle(Color.primary)
        .opacity(comingSoon ? 0.55 : 1)
        // Inner room from the Figma list (Sidebars - Composed): 7 pt above and below the content, 10 pt from the plate's edge.
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // The arrows float over the free space left of the switch (they do not take room from the name while hidden).
        .overlay(alignment: .trailing) {
            if let arrows {
                VStack(spacing: 2) {
                    arrow("chevron.up", enabled: arrows.up) { onArrow(-1) }
                    arrow("chevron.down", enabled: arrows.down) { onArrow(1) }
                }
                .padding(.trailing, 58)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            }
        }
        .modifier(ToolRowPlate(selected: isSelected, hovering: hovering))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.28), value: hovering)
    }

    private func arrow(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .heavy)).frame(width: 20, height: 13)
                .background(RoundedRectangle(cornerRadius: 4).fill(.primary.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }
}

/// The card behind a tool list.
struct ToolListCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.07)))
    }
}

/// The selected row's plate, like the settings sidebar's: Liquid Glass on macOS 26+, a translucent fill before; a hovered row gets a
/// fainter fill than the selected one.
private struct ToolRowPlate: ViewModifier {
    let selected: Bool
    let hovering: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if selected, #available(macOS 26, *), LiquidGlass.isEnabled {
            content.glassEffect(.regular.tint(.white.opacity(0.10)), in: .rect(cornerRadius: 11))
        } else {
            content.background(
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(selected ? 0.16 : (hovering ? 0.07 : 0)))
            )
        }
    }
}
