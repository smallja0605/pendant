import SwiftUI

/// The drop shelf page (requirements 4.6).
@MainActor
final class ShelfModule: PendantModule {
    let id = "shelf"
    let displayName = "檔案中轉站"
    let symbolName = "tray.and.arrow.down"
    let cells = CellRange(default: 6, range: 3...10)
    var isEnabled = false

    private let store = ShelfStore.shared

    func makeView(size: CGSize) -> AnyView {
        AnyView(ShelfView(store: store).frame(width: size.width, height: size.height))
    }

    var activityPriority: Int { 3 }

    func makeCompactView(role: IslandRole) -> AnyView? {
        role == .secondary ? AnyView(ShelfIslandContent(store: store)) : nil
    }

    func activate() {}
    func deactivate() {}
}

/// Shelf as a secondary island: tray icon and the number of files on the shelf.
private struct ShelfIslandContent: View {
    let store: ShelfStore

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
            Text("\(store.items.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
        }
    }
}
