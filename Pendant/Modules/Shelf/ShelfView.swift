import SwiftUI
import UniformTypeIdentifiers

/// Shelf page (see `shelf-airdrop.png`): a dashed "file drawer" on the left and a blue AirDrop zone on the right.
/// Dropping on the drawer stores a copy; dropping on AirDrop opens the AirDrop sheet and keeps nothing.
struct ShelfView: View {
    let store: ShelfStore
    @State private var drawerTargeted = false
    @State private var airDropTargeted = false

    @State private var settings = AppSettings.shared

    var body: some View {
        GeometryReader { proxy in
            row(airDropWidth: min(max((proxy.size.width - 8) * settings.shelfAirDropPercent / 100, 60), proxy.size.width - 8 - 120))
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .onChange(of: drawerTargeted) { _, on in if on { HapticService.shared.play(.dragStep) } }
        .onChange(of: airDropTargeted) { _, on in if on { HapticService.shared.play(.dragStep) } }
    }

    /// The drawer takes what the AirDrop area leaves (its width is a share of the page, set in the shelf settings).
    private func row(airDropWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            DrawerZone(store: store, targeted: drawerTargeted)
                .onDrop(of: [.fileURL], isTargeted: $drawerTargeted) { providers in
                    Self.urls(from: providers) { store.add(urls: $0) }
                    return true
                }
            AirDropZone(store: store, targeted: airDropTargeted)
                .frame(width: airDropWidth)
                .onDrop(of: [.fileURL], isTargeted: $airDropTargeted) { providers in
                    Self.urls(from: providers) { ShelfStore.sendViaAirDrop($0) }
                    return true
                }
        }
    }

    /// File URLs behind dropped providers (they arrive asynchronously).
    private static func urls(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var found: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    lock.lock(); found.append(url); lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { MainActor.assumeIsolated { completion(found) } }
    }
}

// MARK: - Drawer

private struct TileFrame: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue()) { $1 } }
}

private struct DrawerZone: View {
    let store: ShelfStore
    let targeted: Bool
    @State private var anchor: UUID?
    @State private var tileFrames: [UUID: CGRect] = [:]
    @State private var marquee: CGRect?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(targeted ? 0.1 : 0))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(targeted ? 0.7 : 0.22), style: StrokeStyle(lineWidth: targeted ? 3 : 2, dash: [7, 6]))
            if store.items.isEmpty && store.pendingCopies == 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 22, weight: .semibold))
                    Text("檔案抽屜").font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.white.opacity(targeted ? 0.95 : 0.6))
                .padding(16)
            } else {
                content
            }
        }
        .animation(.easeOut(duration: 0.12), value: targeted)
    }

    private var content: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text("檔案抽屜").font(.system(size: 12, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                Text("\(store.items.count)").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                if store.pendingCopies > 0 { ProgressView().controlSize(.mini).tint(.white).padding(.leading, 4) }
                Spacer()
                IconButton(symbol: "doc.on.doc", help: "複製") { store.copyToPasteboard(store.selection) }
                IconButton(symbol: "trash", help: "移除所選") { store.remove(store.selection) }.disabled(store.selection.isEmpty)
                IconButton(symbol: "xmark.circle", help: "清除全部") { store.clear() }
            }
            .padding(.leading, 12).padding(.trailing, 6).padding(.top, 6)
            if let message = store.limitMessage {
                Text(message).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.orange)
            }
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 4)], spacing: 4) {
                    ForEach(store.items) { item in
                        ShelfTile(store: store, item: item, anchor: $anchor)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: TileFrame.self, value: [item.id: proxy.frame(in: .named("shelfGrid"))])
                            })
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
                .coordinateSpace(name: "shelfGrid")
                .onPreferenceChange(TileFrame.self) { tileFrames = $0 }
                .overlay {
                    if let marquee {
                        Rectangle().fill(.white.opacity(0.1)).overlay(Rectangle().stroke(.white.opacity(0.4)))
                            .frame(width: marquee.width, height: marquee.height)
                            .position(x: marquee.midX, y: marquee.midY)
                            .allowsHitTesting(false)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .named("shelfGrid"))
                        .onChanged { drag in
                            let start = drag.startLocation, end = drag.location
                            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                              width: abs(end.x - start.x), height: abs(end.y - start.y))
                            marquee = rect
                            store.selection = Set(tileFrames.filter { $0.value.intersects(rect) }.map(\.key))
                        }
                        .onEnded { _ in marquee = nil }
                )
            }
        }
    }
}

private struct ShelfTile: View {
    let store: ShelfStore
    let item: ShelfItem
    @Binding var anchor: UUID?
    @State private var image: NSImage?

    var body: some View {
        let selected = store.selection.contains(item.id)
        VStack(spacing: 2) {
            Group {
                if let image { Image(nsImage: image).resizable().scaledToFit() } else { Color.clear }
            }
            .frame(width: 38, height: 38)
            Text(item.name).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                .lineLimit(1).truncationMode(.middle).padding(.horizontal, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(selected ? 0.22 : 0)))
        .overlay(ShelfTileInteraction(
            onClick: { modifiers in
                var anchorID = anchor
                store.select(item.id, extend: modifiers.contains(.shift), toggle: modifiers.contains(.command), anchor: &anchorID)
                anchor = anchorID
            },
            dragURLs: { store.dragCopies(for: store.selection.contains(item.id) ? store.selection : [item.id]) },
            dragImage: image,
            onQuickLook: { ShelfPreview.shared.toggle(store.urls(for: store.selection.isEmpty ? [item.id] : store.selection)) },
            onDelete: { store.remove(store.selection.isEmpty ? [item.id] : store.selection) },
            onSelectAll: { store.selectAll() }
        ))
        .task(id: item.id) { image = await store.thumbnail(for: item) }
    }
}

// MARK: - AirDrop

private struct AirDropZone: View {
    let store: ShelfStore
    let targeted: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            if !store.selection.isEmpty { store.airDrop(store.selection) }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 0.0, green: 0.12, blue: 0.25).opacity(targeted || hovering ? 1 : 0.85))
                if targeted {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.blue.opacity(0.9), lineWidth: 3)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "airplayaudio").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.blue)
                    Text("AirDrop").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onActiveHover { hovering = $0 != nil }
        .animation(.easeOut(duration: 0.12), value: targeted)
        .accessibilityLabel("AirDrop")
    }
}
