import SwiftUI

/// A segmented picker (the iOS timer's 倒數 / 碼錶 switch). On macOS 26 it is the system's own segmented control, which Apple
/// builds from Liquid Glass: the thumb lifts when pressed, can be dragged across the segments and morphs as it moves. Older
/// systems (or Liquid Glass off in the settings) get a hand-drawn white slider with the same stretch-and-settle motion.
struct LiquidTabPicker<ID: Hashable>: View {
    typealias Item = GooeyTabPicker<ID>.Item

    let items: [Item]
    @Binding var selection: ID

    var body: some View {
        if #available(macOS 26, *), LiquidGlass.isEnabled {
            if AppSettings.shared.nativeSegmented {
                NativeSegmented(items: items, selection: $selection)
            } else {
                SystemGlassSegmented(items: items, selection: $selection)
            }
        } else {
            GooeyTabPicker(items: items, selection: $selection)
        }
    }
}

/// macOS 26: the system's own segmented control (SwiftUI's segmented `Picker`, an `NSSegmentedControl`) — whatever Apple draws and
/// does for it, nothing hand-built except the "running in the background" dots laid over the segments.
@available(macOS 26, *)
struct NativeSegmented<ID: Hashable>: View {
    let items: [GooeyTabPicker<ID>.Item]
    @Binding var selection: ID

