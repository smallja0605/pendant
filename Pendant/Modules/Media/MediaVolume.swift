import SwiftUI

// MARK: - Volume

struct VolumeButton: View {
    let controller: MediaController
    @State private var popover = AnchoredPopover()
    @State private var level = 0.5

    var body: some View {
        ControlButton(symbol: VolumeIcon.symbol(for: level), size: 15) {
            popover.toggle(size: VolumePopover.size) { _ in AnyView(VolumePopover(controller: controller)) }
        }
        .background(PopoverAnchor(popover: popover))
        .task { level = await controller.volume() }
        .onAppear {
            popover.onVisibilityChange = { shown in
                controller.popoverVisibilityChanged(shown)
                if !shown { Task { level = await controller.volume() } }
            }
        }
        .onDisappear { popover.close() }
        #if DEBUG
        .task {
            // PENDANT_DEBUG_VOLUME=1 opens the volume popover shortly after the capsule opens (visual check).
            guard ProcessInfo.processInfo.environment["PENDANT_DEBUG_VOLUME"] != nil else { return }
            try? await Task.sleep(for: .seconds(3.5))
            popover.toggle(size: VolumePopover.size) { _ in AnyView(VolumePopover(controller: controller)) }
        }
        #endif
    }
}

enum VolumeIcon {
    static func symbol(for volume: Double) -> String {
        switch MediaInteractionMath.volumeLevel(volume) {
        case .muted: "speaker.slash.fill"
        case .low: "speaker.wave.1.fill"
        case .medium: "speaker.wave.2.fill"
        case .high: "speaker.wave.3.fill"
        }
    }
}

struct VolumePopover: View {
    static let size = NSSize(width: 250, height: 48)

    let controller: MediaController
    @State private var volume = 0.5
    @State private var loaded = false
    @State private var tracker = StepTracker(unit: MediaInteractionMath.volumeStepPercent / 100)
    @State private var lastSent = Date.distantPast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: VolumeIcon.symbol(for: volume))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 20)
                .contentTransition(.symbolEffect(.replace))
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule().fill(.white).frame(width: max(width * volume, 0))
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in update(min(max(drag.location.x / max(width, 1), 0), 1), final: false) }
                        .onEnded { drag in update(min(max(drag.location.x / max(width, 1), 0), 1), final: true) }
                )
            }
            .frame(width: 120, height: 22)
            Text("\(Int((volume * 100).rounded()))%")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(width: Self.size.width, height: Self.size.height)
        .task {
            volume = await controller.volume()
            loaded = true
        }
    }

    private func update(_ value: Double, final: Bool) {
        guard loaded else { return }
        volume = value
        if tracker.crossedBoundary(at: value) { HapticService.shared.play(.dragStep) }
        // Throttle the Apple events; the final value is always sent.
        if final || Date().timeIntervalSince(lastSent) > 0.06 {
            lastSent = Date()
            controller.setVolume(value)
        }
        if final { tracker.reset() }
    }
}
