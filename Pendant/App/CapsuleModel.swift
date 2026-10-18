import AppKit
import Observation
import SwiftUI

/// Single source of truth for what the capsule looks like. Views read it; the
/// interaction controller writes it.
/// What the compact capsule is showing.
enum ActivityKind: String {
    case media, timer, stopwatch, shelf

    /// The timer-like activities (countdown, stopwatch) share the compact layout of digits + icon.
    var timerMode: TimerEngine.Mode? {
        switch self {
        case .media, .shelf: nil
        case .timer: .countdown
        case .stopwatch: .stopwatch
        }
    }
}

// The model is the one place all capsule state lives (observed by the views); it grows with each visual state.
@MainActor
@Observable
// swiftlint:disable:next type_body_length
final class CapsuleModel {
    /// Which part of the compact capsule the pointer is over.
    enum CompactHover { case artwork, controls }

    struct Activity: Equatable {
        var symbolName: String
        var kind: ActivityKind = .media
    }

    // Settings live in `AppSettings` (UserDefaults-backed); these forward to it.
    var hoverEffectEnabled: Bool { AppSettings.shared.hoverEffectEnabled }
    var hoverExpandMode: HoverExpandMode { AppSettings.shared.hoverExpandMode }
    var hoverDelay: TimeInterval { AppSettings.shared.hoverDelay }
    var collapseDelay: TimeInterval { AppSettings.shared.collapseDelay }
    let swellLeaveDelay: TimeInterval = 0.15

    private(set) var layout: CapsuleLayout?
    private(set) var state: CapsuleState = .idle
    private(set) var isSwelled = false
    private(set) var compactHover: CompactHover?
    /// Increments on every call to `flash()` (timer finished); the view pulses its outline.
    private(set) var flashCount = 0
    private(set) var isFlashing = false
    /// The module pages exist only while the capsule is (about to be) open: collapsed they cost nothing.
    private(set) var expandedMounted = false
    @ObservationIgnored private var unmountTask: Task<Void, Never>?
    @ObservationIgnored private var hoverClearTask: Task<Void, Never>?
    private(set) var activity: Activity?

    // MARK: Secondary islands (3.5)
    /// Live activities shown as secondary islands, in level order; their positions are in `layout.secondaries`.
    private(set) var secondaryActivities: [LiveActivity] = []
    /// A menu is open under the islands (3.5.8 ②): they fade out until it closes.
    private(set) var menuSuppressed = false
    /// Island under the pointer (hover scale, keeps hover-only islands revealed).
    private(set) var hoveredIsland: String?
    /// The timer-end notice is up: the main island shows it like the song line (swollen, with an info row).
    private(set) var isAlerting = false
    private(set) var briefActive = false
    /// The song line is up because the track just changed (not because of hover).
    private(set) var trackInfoVisible = false
    @ObservationIgnored private var trackInfoTask: Task<Void, Never>?
    private(set) var revealHold = false
    @ObservationIgnored private var briefTask: Task<Void, Never>?
    @ObservationIgnored private var holdTask: Task<Void, Never>?
    /// Source of the compact capsule's artwork and waveform.
    var media: MediaController?
    private(set) var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    /// The next expansion comes from a click (the trackpad clicked already): no extra haptic.
    @ObservationIgnored var suppressExpandHaptic = false

    /// Called *before* the animation starts so the panel can be resized first.
    var willChangeState: ((CapsuleState) -> Void)?
    /// Asks whether something (the output popover, a separate window) requires the capsule to stay open.
    var keepsOpen: (() -> Bool)?
    /// Called once the transition animation has finished and the state is still the target.
    var didSettle: ((CapsuleState) -> Void)?

    var restingState: CapsuleState { ExpandPolicy.restingState(hasActivity: activity != nil) }

    /// The volume / brightness HUD is out over the compact capsule: its contents blur out while the HUD's own shape (which starts
    /// exactly as wide as the capsule) widens and shows its contents, and the other way round when it goes.
    private(set) var hudShowing = false

    func setHUDShowing(_ showing: Bool) {
        guard showing != hudShowing else { return }
        withAnimation(reduceMotion ? AnimationTokens.reduced : .spring(response: 0.3, dampingFraction: 0.82)) { hudShowing = showing }
    }

    var bodySize: CGSize {
        guard let layout else { return .zero }
        let size = layout.bodySize(for: state)
        // While the HUD is out the capsule stays exactly its resting size under it: no swell, no peek line (it would show
        // around the HUD as a second, bigger capsule).
        if hudShowing, state != .expanded { return size }
        if state == .compact, showsPeek {
            // Same swollen size as a plain hover (the cover must not shrink), plus room for song / artist.
            let swollen = layout.swelledSize(size, reduceMotion: reduceMotion)
            let info = isAlerting ? CapsuleLayout.compactInfoHeight : Tuning.shared.songInfoExtra
            return CGSize(width: swollen.width, height: swollen.height + info)
        }
        return isSwelled ? layout.swelledSize(size, reduceMotion: reduceMotion) : size
    }

