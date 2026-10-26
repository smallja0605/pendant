import SwiftUI

/// The one view that morphs between idle / compact / expanded.
struct CapsuleView: View {
    let model: CapsuleModel
    let registry: ModuleRegistry
    var onPointer: (Bool) -> Void = { _ in }
    var onTap: () -> Void = {}
    var onIslandPointer: (String, Bool) -> Void = { _, _ in }
    var onIslandTap: (String) -> Void = { _ in }

    var body: some View {
        // The physical notch never changes size, so the capsule must never get smaller than it:
        // spring undershoot is clamped here (otherwise only the capsule would visibly shrink).
        let concealed = model.idleConcealment != .off
        let notchSize = concealed ? .zero : (model.layout?.notch.size ?? .zero)
        let raw = model.bodySize
        let size = CGSize(width: max(raw.width, notchSize.width), height: max(raw.height, notchSize.height))
        // A virtual notch that is thin or hidden keeps laying its content out at the full size: the growing shape reveals it.
        let restSize = model.layout?.bodySize(for: .idle) ?? size
        let virtualContentSize = model.state == .idle
            ? CGSize(width: max(size.width, restSize.width), height: max(size.height, restSize.height)) : size
        // The thin bar's reverse corners are small (it is only a few points tall).
        let floating = model.layout?.isFloating == true
        let ear = floating ? 0 : (concealed ? 3 : NotchGeometry.earRadius)
        let notchHeight = model.layout?.notch.size.height ?? 0
        let isExpanded = model.state == .expanded
        let virtualStrip = model.layout?.virtualContent == true && AppSettings.shared.virtualBigStrip

        let shape = NotchShape(bottomRadius: model.bottomRadius, ear: ear, topRadius: floating ? model.bottomRadius : 0)
        let expandedSize = model.layout?.bodySize(for: .expanded) ?? size
        let contentSize = CGSize(
            width: expandedSize.width, height: max(expandedSize.height - notchHeight - Tuning.shared.expandedBottomInset, 0)
        )

        let compactFade: Animation = model.state == .compact ? .easeOut(duration: 0.18).delay(0.12) : .easeIn(duration: 0.1)
        ZStack(alignment: .top) {
            // Body only (no ears): pointer "inside" must mean the same thing as the interaction controller's zones.
            Color.clear
                .frame(width: size.width, height: size.height)
                .onActiveHover { location in
                    onPointer(location != nil)
                    updateCompactHover(at: location, bodyWidth: size.width)
                }
                // The small capsule takes the same swipe as the open media page (only while a song is its main activity).
                .modifier(CompactTrackSwipe(model: model))
            // The open capsule's whole final area takes clicks from the first frame of its (spring) growth: until the drawn shape
            // has caught up, those pixels are fully transparent and clicks fell through to the windows behind. Nearly invisible.
            if isExpanded {
                Color.black.opacity(0.01)
                    .frame(width: expandedSize.width + 2 * ear, height: expandedSize.height)
                    .contentShape(Rectangle())
            }
            // While the previous / next icon shows, the black body stretches: a lot on the icon's side, a little on the other
            // (with a jelly bounce); the content stays put.
            let main = Tuning.shared.stepGrow * model.stepGrow, other = Tuning.shared.stepGrowOther * model.stepGrow
            shape
                .fill(Color.black)
                .frame(width: size.width + 2 * ear + main + other, height: size.height)
                .overlay(shape.stroke(Color.white.opacity(model.isFlashing ? 0.9 : 0), lineWidth: 2.5))
                .opacity(model.idleConcealment == .hidden ? 0 : 1)
                .shadow(color: .black.opacity(model.isSwelled && !model.hudShowing ? 0.55 : (floating ? 0.3 : 0)),
                        radius: floating ? 7 : 9, x: 0, y: 5)
                .offset(x: model.stepSide * (main - other) / 2)

            // Content keeps a fixed layout and is revealed by the growing shape (clipped), instead of
            // being stretched with it. It blur-fades in after the frame has started to open (reference
            // layout-彈出.mp4) and blur-fades out immediately on collapse.
            ZStack(alignment: .top) {
                // While the capsule is still larger than its compact size (collapsing) the content keeps its final
                // size and place instead of flying in from the edges; it only fades in.
                // A virtual notch (no physical one) fills its three parts: battery · clock · (free), see VirtualNotchContent.
                if model.layout?.virtualContent == true {
                    VirtualNotchContent(model: model, size: virtualContentSize)
                        .frame(width: virtualContentSize.width, height: virtualContentSize.height, alignment: .top)
                        .opacity(isExpanded ? 0 : 1)
                        .animation(.easeOut(duration: 0.18), value: isExpanded)
                        .modifier(RevealEffect(isVisible: !model.hudShowing, delay: 0.02, blurOnExit: true))
                }
                // The volume / brightness HUD and the system-event card: shapes the capsule widens into.
                CapsuleSystemContent(model: model, notchSize: notchSize)
                if let timerMode = model.activity?.kind.timerMode {
                    // The timer's icon and digits are laid out in the capsule's own animated frame, so they move rigidly
                    // with its edges (no separate target size to drift from).
                    TimerMainRow(model: model, mode: timerMode, size: size)
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .opacity(model.state == .compact ? 1 : 0)
                        .animation(compactFade, value: model.state)
                        .modifier(RevealEffect(isVisible: !model.hudShowing, delay: 0.02, blurOnExit: true))
                } else {
                    CompactContent(model: model, symbolName: model.activity?.symbolName ?? "music.note")
                        .frame(width: min(size.width, compactTargetWidth(model)), height: size.height, alignment: .top)
                        .opacity(model.state == .compact ? 1 : 0)
                        .animation(compactFade, value: model.state)
                        .modifier(RevealEffect(isVisible: !model.hudShowing, delay: 0.02, blurOnExit: true))
                }

                if model.expandedMounted {
                    ExpandedModulesView(
                        registry: registry, layout: model.layout ?? CapsuleLayout(notch: .placeholder), contentSize: contentSize
                    )
                    .environment(\.capsuleExpanded, isExpanded)
                    .frame(width: contentSize.width, height: contentSize.height)
                    .padding(.top, notchHeight)
                    .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
                    .modifier(RevealEffect(isVisible: isExpanded, delay: 0.1, blurOnExit: false))
                // Top-left, beside the notch: switch between the modules and the file shelf.
                if registry.focusedModuleID != nil {
                    FocusHeader(registry: registry)
                        .padding(.leading, 18)
                        .frame(width: expandedSize.width, height: notchHeight, alignment: .leading)
                        .modifier(RevealEffect(isVisible: isExpanded, delay: 0.14, blurOnExit: false))
                } else if registry.availableTabs.count > 1 {
                    // Only the strip left of the physical notch is free: the pair shrinks to icons when it is narrow.
                    let notchWidth = model.layout?.notch.size.width ?? 0
                    let blocked = virtualStrip ? max(notchWidth, VirtualBigStrip.width) : notchWidth
                    let band = max((expandedSize.width - blocked) / 2 - 18 - 8, 60)
                    ModeSwitcher(registry: registry)
                        .frame(width: band, alignment: .leading)
                        .padding(.leading, 18)
                        .padding(.top, max((notchHeight - 22) / 2, 2))
                        .frame(width: expandedSize.width, height: notchHeight, alignment: .topLeading)
                        .modifier(RevealEffect(isVisible: isExpanded, delay: 0.14, blurOnExit: false))
                }
                // A virtual notch: battery · date · time, centred where the small capsule was.
                if virtualStrip {
                    VirtualBigStrip()
                        .frame(width: expandedSize.width, height: notchHeight, alignment: .center)
                        .modifier(RevealEffect(isVisible: isExpanded, delay: 0.14, blurOnExit: false))
                }
                // Top-right, beside the notch: battery and the "new version" tag.
                StatusStrip(hidesBattery: virtualStrip && AppSettings.shared.virtualBigBattery)
                    .padding(.trailing, 18)
                    .frame(width: expandedSize.width, height: notchHeight, alignment: .trailing)
                    .modifier(RevealEffect(isVisible: isExpanded, delay: 0.14, blurOnExit: false))
                }
            }
            .frame(width: size.width + 2 * ear, height: size.height, alignment: .top)
            .clipShape(shape)

            SecondaryIslands(model: model, registry: registry, onPointer: onIslandPointer, onTap: onIslandTap)
                .opacity(model.hudShowing ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: model.hudShowing)

            if model.state == .compact, model.activity?.kind == .media, model.stepActive {
                StepIconOverlay(model: model, bodyWidth: size.width)
            }
        }
        // A track change shows the song line for a moment (hover on the cover shows it as before).
        .onChange(of: model.media?.trackChangeToken) { _, _ in model.noteTrackChange() }
        .padding(.top, model.layout?.notch.floatGap ?? 0) // a floating capsule hangs below the top edge
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap) // the interaction controller ignores taps outside the visible body
    }
}

