import SwiftUI
import UniformTypeIdentifiers

/// Shelf page (see `shelf-airdrop.png`): a dashed "file drawer" on the left and a blue AirDrop zone on the right.
/// Dropping on the drawer stores a copy; dropping on AirDrop opens the AirDrop sheet and keeps nothing.
struct ShelfView: View {
    let store: ShelfStore
    @State private var drawerTargeted = false
    @State private var airDropTargeted = false

    @State private var settings = AppSettings.shared
    @State private var drag = ShelfDragState.shared

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
            DrawerZone(store: store, targeted: drawerTargeted, dragging: drag.isDragging)
                .hoverLift(drawerTargeted)
                .onDrop(of: [.fileURL], isTargeted: $drawerTargeted) { providers in
                    Self.urls(from: providers) { store.add(urls: $0) }
                    return true
                }
            AirDropZone(store: store, targeted: airDropTargeted, dragging: drag.isDragging)
                .frame(width: airDropWidth)
                .hoverLift(airDropTargeted)
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
    let dragging: Bool
    @State private var anchor: UUID?
    @State private var tileFrames: [UUID: CGRect] = [:]
    @State private var marquee: CGRect?
    @State private var sheen: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.white.opacity(targeted ? 0.12 : dragging ? 0.05 : 0))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(targeted ? 0.8 : dragging ? 0.45 : 0.22),
                              style: StrokeStyle(lineWidth: targeted ? 3 : 2, dash: [7, 6]))
            if store.items.isEmpty && store.pendingCopies == 0 {
                if !dragging {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 22, weight: .semibold))
                        Text("檔案抽屜").font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(16)
                    .transition(.opacity)
                }
            } else {
                content
                    .opacity(dragging ? 0.18 : 1)
                    .blur(radius: dragging ? 2 : 0)
                    .allowsHitTesting(!dragging)
            }
            if dragging {
                DropHint(symbol: "tray.and.arrow.down.fill", text: "放開即可加入檔案抽屜", active: targeted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .overlay {
            SweepGradient(progress: sheen).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous)).allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.18), value: targeted)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: dragging)
        .onChange(of: store.lastDropAt) { _, _ in
            sheen = 0
            withAnimation(.easeInOut(duration: 0.75)) { sheen = 1 }
        }
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
        .dropReveal(store.freshIDs.contains(item.id))
    }
}

// MARK: - AirDrop

private struct AirDropZone: View {
    let store: ShelfStore
    let targeted: Bool
    let dragging: Bool
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
                if dragging {
                    DropHint(symbol: "airplayaudio", text: "放開即可 AirDrop", active: targeted, tint: .blue)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "airplayaudio").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.blue)
                        Text("AirDrop").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(16)
                    .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onActiveHover { hovering = $0 != nil }
        .animation(.easeOut(duration: 0.18), value: targeted)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: dragging)
        .accessibilityLabel("AirDrop")
    }
}

// MARK: - Drag feedback

/// "Release to add": what a zone shows while a file is being dragged, bigger and brighter once the pointer is over it.
private struct DropHint: View {
    let symbol: String
    let text: String
    let active: Bool
    var tint: Color = .white

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: active)
            Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(active ? 0.95 : 0.7))
        }
        .scaleEffect(active ? 1.06 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: active)
    }
}

/// A soft band of light that runs from the top of a zone to the bottom (progress 0 → 1), then is gone.
private struct SweepGradient: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let band = proxy.size.height * 0.7
            LinearGradient(colors: [.clear, .white.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: band)
                .offset(y: -band + (proxy.size.height + band) * progress)
                .opacity(progress >= 1 ? 0 : 1)
        }
    }
}

private extension View {
    /// The zone under the dragged files swells a little.
    func hoverLift(_ on: Bool) -> some View {
        scaleEffect(on ? 1.035 : 1)
            .zIndex(on ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: on)
    }

    /// A newly dropped file is uncovered from the top down (a soft edge moves down over it) while it settles in from above.
    func dropReveal(_ fresh: Bool) -> some View { modifier(DropReveal(fresh: fresh)) }
}

private struct DropReveal: ViewModifier {
    let fresh: Bool
    @State private var progress: CGFloat

    init(fresh: Bool) {
        self.fresh = fresh
        _progress = State(initialValue: fresh ? 0 : 1)
    }

    func body(content: Content) -> some View {
        content
            .mask {
                GeometryReader { proxy in
                    let edge = proxy.size.height * 0.8
                    VStack(spacing: 0) {
                        Color.black.frame(height: proxy.size.height)
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: edge)
                    }
                    .offset(y: -(proxy.size.height + edge) * (1 - progress))
                }
            }
            .offset(y: -10 * (1 - progress))
            .onAppear {
                guard fresh, progress < 1 else { return }
                withAnimation(.easeOut(duration: 0.7)) { progress = 1 }
            }
    }
}