    /// The song line under the capsule (hovering the cover) or the timer notice. The timer itself has no song line, so
    /// hovering its icon only swells the capsule.
    var showsPeek: Bool {
        !hudShowing && (isAlerting || trackInfoVisible || (compactHover == .artwork && activity?.kind.timerMode == nil))
    }

    /// Song and artist line: while hovering the cover, and for a moment after the track changed.
    var showsSongLine: Bool { trackInfoVisible || compactHover == .artwork }

    /// The track changed: show the song line for the configured time (compact capsule with music as main island only).
    func noteTrackChange() {
        let settings = AppSettings.shared
        guard settings.showTrackInfoOnChange, state == .compact, activity?.kind == .media else { return }
        trackInfoTask?.cancel()
        if !trackInfoVisible {
            withAnimation(reduceMotion ? AnimationTokens.reduced : AnimationTokens.hoverSwell) { trackInfoVisible = true }
        }
        let seconds = settings.trackInfoSeconds
        trackInfoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            withAnimation(reduceMotion ? AnimationTokens.reduced : AnimationTokens.unswell) { trackInfoVisible = false }
        }
    }

    // MARK: Previous / next swipe on the compact capsule

    /// The icon steps inward from the capsule's edge on the side the fingers moved towards (one cycle: appears, the track
    /// changes in the middle, disappears; a swipe that goes on repeats it).
    private(set) var stepActive = false
    /// 0…1: where the icon is on its way in (0 = at the edge, 0.5 = the track changes, 1 = gone).
    private(set) var stepProgress = 0.0
    /// Which symbol: next (true) or previous.
    private(set) var stepForward = true
    /// +1: the icon is on the right edge (fingers moved left), −1: on the left.
    private(set) var stepSide = 1.0
    /// 0…1: how far the capsule has stretched (the icon's side a lot, the other side a little, with a jelly bounce).
    private(set) var stepGrow = 0.0
    /// 1 normally; fades to 0 in place when a swipe is cancelled (stopped short) instead of the icon sliding back.
    private(set) var stepFade = 1.0
    @ObservationIgnored private var stepTask: Task<Void, Never>?

    private var jelly: Animation { reduceMotion ? AnimationTokens.reduced : .spring(response: 0.34, dampingFraction: 0.45) }

    func stepBegan(leftwards: Bool, forward: Bool) {
        stepTask?.cancel()
        let side = leftwards ? 1.0 : -1.0
        stepProgress = 0
        stepFade = 1
        stepForward = forward
        if stepActive, side != stepSide {
            // Turning around in the middle of a swipe: the capsule's stretch swings over to the other side with a jelly
            // bounce while the icon crossfades there.
            withAnimation(jelly) { stepSide = side; stepGrow = 1 }
        } else {
            stepSide = side
            stepActive = true
            withAnimation(jelly) { stepGrow = 1 }
        }
    }

    func stepMoved(to progress: Double) {
        stepProgress = progress
    }

    /// The swipe ended: the icon finishes its cycle (past the middle) or goes back, and the capsule settles again.
    func stepEnded(at progress: Double) {
        stepTask?.cancel()
        if progress >= 0.5 {
            withAnimation(.easeOut(duration: 0.22)) { stepProgress = 1 }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { stepFade = 0 } // stopped short: fade where it is
        }
        withAnimation(jelly) { stepGrow = 0 }
        stepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.25))
            guard !Task.isCancelled else { return }
            self?.stepActive = false
        }
    }

    /// Swollen look (hover, timer notice or the song line after a track change) of the compact capsule.
    var showsSwell: Bool { !hudShowing && (isSwelled || ((isAlerting || trackInfoVisible) && state == .compact)) }

    func setAlerting(_ alerting: Bool) {
        guard alerting != isAlerting else { return }
        withAnimation(reduceMotion ? AnimationTokens.reduced : (alerting ? AnimationTokens.hoverSwell : AnimationTokens.unswell)) {
            isAlerting = alerting
        }
    }

    var bottomRadius: CGFloat {
        switch state {
        case .idle: isSwelled ? 12 : 10
        case .compact: showsPeek ? 22 : (isSwelled ? 14 : 12)
        case .expanded: 26
        }
    }

    func updateLayout(_ layout: CapsuleLayout?, animated: Bool = false) {
        guard layout != self.layout else { return }
        // Module width / order changes while open animate the capsule's width like any other size change.
        if state == .expanded, self.layout != nil, layout != nil {
            withAnimation(AnimationTokens.expand(reduceMotion: reduceMotion)) { self.layout = layout }
        } else if animated, state == .compact, self.layout != nil, layout != nil {
            // An island was promoted / split: the row glides to its new arrangement.
            withAnimation(AnimationTokens.island(reduceMotion: reduceMotion)) { self.layout = layout }
        } else {
            self.layout = layout
        }
    }

    func refreshReduceMotion() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Region hover from the compact capsule's icons. Leaving a region waits a moment, so that leaving the
    /// whole capsule (which ends swell and peek together, `endCompactHover`) is not played in two steps.
    func setCompactHover(_ hover: CompactHover?) {
        hoverClearTask?.cancel()
        if hover == nil {
            hoverClearTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(70))
                guard !Task.isCancelled else { return }
                self?.applyCompactHover(nil)
            }
        } else {
            applyCompactHover(hover)
        }
    }

    /// Pointer left the compact capsule: peek and swell shrink in one animation.
    func endCompactHover() {
        hoverClearTask?.cancel()
        guard state == .compact else { return }
        withAnimation(reduceMotion ? AnimationTokens.reduced : AnimationTokens.unswell) {
            compactHover = nil
            isSwelled = false
        }
        refreshReveal()
    }

    private func applyCompactHover(_ hover: CompactHover?) {
        guard hover != compactHover, state == .compact else { return }
        if hover != nil { HapticService.shared.play(.hoverControl) }
        withAnimation(reduceMotion ? AnimationTokens.reduced : (hover == nil ? AnimationTokens.unswell : AnimationTokens.hoverSwell)) {
            compactHover = hover
        }
    }

    func setSwelled(_ swelled: Bool) {
        guard swelled != isSwelled else { return }
        let animation = swelled ? AnimationTokens.hoverSwell : AnimationTokens.unswell
        withAnimation(reduceMotion ? AnimationTokens.reduced : animation) {
            isSwelled = swelled
        }
        refreshReveal()
    }

    func transition(to newState: CapsuleState) {
        guard newState != state else { return }
        unmountTask?.cancel()
        if newState == .expanded {
            expandedMounted = true
        } else {
            unmountTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.6)) // after the collapse animation has settled
                guard !Task.isCancelled, let self, state != .expanded else { return }
                expandedMounted = false
            }
        }
        willChangeState?(newState)
        let animation = newState == .expanded
            ? AnimationTokens.expand(reduceMotion: reduceMotion)
            : AnimationTokens.collapse(reduceMotion: reduceMotion)
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            state = newState
            isSwelled = false
            compactHover = nil
        } completion: { [weak self] in
            guard let self, state == newState else { return }
            didSettle?(newState)
        }
        refreshReveal()
    }

    // MARK: Secondary island state

    func setSecondaries(_ activities: [LiveActivity]) {
        guard activities != secondaryActivities else { return }
        withAnimation(AnimationTokens.island(reduceMotion: reduceMotion)) { secondaryActivities = activities }
    }

    func setMenuSuppressed(_ suppressed: Bool) {
        guard suppressed != menuSuppressed else { return }
        withAnimation(AnimationTokens.island(reduceMotion: reduceMotion)) { menuSuppressed = suppressed }
    }

    func setHoveredIsland(_ id: String?) {
        guard id != hoveredIsland else { return }
        withAnimation(AnimationTokens.hoverSwell) { hoveredIsland = id }
        refreshReveal()
    }

    /// "Brief" display mode: show the secondary islands for a few seconds, then fold them into dots.
    func pulseSecondaries(for seconds: Double = 5) {
        briefTask?.cancel()
        withAnimation(AnimationTokens.island(reduceMotion: reduceMotion)) { briefActive = true }
        briefTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation(AnimationTokens.island(reduceMotion: self?.reduceMotion ?? false)) { self?.briefActive = false }
        }
    }

    /// Hover on the main island (or an island) holds hover-only islands visible a moment after the pointer left,
    /// so the pointer can cross the gap to them.
    private func refreshReveal() {
        holdTask?.cancel()
        if isSwelled || hoveredIsland != nil {
            if !revealHold { withAnimation(AnimationTokens.island(reduceMotion: reduceMotion)) { revealHold = true } }
        } else if revealHold {
            holdTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled, let self else { return }
                withAnimation(AnimationTokens.island(reduceMotion: reduceMotion)) { revealHold = false }
            }
        }
    }

    /// Whether the display mode currently wants the secondary islands expanded (otherwise: dots).
    var secondariesRevealed: Bool {
        switch AppSettings.shared.islandDisplayMode {
        case .always: true
        case .brief: briefActive || revealHold
        case .hoverOnly: revealHold
        }
    }

    /// Secondary islands are on screen (compact capsule only, no menu underneath, revealed).
    var secondariesShown: Bool {
        state == .compact && !menuSuppressed && !secondaryActivities.isEmpty && !(layout?.secondaries.isEmpty ?? true)
            && secondariesRevealed
    }

    /// Screen rects of the islands that currently take mouse events.
    var visibleSecondaryRects: [CGRect] { secondariesShown ? (layout?.secondaries.map(\.rect) ?? []) : [] }

    /// Two quick outline pulses (timer finished).
    func flash() {
        flashCount += 1
        Task { @MainActor [weak self] in
            for _ in 0..<2 {
                withAnimation(.easeOut(duration: 0.16)) { self?.isFlashing = true }
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeIn(duration: 0.22)) { self?.isFlashing = false }
                try? await Task.sleep(for: .milliseconds(260))
            }
        }
    }

    func setActivity(_ newActivity: Activity?) {
        activity = newActivity
        switch state {
        case .idle where newActivity != nil: transition(to: .compact)
        case .compact where newActivity == nil: transition(to: .idle)
        default: break
        }
    }
}
