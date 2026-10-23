import SwiftUI

private struct CapsuleExpandedKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ModuleAtCapsuleEdgeKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// True when nothing but the capsule's own edge lies to the right of this module (no neighbour and divider there).
    var moduleAtCapsuleEdge: Bool {
        get { self[ModuleAtCapsuleEdgeKey.self] }
        set { self[ModuleAtCapsuleEdgeKey.self] = newValue }
    }

    /// True while the capsule is open; pauses timelines and animations when it is not.
    var capsuleExpanded: Bool {
        get { self[CapsuleExpandedKey.self] }
        set { self[CapsuleExpandedKey.self] = newValue }
    }
}

/// Large-capsule media page (reference: capsule-media.png / capsule-media-ref2.png).
struct MediaView: View {
    let controller: MediaController
    @Environment(\.capsuleExpanded) private var isExpanded

    var body: some View {
        ZStack {
            if let nowPlaying = controller.nowPlaying {
                PlayerPage(controller: controller, nowPlaying: nowPlaying, isActive: isExpanded)
                    .transition(.opacity)
            } else {
                EmptyMediaView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.nowPlaying != nil)
        .background(alignment: .center) { glow }
        .modifier(TrackSwipe(controller: controller))
    }

    @ViewBuilder private var glow: some View {
        if controller.showsArtworkGlow, let color = controller.artworkColor {
            // Larger than the page and centred on it, so the colour runs up behind the notch without a visible edge.
            RadialGradient(colors: [color.opacity(0.30), .clear], center: .center, startRadius: 0, endRadius: 190)
                .frame(width: 400, height: 400)
                .blur(radius: 10)
                .animation(.easeInOut(duration: 0.5), value: controller.artworkColor)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Player

private struct PlayerPage: View {
    let controller: MediaController
    let nowPlaying: NowPlaying
    let isActive: Bool
    @State private var outputs = AnchoredPopover()

    private var artSize: CGFloat { Tuning.shared.artSize }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: Tuning.shared.sectionSpacing) {
                HStack(alignment: .center, spacing: Tuning.shared.artTextGap) {
                    ArtworkView(
                        image: controller.artwork, trackKey: nowPlaying.snapshot.trackKey,
                        glow: controller.artworkColor, onOpen: { controller.openPlayerApp() }
                    )
                    .frame(width: artSize, height: artSize)
                    VStack(alignment: .leading, spacing: Tuning.shared.textLineSpacing) {
                        HStack(spacing: 2) {
                            Text(nowPlaying.snapshot.title)
                                .font(.system(size: Tuning.shared.titleSize, weight: .bold))
                                .foregroundStyle(.white)
                            FocusEnterButton()
                        }
                        Text(nowPlaying.snapshot.album)
                            .font(.system(size: Tuning.shared.albumSize, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                        Text(nowPlaying.snapshot.artist)
                            .font(.system(size: Tuning.shared.artistSize, weight: .medium))
                            .foregroundStyle(.white.opacity(0.42))
                        Spacer(minLength: 0)
                        controls
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: artSize, alignment: .leading)
                    .animation(.easeInOut(duration: 0.25), value: nowPlaying.snapshot.trackKey)
                }
                if controller.automationDenied && !nowPlaying.hasKnownPosition {
                    PermissionGuide()
                } else {
                    MediaProgressBar(nowPlaying: nowPlaying, isActive: isActive, canSeek: !controller.automationDenied) {
                        controller.seek(to: $0)
                    }
                }
            }
            .padding(.top, Tuning.shared.topPadding)
            .padding(.bottom, Tuning.shared.bottomPadding)

        }
        .onChange(of: isActive) { _, active in if !active { outputs.close() } }
        .onAppear { outputs.onVisibilityChange = { controller.popoverVisibilityChanged($0) } }
        .onDisappear { outputs.close() }
        #if DEBUG
        .task(id: isActive) {
            // PENDANT_DEBUG_OUTPUTS=1 opens the output popover once the capsule is open (visual check).
            guard isActive, ProcessInfo.processInfo.environment["PENDANT_DEBUG_OUTPUTS"] != nil else { return }
            try? await Task.sleep(for: .seconds(0.8))
            outputs.toggle(size: NSSize(width: OutputsPopover.width, height: 120)) { popover in
                AnyView(OutputsPopover(controller: controller) { popover.resize(to: NSSize(width: OutputsPopover.width, height: $0)) })
            }
        }
        #endif
    }

    private var controls: some View {
        HStack(spacing: Tuning.shared.controlsSpacing) {
            ControlButton(symbol: "airplayaudio", size: Tuning.shared.skipIconSize) {
                outputs.toggle(size: NSSize(width: OutputsPopover.width, height: 120)) { popover in
                    AnyView(OutputsPopover(controller: controller) {
                        popover.resize(to: NSSize(width: OutputsPopover.width, height: $0))
                    })
                }
            }
            .background(PopoverAnchor(popover: outputs))
            ControlButton(symbol: "backward.fill", size: Tuning.shared.skipIconSize) { controller.previous() }
            ControlButton(symbol: nowPlaying.isPlaying ? "pause.fill" : "play.fill", size: Tuning.shared.playIconSize,
                          width: Tuning.shared.controlButtonWidth + 2) { controller.togglePlayPause() }
            ControlButton(symbol: "forward.fill", size: Tuning.shared.skipIconSize) { controller.next() }
            VolumeButton(controller: controller)
        }
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    var width: CGFloat = Tuning.shared.controlButtonWidth
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: width, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .hapticOnHover()
        .accessibilityLabel(SymbolLabel.text(for: symbol))
    }
}

/// Cover with a coloured shadow; the cover tilts in 3D towards the pointer; click opens the player app.
private struct ArtworkView: View {
    let image: NSImage?
    let trackKey: String
    let glow: Color?
    let onOpen: () -> Void

    /// Pointer position normalised to -1…1 on both axes while hovering.
    @State private var tilt: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var registry = ModuleRegistry.shared

    var body: some View {
        let hovering = tilt != nil
        let tiltX = tilt?.x ?? 0, tiltY = tilt?.y ?? 0
        let maxAngle = reduceMotion ? 0.0 : 14.0
        SwappingCover(image: image) { shown in
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        Image(systemName: "music.note").font(.system(size: 30, weight: .semibold)).foregroundStyle(.white.opacity(0.35))
                    )
                if let shown {
                    Image(nsImage: shown)
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
        // Flatten the cover once so the 3D transform only moves a cached layer while the pointer moves.
        .drawingGroup()
        // Shadow takes the cover's colour and slides opposite to the tilt.
        .shadow(color: (glow ?? .white).opacity(hovering ? 0.75 : 0.5), radius: hovering ? 20 : 13,
                x: -tiltX * 7, y: 9 - tiltY * 4)
        .rotation3DEffect(.degrees(tiltY * maxAngle), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
        .rotation3DEffect(.degrees(-tiltX * maxAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .scaleEffect(hovering ? 1.05 : 1)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.75), value: tilt)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        // While the page opens or closes the cover moves under a resting pointer; that must not count as hovering (it would
        // leave the cover tilted, and blurred, until the pointer moved).
        .onChange(of: registry.focusTransitioning) { _, moving in if moving { tilt = nil } }
        .onActiveHover(sampled: true) { location in
            guard let location, !registry.focusTransitioning else { tilt = nil; return }
            tilt = CGPoint(x: min(max(location.x / 50 - 1, -1), 1), y: min(max(location.y / 50 - 1, -1), 1))
        }
        .onTapGesture(perform: onOpen)
        #if DEBUG
        .task {
            // PENDANT_DEBUG_TILT=1 drives the tilt like a moving pointer (~120 Hz) so it can be profiled headlessly.
            guard ProcessInfo.processInfo.environment["PENDANT_DEBUG_TILT"] != nil else { return }
            var phase = 0.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(8))
                phase += 0.05
                tilt = CGPoint(x: sin(phase), y: cos(phase * 0.7))
            }
        }
        #endif
        .accessibilityLabel("在播放器中開啟")
        .accessibilityAddTraits(.isButton)
    }
}

private struct EmptyMediaView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.35))
            Text("沒有播放中的音樂")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text("在 Apple Music 或 Spotify 開始播放")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PermissionGuide: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill").foregroundStyle(.white.opacity(0.5))
            Text("需要「自動化」權限才能控制播放與顯示進度")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 0)
            Button("開啟系統設定") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.16)))
            .hapticOnHover()
        }
        .frame(height: 30)
    }
}

