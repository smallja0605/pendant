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

    /// The modules with the thin separators between them.
    private func tabContent(_ ids: [String]) -> some View {
        HStack(spacing: 0) {
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
                    module.makeView(size: size)
                        .environment(\.moduleAtCapsuleEdge, index == ids.count - 1)
                        .frame(width: size.width, height: size.height)
                }
            }
        }
        .padding(.horizontal, layout.contentInset)
        .frame(width: contentSize.width, height: contentSize.height)
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
