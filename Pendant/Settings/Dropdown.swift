import SwiftUI

/// A pop-up menu for a settings row: the current choice and a small up/down chevron close behind it. The chevron has no
/// background at rest; the whole control lights up softly while the pointer is over it.
struct DropdownMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, title: String)]
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(options.first { $0.value == selection }?.title ?? "")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.white.opacity(hovering && isEnabled ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// A settings row with a dropdown on its right.
struct DropdownRow<Value: Hashable>: View {
    let title: String
    var tip: String?
    @Binding var selection: Value
    let options: [(value: Value, title: String)]

    var body: some View {
        TipRow(title: title, tip: tip) { DropdownMenu(selection: $selection, options: options) }
    }
}