    var body: some View {
        Picker("", selection: Binding(get: { selection }, set: { newValue in
            guard newValue != selection else { return }
            HapticService.shared.play(.dragStep)
            selection = newValue
        })) {
            ForEach(items) { item in Text(item.title).tag(item.id) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .fixedSize()
        .environment(\.colorScheme, .dark)
        .overlay {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    Color.clear.overlay(alignment: .topTrailing) {
                        if let dot = item.dot, item.id != selection {
                            Circle().fill(dot).frame(width: 7, height: 7).padding(.top, 3).padding(.trailing, 6)
                        }
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// macOS 26, after the system's segmented control: at rest the chosen segment has a grey thumb; pressing lifts it into a clear
/// Liquid Glass lens (real glass, sampling what is behind it) with the labels inside it drawn over the glass, sharp and a little larger
/// like a magnifier, and follows the pointer across the segments; letting go settles it on the segment under it,
/// which becomes the selection, and it shrinks back into the thumb. The page below only switches on release, so dragging stays light.
@available(macOS 26, *)
struct SystemGlassSegmented<ID: Hashable>: View {
    let items: [GooeyTabPicker<ID>.Item]
    @Binding var selection: ID

    @State private var frames: [ID: CGRect] = [:]
    @State private var lifted = false
    @State private var lensCenter: CGFloat = 0
    /// The segment under the lens while it is lifted (shown in white); committed on release.
    @State private var hoverID: ID?
    @State private var settleTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let space = "glass-lens-segmented"
    private var selectedFrame: CGRect { frames[selection] ?? .zero }
    private var activeID: ID { lifted ? (hoverID ?? selection) : selection }
    private var lensSize: CGSize { CGSize(width: selectedFrame.width * 1.22, height: selectedFrame.height * 1.32) }
    private var contentWidth: CGFloat { frames.values.map(\.maxX).max() ?? 0 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            restThumb
            labels(magnified: false)
        }
        // An overlay, so the lens (bigger than the thumb) does not make the control taller.
        .overlay(alignment: .topLeading) { lensLayer }
        .coordinateSpace(name: space)
        .onPreferenceChange(ItemFrames<ID>.self) { newFrames in
            frames = newFrames
            if !lifted { lensCenter = (newFrames[selection] ?? .zero).midX }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { press(at: $0.location.x - 3) }
                .onEnded { _ in released() }
        )
        #if DEBUG
        .task { await debugDrag() }
        #endif
        .accessibilityRepresentation {
            HStack {
                ForEach(items) { item in
                    Button(item.title) { selection = item.id }
                        .accessibilityAddTraits(item.id == selection ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    /// The grey thumb under the chosen segment; it gives way to the lens while pressed.
    private var restThumb: some View {
        Capsule()
            .fill(Color.white.opacity(0.22))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
            .frame(width: selectedFrame.width, height: selectedFrame.height)
            .offset(x: selectedFrame.minX, y: selectedFrame.minY)
            .opacity(lifted ? 0 : 1)
            .animation(.snappy(duration: 0.3), value: selection)
            .animation(.easeOut(duration: 0.14), value: lifted)
    }

    private func labels(magnified: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                ZStack(alignment: .topTrailing) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.id == activeID ? Color.white : Color.white.opacity(0.62))
                        .padding(.horizontal, 14).padding(.vertical, 4)
                    if let dot = item.dot, item.id != selection {
                        Circle().fill(dot).frame(width: 6, height: 6).offset(x: -5, y: 3)
                    }
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(
                        key: ItemFrames<ID>.self, value: magnified ? [:] : [item.id: proxy.frame(in: .named(space))]
                    )
                })
            }
        }
        .allowsHitTesting(false)
    }

    /// Magnified labels inside the lens, and the glass over them. Always mounted, so lifting is a scale / fade, not a rebuild.
    private var lensLayer: some View {
        let size = lensSize
        let anchor = UnitPoint(x: contentWidth > 0 ? lensCenter / contentWidth : 0.5, y: 0.5)
        return ZStack(alignment: .topLeading) {
            GlassEffectContainer {
                Color.clear
                    .glassEffect(.clear.tint(.white.opacity(0.05)).interactive(), in: .capsule)
                    .frame(width: size.width, height: size.height)
            }
            .offset(x: lensCenter - size.width / 2, y: selectedFrame.midY - size.height / 2)
            // The labels inside the lens are drawn over the glass: sharp, and a little larger (the magnifier).
            labels(magnified: true)
                .scaleEffect(1.16, anchor: anchor)
                .mask(alignment: .topLeading) {
                    Capsule().frame(width: size.width, height: size.height)
                        .offset(x: lensCenter - size.width / 2, y: selectedFrame.midY - size.height / 2)
                }
        }
        .scaleEffect(lifted ? 1 : 0.84, anchor: UnitPoint(x: anchor.x, y: 0.5))
        .opacity(lifted ? 1 : 0)
        .allowsHitTesting(false)
    }

    // MARK: Interaction

    private func press(at position: CGFloat) {
        settleTask?.cancel()
        guard let low = frames.values.map(\.midX).min(), let high = frames.values.map(\.midX).max() else { return }
        let target = min(max(position, low), high)
        if !lifted {
            lensCenter = selectedFrame.midX
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.74)) { lifted = true }
            HapticService.shared.play(.dragStep)
        }
        withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.18, dampingFraction: 0.86)) { lensCenter = target }
        let hit = items.first { item in frames[item.id].map { target >= $0.minX && target < $0.maxX } ?? false }
        if let hit, hit.id != hoverID {
            if hoverID != nil || hit.id != selection { HapticService.shared.play(.dragStep) }
            hoverID = hit.id
        }
    }

    /// Commits the segment under the lens, settles the lens on it and shrinks it back into the thumb.
    private func released() {
        guard lifted else { return }
        let chosen = hoverID ?? selection
        hoverID = nil
        if chosen != selection { selection = chosen }
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.72)) {
            lensCenter = (frames[chosen] ?? selectedFrame).midX
        }
        settleTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) { lifted = false }
        }
    }

    #if DEBUG
    /// PENDANT_DEBUG_LENS=1: presses the thumb, drags the lens across all segments and lets go (visual check).
    private func debugDrag() async {
        guard ProcessInfo.processInfo.environment["PENDANT_DEBUG_LENS"] != nil else { return }
        try? await Task.sleep(for: .seconds(2))
        guard let first = frames.values.map(\.midX).min(), let last = frames.values.map(\.midX).max() else { return }
        press(at: first)
        for step in 0...30 {
            try? await Task.sleep(for: .milliseconds(30))
            press(at: first + (last - first) * CGFloat(step) / 30)
        }
        try? await Task.sleep(for: .milliseconds(500))
        released()
    }
    #endif
}