// MARK: - Progress

private struct MediaProgressBar: View {
    let nowPlaying: NowPlaying
    let isActive: Bool
    let canSeek: Bool
    let onSeek: (TimeInterval) -> Void

    @State private var dragFraction: Double?
    @State private var hovering = false
    @State private var tracker = StepTracker(unit: 1)

    var body: some View {
        let duration = nowPlaying.snapshot.duration
        let running = isActive && nowPlaying.isPlaying && dragFraction == nil
        // Only ticks while the capsule is open and the track is playing (no polling otherwise).
        TimelineView(.animation(minimumInterval: 0.25, paused: !running)) { context in
            let fraction = dragFraction ?? nowPlaying.progress(at: context.date)
            let position = dragFraction.map { $0 * duration } ?? nowPlaying.position(at: context.date)
            let thick = hovering || dragFraction != nil
            VStack(spacing: 1) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(thick ? 0.24 : 0.18))
                        Capsule().fill(.white).frame(width: max(width * fraction, 0))
                    }
                    .frame(height: thick ? Tuning.shared.progressThick : Tuning.shared.progressThin)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(canSeek && duration > 0 ? dragGesture(width: width, duration: duration) : nil)
                    .animation(.linear(duration: dragFraction != nil ? 0 : 0.25), value: fraction)
                    .animation(.spring(response: 0.25, dampingFraction: 0.65), value: thick)
                }
                .frame(height: 16)
                .onActiveHover { hovering = $0 != nil }
                HStack {
                    Text(MediaInteractionMath.formatTime(position))
                    Spacer()
                    Text(MediaInteractionMath.formatTime(duration))
                }
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private func dragGesture(width: CGFloat, duration: TimeInterval) -> some Gesture {
        let step = MediaInteractionMath.progressStepSeconds(duration: duration)
        return DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let fraction = min(max(drag.location.x / max(width, 1), 0), 1)
                if dragFraction == nil { tracker = StepTracker(unit: step) }
                dragFraction = fraction
                if tracker.crossedBoundary(at: fraction * duration) { HapticService.shared.play(.dragStep) }
            }
            .onEnded { drag in
                let fraction = min(max(drag.location.x / max(width, 1), 0), 1)
                onSeek(fraction * duration)
                dragFraction = nil
            }
    }
}
