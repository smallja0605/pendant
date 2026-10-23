import AppKit
import Observation
import SwiftUI

/// What the volume / brightness HUD shows right now. The capsule draws it itself (its own shape widens into the HUD and back).
struct LevelHUD: Equatable {
    enum Kind { case volume, brightness }

    var kind = Kind.volume
    var level = 0.5
    var muted = false
}

/// The volume / brightness HUD's timing: the notch (the capsule itself, not a window above it) grows a wing each side — icon and
/// name left, percentage and a bar right — for a moment, then tucks back. This controller only decides when: the capsule model
/// holds the state and `CapsuleView` draws it.
@MainActor
final class NotchHUDController {
    static var wingWidth: CGFloat { CapsuleLayout.hudWing }

    private let model: CapsuleModel
    private var hideTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    /// True while the HUD is out: the capsule's own contents tuck away, and come back when this turns false.
    var onVisibilityChange: ((Bool) -> Void)?
    /// Asks the window to make its panel as big as the HUD needs (before it grows) or small again (after it has folded).
    var updatePanel: (() -> Void)?

    init(model: CapsuleModel) { self.model = model }

    var isShowing: Bool { model.levelHUDWanted }

    /// `notch` is the notch's frame in screen coordinates.
    func show(_ level: SystemLevel, notch: CGRect) {
        var hud = model.levelHUD
        switch level {
        case let .volume(value, muted):
            hud = LevelHUD(kind: .volume, level: value, muted: muted)
        case let .brightness(value):
            hud = LevelHUD(kind: .brightness, level: value, muted: false)
        }
        model.presentLevelHUD(hud)
        updatePanel?() // room first, then the animation
        if !model.levelHUDVisible {
            onVisibilityChange?(true) // the capsule's contents blur out as it widens into the HUD
            model.setLevelHUDVisible(true)
        }
        watchHover(notch: notch)
        hideTask?.cancel()
        let seconds = AppSettings.shared.hudSeconds
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            fold()
        }
    }

    private func fold() {
        hoverTask?.cancel()
        model.setLevelHUDVisible(false)
        onVisibilityChange?(false) // the capsule's contents come back as it folds
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            model.clearLevelHUD()
            updatePanel?()
        }
    }

    /// While the HUD is up the pointer is watched: over the HUD or the notch it swells, the same jelly swell the compact capsule
    /// has on hover, with the same trackpad tick when it is entered.
    private func watchHover(notch: CGRect) {
        guard AppSettings.shared.hoverEffectEnabled else { return }
        hoverTask?.cancel()
        let area = CGRect(
            x: notch.midX - (notch.width + 2 * Self.wingWidth) / 2 - 6, y: notch.minY - 14,
            width: notch.width + 2 * Self.wingWidth + 12, height: notch.height + 14 + 6
        )
        hoverTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let inside = area.contains(NSEvent.mouseLocation)
                if inside != model.levelHUDSwelled {
                    model.setLevelHUDSwelled(inside)
                    if inside { HapticService.shared.play(.notchEnter) }
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    func hideNow() {
        hoverTask?.cancel()
        hideTask?.cancel()
        let wasOut = model.levelHUDVisible
        model.resetLevelHUD()
        if wasOut { onVisibilityChange?(false) }
        updatePanel?()
    }
}

/// The HUD's row of contents inside the capsule: icon and name in the left wing, percentage and bar in the right wing, the notch's
/// width left empty between them. Laid out at its final size; the capsule's shape reveals it as it widens.
struct HUDRowContent: View {
    let hud: LevelHUD
    let notchWidth: CGFloat
    let height: CGFloat

    private static let iconSize: CGFloat = 18
    /// Where the name starts, measured from the capsule's left edge (unchanged when the icon size changes).
    private static let nameOffset: CGFloat = 36

    var body: some View {
        // The icon sits as far from the capsule's edge as from its bottom; the gap to the name makes up the rest.
        let margin = max((height - Self.iconSize) / 2, 3)
        HStack(spacing: 0) {
            HStack(spacing: max(Self.nameOffset - margin - Self.iconSize, 6)) {
                HUDIcon(kind: hud.kind, level: hud.level, muted: hud.muted)
                    .frame(width: Self.iconSize, height: Self.iconSize)
                Text(hud.kind == .volume ? "音量" : "亮度")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.leading, margin)
            .frame(width: NotchHUDController.wingWidth, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            HStack(spacing: 8) {
                Text("\(Int((hud.level * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize() // "100%" never wraps
                    .frame(width: 38, alignment: .trailing)
                HUDBar(level: hud.level)
                    .frame(width: 36, height: 5)
            }
            .padding(.trailing, margin)
            .frame(width: NotchHUDController.wingWidth, alignment: .trailing)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Thin progress bar; the fill follows the level with a short ease so key repeats glide.
struct HUDBar: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.22))
                Capsule().fill(Color.white).frame(width: max(proxy.size.height, proxy.size.width * level))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}

/// The speaker's waves grow with the volume (mute: a slashed speaker); the sun's rays grow longer with the brightness.
struct HUDIcon: View {
    let kind: LevelHUD.Kind
    let level: Double
    let muted: Bool

    var body: some View {
        switch kind {
        case .volume:
            if muted || level <= 0 {
                Image(systemName: "speaker.slash.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            } else {
                Image(systemName: "speaker.wave.3.fill", variableValue: level)
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
        case .brightness:
            SunIcon(level: level)
        }
    }
}

/// A sun: a disc whose rays are short when the screen is dim and long when it is bright.
struct SunIcon: View {
    var level: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width * 0.19
            let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: disc), with: .color(.white))
            let inner = radius + size.width * 0.09
            let shortest = size.width * 0.03, longest = size.width * 0.19
            let length = shortest + (longest - shortest) * level
            for index in 0..<8 {
                let angle = Double(index) * .pi / 4
                var ray = Path()
                ray.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                ray.addLine(to: CGPoint(x: center.x + cos(angle) * (inner + length), y: center.y + sin(angle) * (inner + length)))
                context.stroke(ray, with: .color(.white), style: StrokeStyle(lineWidth: size.width * 0.085, lineCap: .round))
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
