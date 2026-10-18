import SwiftUI

/// Two-finger swipe over the compact capsule changes the track when the main island shows the music; its progress drives
/// the previous / next icon (`StepIconOverlay`) and the capsule's stretch.
struct CompactTrackSwipe: ViewModifier {
    let model: CapsuleModel

    func body(content: Content) -> some View {
        if let media = model.media {
            content.modifier(TrackSwipe(
                controller: media, enabled: model.state == .compact && model.activity?.kind == .media,
                onGesture: { event in
                    switch event {
                    case let .began(leftwards, forward): model.stepBegan(leftwards: leftwards, forward: forward)
                    case let .progress(progress): model.stepMoved(to: progress)
                    case let .ended(progress): model.stepEnded(at: progress)
                    }
                }
            ))
        } else {
            content
        }
    }
}

/// The previous / next icon of a swipe, in the compact capsule's icon row (same height as the cover and the waveform). It
/// follows the fingers: it fades in at the edge on the side they moved towards, steps inward (the track changes in the
/// middle) and fades out; a swipe that keeps going repeats the cycle.
struct StepIconOverlay: View {
    let model: CapsuleModel
    let bodyWidth: CGFloat

    /// 0…1 → 0 → 1 → 0: gradual in during the first quarter, gradual out during the last quarter.
    static func opacity(at progress: Double) -> Double {
        func smooth(_ value: Double) -> Double { let clamped = min(max(value, 0), 1); return clamped * clamped * (3 - 2 * clamped) }
        return smooth(progress / 0.25) * smooth((1 - progress) / 0.25)
    }

    var body: some View {
        let tuning = Tuning.shared
        let layout = model.layout
        let compact = layout?.bodySize(for: .compact) ?? .zero
        let target = model.showsSwell ? (layout?.swelledSize(compact, reduceMotion: model.reduceMotion) ?? compact) : compact
        let notch = layout?.notch.size ?? .zero
        let wing = max((target.width - notch.width) / 2, notch.height)
        let icon = min(wing, target.height) - 2 * tuning.iconMargin
        let progress = model.stepProgress
        let opacity = Self.opacity(at: progress) * model.stepFade
        // Stage 1 sits at the edge of the stretched capsule, stage 3 two steps further in.
        let edge = bodyWidth / 2 + tuning.stepGrow * 0.5
        let offsetX = model.stepSide * (edge - progress * 2 * tuning.stepSpacing)
        Image(systemName: model.stepForward ? "forward.end.fill" : "backward.end.fill")
            .font(.system(size: icon * tuning.stepIconScale, weight: .bold))
            .foregroundStyle(.white)
            .scaleEffect(0.8 + 0.2 * opacity)
            .opacity(opacity)
            // A new side (the swipe turned around) is a new icon: the old one fades out where it was, the new one fades in.
            .id(model.stepSide)
            .transition(.opacity)
            .offset(x: offsetX)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: target.height, alignment: .center)
            .frame(maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
