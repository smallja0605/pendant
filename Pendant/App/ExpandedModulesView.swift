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
        .id(registry.focusedModuleID ?? "page")
        .transition(.opacity)
    }

    @ViewBuilder private func moduleView(_ module: any PendantModule, size: CGSize, focused: Bool, canFocus: Bool) -> some View {
        if focused {
            (module.makeFocusView(size: size) ?? module.makeView(size: size))
                .overlay(alignment: .topLeading) { FocusHandle(direction: .back) { registry.unfocus() } }
        } else if canFocus, ModuleFocus.supports(module.id) {
            module.makeView(size: size)
                .overlay(alignment: .topTrailing) { FocusHandle(direction: .enter) { registry.focus(module.id) } }
        } else {
            module.makeView(size: size)
        }
    }
}

/// Which modules have a detailed page to open.
enum ModuleFocus {
    static func supports(_ id: String) -> Bool { ["media", "reminders", "calendar", "timer"].contains(id) }
}

/// A muted arrow in a module's top corner, shown while the pointer is over the module's top edge: ">" opens its detailed page
/// (the other modules give way), "<" goes back to the whole tab.
struct FocusHandle: View {
    enum Direction { case enter, back }
    let direction: Direction
    let action: () -> Void
    @State private var nearby = false
    @State private var overButton = false

    var body: some View {
        ZStack(alignment: direction == .enter ? .topTrailing : .topLeading) {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 34)
                .onActiveHover { nearby = $0 != nil }
                .allowsHitTesting(false)
            Button(action: action) {
                Image(systemName: direction == .enter ? "chevron.right" : "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(overButton ? 0.85 : 0.42))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onActiveHover { overButton = $0 != nil }
            .opacity(nearby || overButton || direction == .back ? 1 : 0)
            .allowsHitTesting(nearby || overButton || direction == .back)
            .animation(.easeOut(duration: 0.18), value: nearby)
            .animation(.easeOut(duration: 0.12), value: overButton)
        }
        .frame(maxWidth: .infinity, maxHeight: 34, alignment: direction == .enter ? .topTrailing : .topLeading)
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
