import SwiftUI

/// The 手勢操控 page's demonstration: on the left a trackpad with two white dots standing for the fingers, on the right the compact
/// capsule doing what it really does for that swipe — the previous / next icon steps in from the edge, the track changes in the
/// middle of the cycle (cover shrinks and springs back, the song line appears), the capsule stretches with a jelly bounce. The
/// whole picture is a pure function of time, so it plays live (`TimelineView`) and can be rendered frame by frame into a GIF.
struct GestureDemo: View {
    static let loop = 6.4

    /// Plays continuously.
    var body: some View {
        TimelineView(.animation) { context in
            GestureDemoFrame(time: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.loop))
        }
    }
}

enum DemoPhase {
    case next, previous

    /// Start and end of the finger movement, seconds into the loop.
    var span: (start: Double, end: Double) { self == .next ? (0.7, 1.95) : (3.7, 4.95) }
}

/// What the swipe is doing at one moment.
struct SwipeState {
    var fingers = 0.0 // 0…1 opacity of the dots
    var fingerX = 0.5 // 0…1 along the trackpad (first finger)
    var secondX = 0.5 // the second finger, trailing
    var pressure = 1.0 // 1 = pressed down, smaller while touching down / lifting
    var icon: DemoPhase?
    var iconIsNext = true
    var rightSide = true // the icon sits on the right edge (fingers moved left)
    var iconFade = 1.0 // extra fade when a swipe is let go before the change
    var iconProgress = 0.0 // 0…1 (0.5 = the track changes)
    var grow = 0.0 // 0…1 capsule stretch
    var track = 0
    var changedAt: Double? // when the current track appeared
}

/// The capsule's stretch is the real one: a spring (response 0.34 s, damping 0.45 — `CapsuleModel.jelly`) that is set to 1 when the
/// icon appears and back to 0 when the fingers lift. The spring is linear, so the stretch is the sum of two step responses (on at
/// `on`, off at `off`) and overshoots / wobbles exactly like the app's.
func jelly(at time: Double, on: Double, off: Double) -> Double {
    func step(_ elapsed: Double) -> Double {
        guard elapsed > 0 else { return 0 }
        let omega = 2 * Double.pi / 0.34, zeta = 0.45
        let damped = omega * (1 - zeta * zeta).squareRoot()
        return 1 - exp(-zeta * omega * elapsed) * (cos(damped * elapsed) + zeta * omega / damped * sin(damped * elapsed))
    }
    return step(time - on) - step(time - off)
}

/// How a hand really swipes: it gets going quickly and then takes its time arriving (a smoothstep of a front-loaded clock), instead
/// of an even, mechanical glide.
private func swipeEase(_ value: Double) -> Double {
    let clamped = min(max(value, 0), 1)
    let front = 1 - pow(1 - clamped, 1.5) // front-loaded clock
    return front * front * front * (front * (front * 6 - 15) + 10) // smootherstep: slow start, fast middle, long gentle arrival
}

