import SwiftUI

/// Secondary islands (3.5): separate black pills beside the main island, positioned from the pure planner's rects
/// (relative to the screen centre, which is also the panel's centre).
struct SecondaryIslands: View {
    let model: CapsuleModel
    let registry: ModuleRegistry
    let onPointer: (String, Bool) -> Void
    let onTap: (String) -> Void

    var body: some View {
        let layout = model.layout
        let midX = layout?.notch.screenFrame.midX ?? 0
        let top = layout?.notch.screenFrame.maxY ?? 0
        let reduce = model.reduceMotion
        let pairs: [(IslandPlacement, LiveActivity)] = (layout?.secondaries ?? []).compactMap { placement in
            model.secondaryActivities.first { $0.id == placement.id }.map { (placement, $0) }
        }
        let main = layout?.bodyRect(for: .compact) ?? .zero
        let swellShift = model.isSwelled
            ? ((layout?.swelledSize(main.size, reduceMotion: reduce).width ?? main.width) - main.width) / 2 : 0
        ZStack(alignment: .top) {
            if model.state == .compact, !model.menuSuppressed {
                ForEach(pairs, id: \.0.id) { placement, activity in
                    let side = placement.side ?? .right
                    let towardMain: CGFloat = side == .left ? 1 : -1
                    let revealed = model.secondariesRevealed
                    Group {
                        if revealed {
                            IslandPill(activity: activity, registry: registry, size: placement.rect.size,
                                       hovering: model.hoveredIsland == activity.id,
                                       onPointer: { onPointer(activity.id, $0) }, onTap: { onTap(activity.id) })
                                .transition(reduce ? .opacity : .asymmetric(
                                    insertion: .offset(x: towardMain * (placement.rect.width / 2 + 10)).combined(with: .opacity)
                                        .combined(with: .scale(scale: 0.5)),
                                    removal: .offset(x: towardMain * (placement.rect.width / 2 + 10)).combined(with: .opacity)
                                        .combined(with: .scale(scale: 0.5))))
                        } else {
                            Circle().fill(.white.opacity(0.55)).frame(width: 5, height: 5)
                                .frame(width: placement.rect.width, height: placement.rect.height,
                                       alignment: side == .left ? .trailing : .leading)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: placement.rect.width, height: placement.rect.height)
                    .offset(x: placement.rect.midX - midX + (side == .left ? -swellShift : swellShift),
                            y: top - placement.rect.maxY)
                    .animation(AnimationTokens.island(reduceMotion: reduce), value: revealed)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(AnimationTokens.island(reduceMotion: reduce), value: pairs.map(\.0))
        .animation(AnimationTokens.island(reduceMotion: reduce), value: model.state)
    }
}

struct IslandPill: View {
    let activity: LiveActivity
    let registry: ModuleRegistry
    let size: CGSize
    let hovering: Bool
    let onPointer: (Bool) -> Void
    let onTap: () -> Void
    @State private var pulse = false

    var body: some View {
        let module = registry.module(for: activity.moduleID)
        ZStack {
            Capsule().fill(Color.black)
                .overlay(Capsule().stroke(Color.white.opacity(activity.isAlerting ? (pulse ? 0.95 : 0.15) : 0), lineWidth: 2))
                .shadow(color: .black.opacity(hovering ? 0.5 : 0.25), radius: hovering ? 7 : 3, y: 2)
            Group {
                if activity.id == "stopwatch" {
                    TimerIslandContent(mode: .stopwatch)
                } else if let view = module?.makeCompactView(role: .secondary) {
                    view
                } else {
                    Image(systemName: activity.symbolName).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 9)
            Color.clear.contentShape(Capsule()).onActiveHover { onPointer($0 != nil) }
        }
        .frame(width: size.width, height: size.height)
        .scaleEffect(hovering ? Tuning.shared.islandHoverScale : 1)
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .task(id: activity.isAlerting) {
            guard activity.isAlerting else { pulse = false; return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.35)) { pulse.toggle() }
                try? await Task.sleep(for: .milliseconds(450))
            }
        }
        .accessibilityLabel(Text(module?.displayName ?? activity.id))
    }
}

/// Tab switch at the capsule's top-left (the user's tabs that have something to show). With titles when the strip beside
/// the notch is wide enough, otherwise as icons (the symbol of the tab's first module).
struct ModeSwitcher: View {
    let registry: ModuleRegistry

    var body: some View {
        ViewThatFits(in: .horizontal) {
            tabs(titles: true)
            tabs(titles: false)
        }
    }

    private func tabs(titles: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(registry.availableTabs) { tab in
                let first = registry.modules(in: tab).first
                let symbol = first.flatMap { ModuleDescriptor.descriptor(for: $0)?.symbolName } ?? "square.grid.2x2.fill"
                pill(tab.title, symbol: symbol, selected: registry.effectiveTab?.id == tab.id, titles: titles) { show(tab.id) }
            }
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.12)))
        .fixedSize()
    }