/// Width the compact capsule settles at (swollen while hovered).
@MainActor
private func compactTargetWidth(_ model: CapsuleModel) -> CGFloat {
    guard let layout = model.layout else { return 0 }
    let compact = layout.bodySize(for: .compact)
    return model.showsSwell ? layout.swelledSize(compact, reduceMotion: model.reduceMotion).width : compact.width
}

private struct CompactContent: View {
    let model: CapsuleModel
    let symbolName: String

    private var media: MediaController? { model.media }
    private var isVisible: Bool { model.state == .compact }

    var body: some View {
        let notch = model.layout?.notch.size ?? .zero
        // While the capsule swells (also while the song info is shown) the row fills the swollen height; icons
        // are centred in their wing with the same margin on every side (top, bottom, notch side, outer edge).
        let compact = model.layout?.bodySize(for: .compact) ?? .zero
        let target = model.showsSwell ? (model.layout?.swelledSize(compact, reduceMotion: model.reduceMotion) ?? compact) : compact
        let rowHeight = target.height
        let wing = max((target.width - notch.width - (model.layout?.virtualMiddleExtra ?? 0)) / 2, notch.height)
        let icon = min(wing, rowHeight) - 2 * Tuning.shared.iconMargin
        // On a virtual notch the icons sit against the outer edges (the wings are wider than an icon: battery and percent fit).
        let virtual = model.layout?.virtualContent == true
        ZStack(alignment: .top) {
            // Both icons are pinned to the capsule's own edges (never centred as a pair), so while the capsule is
            // still wider or narrower than its resting size mid-animation they stay at their edge margin. The timer
            // sits on its outer edge too, with the same margin as the icon.
            ZStack {
                leading(size: icon)
                    .opacity(model.stepActive && model.stepSide < 0 ? 0 : 1) // the step icon takes the cover's place
                    .animation(.easeInOut(duration: 0.18), value: [model.stepActive ? model.stepSide : 0])
                    .frame(width: wing, height: rowHeight, alignment: virtual ? .leading : .center)
                    .padding(.leading, virtual ? Tuning.shared.iconMargin : 0)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing(alignment: virtual ? .trailing : .center)
                    .opacity(model.stepActive && model.stepSide > 0 ? 0 : 1)
                    .animation(.easeInOut(duration: 0.18), value: [model.stepActive ? model.stepSide : 0])
                    .frame(width: wing, height: rowHeight, alignment: virtual ? .trailing : .center)
                    .padding(.trailing, virtual ? Tuning.shared.iconMargin + 3 : 0)
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: rowHeight)
            // Pinned below the (unmoving) icon row, so showing it never shifts the row.
            nowPlayingLine
                .padding(.top, rowHeight)
                .modifier(RevealEffect(isVisible: model.showsSongLine, delay: 0.04))
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }

    /// Song and artist with their icons, centred under the icon row: while the pointer is over the cover, and for a moment
    /// after the track changed.
    @ViewBuilder private var nowPlayingLine: some View {
        if model.activity?.kind == .shelf {
            let height = Tuning.shared.songInfoExtra
            ShelfInfoLine()
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .center)
        } else if let snapshot = media?.nowPlaying?.snapshot {
            HStack(spacing: 14) {
                Label(snapshot.title, systemImage: "music.note")
                Label(snapshot.artist, systemImage: "music.mic")
            }
            .labelStyle(SongInfoLabelStyle())
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.58))
            .lineLimit(1)
            .padding(.horizontal, 16)
            // Centred in the song area (no empty band below the text).
            .frame(maxWidth: .infinity, minHeight: Tuning.shared.songInfoExtra, maxHeight: Tuning.shared.songInfoExtra, alignment: .center)
        }
    }

    @ViewBuilder private func leading(size: CGFloat) -> some View {
        // The left icon always belongs to the same activity as the right one (never a cover next to a timer).
        if model.activity?.kind == .media || model.activity == nil,
           AppSettings.shared.showCoverInCompact, let image = media?.artwork, media?.nowPlaying != nil {
            SwappingCover(image: image) { shown in
                if let shown {
                    Image(nsImage: shown)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
                }
            }
            .frame(width: size, height: size)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous).fill(Color.white.opacity(0.18)))
        }
    }

    /// Waveform at rest; while hovered it blur-morphs into play / pause, which is also a button.
    @ViewBuilder private func trailing(alignment: Alignment) -> some View {
        if model.activity?.kind == .shelf {
            if AppSettings.shared.shelfShowsCount {
                Text("\(ShelfStore.shared.items.count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
            }
        } else if AppSettings.shared.showWaveformInCompact, let nowPlaying = media?.nowPlaying {
            let hovering = model.compactHover == .controls
            Button { media?.togglePlayPause() } label: {
                ZStack {
                    // Plain crossfade (no blur layers): the blur version could leave both states invisible.
                    WaveformBars(isPlaying: nowPlaying.isPlaying, isVisible: isVisible && !hovering, palette: media?.artworkPalette)
                        .opacity(hovering ? 0 : 1)
                    Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(hovering ? 1 : 0)
                        .scaleEffect(hovering ? 1 : 0.85)
                }
                .frame(width: 30, height: 30)
                // The whole right wing is the button (it shows play / pause while the pointer is anywhere on it), not only the 30 pt icon.
                .contentShape(Rectangle())
            }
            .buttonStyle(CompactPressStyle(anchor: alignment == .trailing ? .trailing : .center))
        } else {
            Text("⋯")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

private struct CompactPressStyle: ButtonStyle {
    var anchor = UnitPoint.center

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.8 : 1, anchor: anchor)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Blur + fade + slight scale; the entrance waits `delay` so the frame leads the content.
struct RevealEffect: ViewModifier {
    let isVisible: Bool
    let delay: Double
    /// Blurring a large, busy view while it fades out is expensive (visible hitch); big content only fades out.
    var blurOnExit = true

    func body(content: Content) -> some View {
        content
            .blur(radius: isVisible || !blurOnExit ? 0 : 12)
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.94, anchor: .top)
            .animation(
                isVisible ? .easeOut(duration: 0.28).delay(delay) : .easeIn(duration: 0.12),
                value: isVisible
            )
    }
}

/// Remaining (or elapsed) time in the compact capsule; ticks once a second while the timer runs. A countdown also gets
/// a progress line under the digits, 2.5 pt at rest, 4 pt while swollen.
struct CompactTimerText: View {
    /// Swollen (hovered) capsule: the line grows to 4 pt; at rest it is a thin 2.5 pt.
    let mode: TimerEngine.Mode
    let swollen: Bool

    var body: some View {
        let engine = TimerController.shared.engine(for: mode)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let text = TimerEngine.format(engine.displayTime(at: context.date))
            let showBar = AppSettings.shared.timerRing && mode == .countdown
            let barHeight: CGFloat = swollen ? Tuning.shared.progressThick / 2 : 2.5
            let remaining = 1 - engine.progress(at: context.date)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                // A new second replaces the digits at once: during a swell animation they would otherwise cross-fade, and
                // the old and new time were drawn on top of each other.
                .contentTransition(.identity)
                .animation(nil, value: text)
                .fixedSize()
                .frame(width: TimerCompactMetrics.textWidth(text))
                .padding(.bottom, showBar ? Tuning.shared.progressThick / 2 + 2 : 0)
                // The line is an overlay, so it is exactly as wide as the digits.
                .overlay(alignment: .bottom) {
                    if showBar {
                        // Track and fill are plain fixed-size shapes in one ZStack (no GeometryReader), so they animate
                        // together with the capsule's swell and never drift apart.
                        let lineWidth = TimerCompactMetrics.textWidth(text)
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.22))
                            Capsule().fill(.white)
                                // No implicit animation: a 1 s linear animation here hijacked the swell's spring whenever
                                // the tick landed during it, so the fill drifted away from the track. It moves a fraction of
                                // a point per second anyway.
                                .frame(width: max(lineWidth * remaining, 0))
                        }
                        .frame(width: lineWidth, height: barHeight)
                    }
                }
        }
    }
}

/// Icon in front of the text with a small gap, as in the song line of the compact capsule.
private struct SongInfoLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

/// What the compact capsule shows under itself while the shelf is its activity: the newest thing on the shelf, as
/// "name · size", with its file icon in front if the setting asks for it (設定 › 檔案中轉站 › 小膠囊資訊).
private struct ShelfInfoLine: View {
    private let store = ShelfStore.shared
    @State private var settings = AppSettings.shared

    var body: some View {
        if settings.shelfPeekEnabled, let item = store.items.last {
            HStack(spacing: 6) {
                if settings.shelfPeekWithIcon {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: store.url(for: item).path)).resizable().frame(width: 16, height: 16)
                }
                Text("\(item.name) · \(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))")
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.white.opacity(0.58))
            .lineLimit(1)
        }
    }
}