func smooth(_ value: Double) -> Double {
    let clamped = min(max(value, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
}

private func state(at time: Double) -> SwipeState {
    var result = SwipeState()
    for phase in [DemoPhase.next, .previous] {
        let (start, end) = phase.span
        let appear = 0.25
        guard time >= start - appear, time <= end + 1.0 else { continue }
        let travel = swipeEase((time - start) / (end - start)) // eased finger travel
        let lagged = swipeEase((time - start - 0.045) / (end - start)) // the second finger trails a little
        let moving = time >= start && time <= end
        if time < start { result.fingers = smooth((time - (start - appear)) / appear) } else if moving { result.fingers = 1 } else {
            result.fingers = 1 - smooth((time - end) / 0.2)
        }
        result.fingerX = phase == .next ? 0.82 - 0.64 * travel : 0.18 + 0.64 * travel
        result.secondX = phase == .next ? 0.82 - 0.64 * lagged : 0.18 + 0.64 * lagged
        result.pressure = 0.82 + 0.18 * result.fingers
        // The icon follows the fingers (after a short dead zone), finishes its cycle once they lift.
        let deadZone = 0.12
        var progress = min(max((travel - deadZone) / (1 - deadZone), 0), 1) * 0.96
        if time > end { progress = 0.96 + 0.04 * smooth((time - end) / 0.25) }
        if travel > deadZone || time > end {
            result.icon = phase
            result.rightSide = phase == .next
            result.iconIsNext = phase == .next
            result.iconProgress = progress
        }
        result.grow += jelly(at: time, on: timeWhenTravelReaches(0.12, phase: phase), off: end)
    }
    // Track changes in the middle of each cycle.
    let nextChange = timeWhenProgressReaches(0.5, phase: .next), previousChange = timeWhenProgressReaches(0.5, phase: .previous)
    if time >= previousChange {
        result.track = 0; result.changedAt = previousChange
    } else if time >= nextChange {
        result.track = 1; result.changedAt = nextChange
    }
    return result
}

/// The moment the (eased) finger travel reaches `target` of its distance.
private func timeWhenTravelReaches(_ target: Double, phase: DemoPhase) -> Double {
    let (start, end) = phase.span
    var low = start, high = end
    for _ in 0..<30 {
        let mid = (low + high) / 2
        if swipeEase((mid - start) / (end - start)) < target { low = mid } else { high = mid }
    }
    return (low + high) / 2
}

/// The moment the icon's progress crosses `target` while the fingers move (inverts the same easing used above).
private func timeWhenProgressReaches(_ target: Double, phase: DemoPhase) -> Double {
    let (start, end) = phase.span
    var low = start, high = end
    for _ in 0..<30 {
        let mid = (low + high) / 2
        let travel = swipeEase((mid - start) / (end - start))
        let progress = min(max((travel - 0.12) / 0.88, 0), 1) * 0.96
        if progress < target { low = mid } else { high = mid }
    }
    return (low + high) / 2
}

struct GestureDemoFrame: View {
    let time: Double
    /// Live state while the pointer is over the trackpad (the visitor swipes for real); nil = the looping demo.
    var live: SwipeState?
    /// Natural size of the picture (trackpad + island); the page scales it up to the room it has.
    static let size = CGSize(width: 220 + 22 + 330, height: 150)

    var body: some View {
        let swipe = live ?? state(at: time)
        HStack(spacing: 22) {
            Trackpad(swipe: swipe, showsHint: live == nil)
            DemoIsland(swipe: swipe, time: time)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

/// The demo as the page shows it: no card of its own (the section already is one), as large as the width allows. It loops by
/// itself; with the pointer over the trackpad the dots and the hint go away and the real two-finger swipe drives the island, with
/// the sensitivity and direction from the settings.
struct GestureDemoView: View {
    @State private var interaction = LiveSwipe()

    var body: some View {
        // The box takes the picture's proportions at the width the page offers (up to 1.7×); the picture is scaled to fill it.
        Color.clear
            .aspectRatio(GestureDemoFrame.size.width / GestureDemoFrame.size.height, contentMode: .fit)
            .frame(maxWidth: GestureDemoFrame.size.width * 1.7)
            .overlay {
                GeometryReader { proxy in
                    let scale = proxy.size.width / GestureDemoFrame.size.width
                    TimelineView(.animation) { context in
                        let now = context.date.timeIntervalSinceReferenceDate
                        GestureDemoFrame(
                            time: interaction.hovering ? now : now.truncatingRemainder(dividingBy: GestureDemo.loop),
                            live: interaction.hovering ? interaction.state(at: now) : nil
                        )
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    }
                    // The trackpad's area: hover switches to the live mode and its scroll events become the swipe.
                    Color.clear
                        .frame(width: 220 * scale, height: 150 * scale)
                        .contentShape(Rectangle())
                        .onHover { interaction.hovering = $0; if !$0 { interaction.release() } }
                        .onScrollWheelPhased { dx, dy, phase in interaction.scroll(dx, dy, phase) }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity)
    }
}

private struct Trackpad: View {
    let swipe: SwipeState
    var showsHint = true

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.25)).frame(width: 220, height: 150)
            if showsHint {
                Text("將游標移入來試試看").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                    .frame(width: 220, height: 150)
            }
            finger(x: swipe.fingerX, y: 0.34)
            finger(x: swipe.secondX, y: 0.66)
        }
        .frame(width: 220, height: 150)
    }

    private func finger(x position: Double, y row: Double) -> some View {
        ZStack {
            Circle().fill(.white.opacity(0.22)).frame(width: 44, height: 44).scaleEffect(swipe.pressure) // soft halo
            Circle().fill(.white).frame(width: 28, height: 28).scaleEffect(swipe.pressure)
        }
        .opacity(swipe.fingers)
        .offset(x: 220 * position - 22, y: 150 * row - 22)
    }
}

private struct DemoIsland: View {
    let swipe: SwipeState
    let time: Double

    private let width: CGFloat = 330
    private let capsuleWidth: CGFloat = 236
    private let capsuleHeight: CGFloat = 32
    private let infoHeight: CGFloat = 28

    var body: some View {
        let tracks = [("歌名", "歌手"), ("歌名", "歌手")]
        let track = tracks[swipe.track]
        // Song line: shown for about 2 s after a change (shorter than the real 2.5 s, to keep the loop brisk).
        let sinceChange = swipe.changedAt.map { time - $0 } ?? 99
        let info = smooth(sinceChange / 0.25) * (1 - smooth((sinceChange - 1.8) / 0.25))
        let side: CGFloat = swipe.rightSide ? 1 : -1 // fingers left = icon on the right edge
        let main = 34 * swipe.grow, other = 8 * swipe.grow
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.3, blue: 0.62), Color(red: 0.5, green: 0.28, blue: 0.58)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Rectangle().fill(.black.opacity(0.35)).frame(height: capsuleHeight).frame(maxHeight: .infinity, alignment: .top)
            // The body stretches (a lot on the icon's side, a little on the other) and gains the song line's height.
            NotchShape(bottomRadius: 14 + 8 * info)
                .fill(Color.black)
                .frame(width: capsuleWidth + 16 + main + other, height: capsuleHeight + infoHeight * info)
                .offset(x: side * (main - other) / 2)
            content(track: track, side: side, info: info)
            if swipe.icon != nil {
                let edge = capsuleWidth / 2 + 17
                let progress = swipe.iconProgress
                let fade = StepFade.opacity(at: progress) * swipe.iconFade
                Image(systemName: swipe.iconIsNext ? "forward.end.fill" : "backward.end.fill")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .scaleEffect(0.8 + 0.2 * fade).opacity(fade)
                    .offset(x: side * (edge - progress * 54))
                    .frame(height: capsuleHeight)
            }
        }
        .frame(width: width, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder private func content(track: (String, String), side: CGFloat, info: Double) -> some View {
        let hideLeft = swipe.icon != nil && side < 0, hideRight = swipe.icon != nil && side > 0
        let sinceChange = swipe.changedAt.map { time - $0 } ?? 99
        // Cover: shrinks and springs back around the change.
        let coverScale: Double = {
            if sinceChange < 0 { return 1 }
            if sinceChange < 0.16 { return 1 - 0.26 * smooth(sinceChange / 0.16) }
            let settle = sinceChange - 0.16 // springs back with a small overshoot
            return 1 - 0.26 * exp(-settle * 9) * cos(settle * 16)
        }()
        VStack(spacing: 0) {
            HStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient(
                        colors: swipe.track == 0 ? [Color(red: 0.7, green: 0.1, blue: 0.2), Color(red: 0.25, green: 0.05, blue: 0.1)]
                            : [Color(red: 0.3, green: 0.7, blue: 0.4), Color(red: 0.1, green: 0.3, blue: 0.2)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 22, height: 22).scaleEffect(coverScale).opacity(hideLeft ? 0 : 1)
                Spacer()
                HStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule().fill(.white).frame(width: 3, height: 6 + 7 * abs(sin(time * 5 + Double(index) * 1.3)))
                    }
                }
                .opacity(hideRight ? 0 : 1)
            }
            .padding(.horizontal, 18).frame(width: capsuleWidth, height: capsuleHeight)
            HStack(spacing: 12) {
                Label(track.0, systemImage: "music.note")
                Label(track.1, systemImage: "music.mic")
            }
            .labelStyle(.titleAndIcon)
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            .frame(width: capsuleWidth, height: infoHeight).opacity(info).blur(radius: 4 * (1 - info))
        }
        .frame(height: capsuleHeight + infoHeight)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The step icon's fade, the same curve as the capsule's real one (`StepIconOverlay.opacity`).
private enum StepFade {
    static func opacity(at progress: Double) -> Double { StepIconOverlay.opacity(at: progress) }
}

#if DEBUG
import AppKit

extension IllustrationExporter {
    /// PENDANT_DEBUG_GESTURE_DEMO=<folder>: renders the demo frame by frame (60 fps) for building a preview GIF.
    @MainActor static func exportGestureFrames(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let frames = Int(GestureDemo.loop * 60)
        for index in 0..<frames {
            let view = GestureDemoFrame(time: Double(index) / 60).padding(14)
                .background(Color(white: 0.16)).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1.5
            guard let image = renderer.cgImage else { continue }
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: folder.appendingPathComponent(String(format: "f%03d.png", index)))
        }
    }
}
#endif