/// The hand-drawn version: a dark capsule holds the options, a white capsule slides under the chosen one and
/// the text turns black exactly where the slider covers it. The slider's two edges move on different springs — the edge it moves
/// towards runs ahead, the other lags behind and then catches up with a bounce — so it stretches like a drop and settles with a
/// jelly wobble instead of sliding linearly.
struct GooeyTabPicker<ID: Hashable>: View {
    struct Item: Identifiable {
        let id: ID
        let title: String
        /// A small coloured dot after the title (e.g. "this timer is running in the background").
        var dot: Color?
    }

    let items: [Item]
    @Binding var selection: ID
    var font = Font.system(size: 14, weight: .semibold)

    @State private var frames: [ID: CGRect] = [:]
    /// The slider's current edges (animated separately).
    @State private var leading: CGFloat = 0
    @State private var trailing: CGFloat = 0
    @State private var placed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let space = "liquid-tab-picker"

    var body: some View {
        ZStack(alignment: .topLeading) {
            slider
            labels(selected: false) // white text on the dark capsule
            labels(selected: true) // black text, visible only where the slider is
                .mask(alignment: .topLeading) { sliderShape }
            taps
        }
        .coordinateSpace(name: space)
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .onPreferenceChange(ItemFrames<ID>.self) { newFrames in
            frames = newFrames
            if !placed, let frame = newFrames[selection] {
                leading = frame.minX
                trailing = frame.maxX
                placed = true
            } else if placed, let frame = newFrames[selection], abs(frame.minX - leading) > 0.5 || abs(frame.maxX - trailing) > 0.5 {
                move(to: frame, animated: false) // a title got wider (e.g. the dot appeared): follow without a show
            }
        }
        .onChange(of: selection) { old, new in
            guard let target = frames[new] else { return }
            move(to: target, animated: true, movingRight: (frames[old]?.minX ?? 0) < target.minX)
        }
    }

    private var sliderShape: some View {
        Capsule()
            .frame(width: max(trailing - leading, 0))
            .offset(x: leading)
    }

    private var slider: some View {
        sliderShape.foregroundStyle(Color.white)
    }

    private func labels(selected: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                HStack(spacing: 4) {
                    Text(item.title)
                    if let dot = item.dot, !selected {
                        Circle().fill(dot).frame(width: 6, height: 6)
                    }
                }
                .font(font)
                .foregroundStyle(selected ? Color.black : Color.white.opacity(0.7))
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ItemFrames<ID>.self, value: selected ? [:] : [item.id: proxy.frame(in: .named(space))])
                })
            }
        }
        .allowsHitTesting(false)
    }

    /// Invisible tap targets over the labels.
    private var taps: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Color.clear
                    .contentShape(Capsule())
                    .onTapGesture { select(item.id) }
                    .hapticOnHover()
                    .frame(width: frames[item.id]?.width)
                    .accessibilityElement()
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(item.id == selection ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    private func select(_ id: ID) {
        guard id != selection else { return }
        HapticService.shared.play(.dragStep)
        selection = id
    }

    private func move(to frame: CGRect, animated: Bool, movingRight: Bool = true) {
        guard animated, !reduceMotion else {
            leading = frame.minX
            trailing = frame.maxX
            return
        }
        // The edge in front is quick, the one behind follows late: the slider stretches, then contracts with a bounce.
        let quick = Animation.spring(response: 0.26, dampingFraction: 0.62)
        let slow = Animation.spring(response: 0.46, dampingFraction: 0.58)
        withAnimation(movingRight ? quick : slow) { trailing = frame.maxX }
        withAnimation(movingRight ? slow : quick) { leading = frame.minX }
    }
}

struct ItemFrames<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: CGRect] { [:] }
    static func reduce(value: inout [ID: CGRect], nextValue: () -> [ID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
