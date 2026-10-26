import SwiftUI

/// Shortcuts page: one tap runs a shortcut from the Shortcuts app.
struct ShortcutsView: View {
    let store: ShortcutsStore
    @State private var settings = AppSettings.shared

    var body: some View {
        let names = store.visibleNames(hidden: settings.shortcutsHidden)
        VStack(spacing: 6) {
            HStack {
                Text("捷徑").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Spacer()
                IconButton(symbol: "arrow.clockwise", help: "重新整理") { store.refresh() }
            }
            .padding(.top, 8)
            if !store.isAvailable {
                message("此系統找不到「捷徑」工具")
            } else if names.isEmpty {
                message(store.loaded ? "沒有可顯示的捷徑" : "讀取中…")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    if settings.shortcutsGrid {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                            ForEach(names, id: \.self) { name in
                                ShortcutTile(name: name, state: store.states[name], grid: true) { store.run(name) }
                            }
                        }
                    } else {
                        VStack(spacing: 3) {
                            ForEach(names, id: \.self) { name in
                                ShortcutTile(name: name, state: store.states[name], grid: false) { store.run(name) }
                            }
                        }
                    }
                }
            }
        }
        .padding(.bottom, 8)
        .task { if !store.loaded { store.refresh() } }
    }

    private func message(_ text: String) -> some View {
        Text(loc(text)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShortcutTile: View {
    let name: String
    let state: ShortcutsStore.RunState?
    let grid: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if grid {
                    VStack(spacing: 5) { icon; label }.frame(height: 56)
                } else {
                    HStack(spacing: 8) { icon; label; Spacer(minLength: 0) }.frame(height: 30).padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hovering ? 0.16 : 0.09)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onActiveHover { hovering = $0 != nil }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var icon: some View {
        Group {
            switch state {
            case .running: ProgressView().controlSize(.small).tint(.white)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case nil: Image(systemName: "sparkles").foregroundStyle(.white.opacity(0.85))
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .frame(width: 20, height: 20)
    }

    private var label: some View {
        Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1).padding(.horizontal, grid ? 6 : 0)
    }
}