    private func show(_ id: String) {
        guard id != registry.effectiveTab?.id else { return }
        HapticService.shared.play(.dragStep)
        registry.setTab(id)
    }

    private func pill(_ title: String, symbol: String, selected: Bool, titles: Bool, action: @escaping () -> Void) -> some View {
        Group {
            if titles { Text(title) } else { Image(systemName: symbol) }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(selected ? Color.black : .white.opacity(0.75))
        .padding(.horizontal, titles ? 9 : 10).padding(.vertical, 3)
        .background(Capsule().fill(selected ? Color.white : .clear))
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .hapticOnHover()
        .accessibilityLabel(title)
    }
}

/// The compact capsule while a timer (countdown or stopwatch) is the main island: icon on the left edge, digits (and the
/// progress line) on the right edge, both laid out in the capsule's own animated frame, so they move rigidly with its
/// edges while it swells. The timer-end notice appears below the row.
struct TimerMainRow: View, @preconcurrency Animatable {
    let model: CapsuleModel
    let mode: TimerEngine.Mode
    /// The capsule body as drawn right now (animated).
    var size: CGSize

    /// `size` is interpolated by SwiftUI on every frame of an animation, so the margin, icon size and positions computed
    /// from it below follow the capsule's edges exactly instead of jumping to their final values at the start.
    var animatableData: CGSize.AnimatableData {
        get { size.animatableData }
        set { size.animatableData = newValue }
    }

    var body: some View {
        let layout = model.layout
        let compact = layout?.bodySize(for: .compact) ?? size
        let swelled = layout?.swelledSize(compact, reduceMotion: model.reduceMotion) ?? compact
        let rowHeight = size.height - (model.isAlerting ? CapsuleLayout.compactInfoHeight : 0)
        // Swollen, the margin doubles (smoothly: it follows how far the capsule has grown).
        let progress = min(max((rowHeight - compact.height) / max(swelled.height - compact.height, 1), 0), 1)
        let base = Tuning.shared.iconMargin
        let margin = base * (1 + progress)
        let icon = max(rowHeight - 2 * base, 0)
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                Image(systemName: TimerStyle.symbol(for: mode))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(TimerStyle.color(for: mode))
                    .frame(width: icon * 0.8, height: icon * 0.8)
                    .frame(width: icon, height: icon)
                Spacer(minLength: 0)
                CompactTimerText(mode: mode, swollen: model.showsSwell)
            }
            .padding(.horizontal, margin)
            .frame(width: size.width, height: rowHeight)
            alertLine
                .padding(.top, rowHeight)
                .modifier(RevealEffect(isVisible: model.isAlerting, delay: 0.04))
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .accessibilityHidden(true)
    }

    /// Timer-end notice, laid out like the song line.
    private var alertLine: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("計時結束").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            Text("點一下查看").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}
