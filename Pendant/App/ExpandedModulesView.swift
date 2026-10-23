import SwiftUI

/// The modules of the current tab side by side, each `cells × cellWidth` wide (notes and the shelf fill the capsule).
struct ExpandedModulesView: View {
    let registry: ModuleRegistry
    let layout: CapsuleLayout
    /// Size of the area below the notch.
    let contentSize: CGSize

    var body: some View {
        let ids = registry.currentPageIDs
        ZStack(alignment: .bottom) {
            if ids.isEmpty {
                EmptyModulesView().frame(width: contentSize.width, height: contentSize.height)
            } else {
                tabContent(ids)
                    .id(registry.effectiveTab?.id)
                    .transition(.opacity)
            }
        }
    }

    /// The modules with the thin separators between them (or one module alone, in its detailed page).
    private func tabContent(_ ids: [String]) -> some View {
        let focused = registry.focusedModuleID != nil && ids.count == 1
        return HStack(spacing: 0) {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                if index > 0 {
                    // Thin separator in the gap between two blocks (not full height).
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 2, height: contentSize.height * Tuning.shared.dividerLengthRatio)
                        .frame(width: layout.moduleGap, height: contentSize.height)
                }
                // A tab with a single module (notes, the shelf) fills the whole capsule (no empty strips at its sides).
                let width = ids.count > 1
                    ? CGFloat(registry.cells(for: id)) * layout.effectiveCellWidth
                    : contentSize.width - 2 * layout.contentInset
                let size = CGSize(width: width, height: contentSize.height)
                if let module = registry.module(for: id) {
                    moduleView(module, size: size, focused: focused, canFocus: ids.count > 1)
                        .environment(\.moduleAtCapsuleEdge, index == ids.count - 1)
                        .frame(width: size.width, height: size.height)
                }
            }
        }
        .padding(.horizontal, layout.contentInset)
        .frame(width: contentSize.width, height: contentSize.height)
        .transition(.opacity)
    }

    /// One module. The same view type is used in the page and in its detailed page, so the module keeps its identity and
    /// glides to its new size and place instead of being swapped.
    private func moduleView(_ module: any PendantModule, size: CGSize, focused: Bool, canFocus: Bool) -> some View {
        let content = focused ? (module.makeFocusView(size: size) ?? module.makeView(size: size)) : module.makeView(size: size)
        let enter: (() -> Void)? = !focused && canFocus && ModuleFocus.supports(module.id)
            ? { registry.focus(module.id) } : nil
        return content.environment(\.focusEnter, enter)
    }
}

/// Which modules have a detailed page to open.
enum ModuleFocus {
    static func supports(_ id: String) -> Bool { ["media", "reminders", "calendar"].contains(id) }
}

private struct FocusEnterKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Opens this module's detailed page (nil: it has none, or it is already open).
    var focusEnter: (() -> Void)? {
        get { self[FocusEnterKey.self] }
        set { self[FocusEnterKey.self] = newValue }
    }
}

/// A muted ">" that sits right after a module's title and opens the module's detailed page. Draws nothing where there is none.
struct FocusEnterButton: View {
    @Environment(\.focusEnter) private var enter
    @State private var hovering = false

    var body: some View {
        if let enter {
            Button(action: enter) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(hovering ? 0.85 : 0.42))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onActiveHover { hovering = $0 != nil }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .accessibilityLabel("開啟詳細頁")
        }
    }
}

private struct EmptyModulesView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.dashed")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            Text("沒有啟用的小工具")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("到設定 → 小工具 開啟")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}
