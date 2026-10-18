import SwiftUI

/// What a horizontal swipe is doing, for the compact capsule's previous / next icon.
enum SwipeGestureEvent {
    /// A swipe started (or turned around): fingers moving left, and whether it will go to the next track.
    case began(leftwards: Bool, forward: Bool)
    /// Position in the current cycle, 0…<1 (0.5 is where the track changes).
    case progress(Double)
    /// Fingers lifted (or a pause) at this cycle position.
    case ended(Double)
}

/// Two-finger horizontal swipe = previous / next track. Used on the open media page and on the compact capsule.
struct TrackSwipe: ViewModifier {
    let controller: MediaController
    var enabled = true
    /// Reports the swipe's progress (compact capsule: drives the icon that steps inward).
    var onGesture: ((SwipeGestureEvent) -> Void)?
    @State private var swipe = SwipeAccumulator()
    @State private var swipeReset: Task<Void, Never>?
    @State private var gestureActive = false
    @State private var lastEvent: TimeInterval?
    @State private var speed = 0.0
    @State private var peakSpeed = 0.0

    func body(content: Content) -> some View {
        content.onScrollWheelPhased { deltaX, deltaY, phase in
            // Vertical-dominant scrolls (e.g. in the output list) and any scroll while a popover is open are left alone.
            let settings = AppSettings.shared
            guard enabled, settings.swipeTracksEnabled, controller.nowPlaying != nil, !AnchoredPopover.isAnyOpen else { return false }
            // A new gesture starts from zero at once. Waiting for a pause instead meant the trackpad's inertia (it keeps
            // sending events for a second or more after the fingers lift) blocked the next swipe for just as long.
            if phase.began { finish() }
            let horizontal = abs(deltaX) > abs(deltaY)
            // The fingers lifting: the icon completes at once. The lift's own event often carries no movement, and the
            // trackpad's inertia that follows never counts (but is not passed on either).
            if phase.momentum { finish(); return horizontal }
            guard horizontal else {
                if phase.ended { finish() }
                return false
            }
            swipe.threshold = settings.swipeThreshold
            swipe.reversed = settings.swipeReversed
            track(deltaX)
            if phase.ended { finish() }
            // A mouse wheel has no phases (and a lost "ended" must not leave the icon up): a pause ends the gesture.
            swipeReset?.cancel()
            if !phase.ended {
                swipeReset = Task {
                    try? await Task.sleep(for: .seconds(phase.hasPhase ? 0.5 : 0.3))
                    guard !Task.isCancelled else { return }
                    finish()
                }
            }
            return true
        }
    }

    /// Quick flicks count for more distance than slow swipes (speed from the time between events, smoothed).
    private func scaled(_ deltaX: Double) -> Double {
        let now = ProcessInfo.processInfo.systemUptime
        let interval = min(max(now - (lastEvent ?? now - 0.016), 0.004), 0.1)
        lastEvent = now
        speed = 0.5 * speed + 0.5 * abs(deltaX) / interval
        peakSpeed = max(peakSpeed, speed)
        let tuning = Tuning.shared
        return deltaX * SwipeSpeed.gain(speed: speed, fast: tuning.swipeFastSpeed, maxGain: tuning.swipeFastGain)
    }

    private func track(_ rawDeltaX: Double) {
        let wasLeftwards = swipe.leftwards
        let action = swipe.add(deltaX: scaled(rawDeltaX))
        // Turned around while the icon was up: it finishes on its side first.
        if gestureActive, swipe.leftwards != wasLeftwards {
            gestureActive = false
            peakSpeed = 0
            onGesture?(.ended(0))
        }
        // The icon only appears after the swipe has travelled a little (the dead zone).
        if swipe.isVisible, !gestureActive {
            gestureActive = true
            onGesture?(.began(leftwards: swipe.leftwards, forward: swipe.currentAction == .next))
        }
        if let action {
            HapticService.shared.play(.swipeCommit)
            if action == .next { controller.next() } else { controller.previous() }
        }
        if gestureActive { onGesture?(.progress(swipe.cycleProgress)) }
    }

    /// The swipe is over. A quick flick that did not get far enough still changes the track (the icon completes its step);
    /// a slow swipe that stops short cancels (the icon just fades where it is).
    private func finish() {
        defer { swipe.reset(); lastEvent = nil; speed = 0; peakSpeed = 0 }
        guard gestureActive else { return }
        gestureActive = false
        var progress = swipe.cycleProgress
        if swipe.cutCount == 0, peakSpeed >= Tuning.shared.swipeFastSpeed * 0.5 {
            HapticService.shared.play(.swipeCommit)
            if swipe.currentAction == .next { controller.next() } else { controller.previous() }
            progress = 1
        }
        onGesture?(.ended(progress))
    }
}

/// A cover that swaps in one continuous motion: it shrinks and dims, the new picture is exchanged at the lowest point and it
/// springs back up, all on a single keyframe curve (no stages, no waiting in between). It starts when the new cover is ready;
/// until then the old one stays as it is.
struct SwappingCover<Content: View>: View {
    let image: NSImage?
    @ViewBuilder let content: (NSImage?) -> Content

    private struct Pose {
        var scale = 1.0
        var opacity = 1.0
    }

    private static var dip: Double { 0.16 }

    @State private var shown: NSImage?
    @State private var swapTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(image: NSImage?, @ViewBuilder content: @escaping (NSImage?) -> Content) {
        self.image = image
        self.content = content
        _shown = State(initialValue: image)
    }

    var body: some View {
        content(shown)
            .keyframeAnimator(initialValue: Pose(), trigger: image.map(ObjectIdentifier.init)) { view, pose in
                view.scaleEffect(pose.scale).opacity(pose.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(0.74, duration: Self.dip)
                    SpringKeyframe(1, duration: 0.5, spring: .bouncy(duration: 0.42, extraBounce: 0.1))
                }
                KeyframeTrack(\.opacity) {
                    CubicKeyframe(0.6, duration: Self.dip)
                    CubicKeyframe(1, duration: 0.28)
                }
            }
            .onChange(of: image.map(ObjectIdentifier.init)) { _, _ in
                swapTask?.cancel()
                guard !reduceMotion else { shown = image; return }
                swapTask = Task {
                    try? await Task.sleep(for: .seconds(Self.dip))
                    guard !Task.isCancelled else { return }
                    shown = image
                }
            }
    }
}
