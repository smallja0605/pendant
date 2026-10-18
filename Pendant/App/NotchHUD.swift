import AppKit
import Observation
import SwiftUI

/// What the volume / brightness HUD shows right now.
@MainActor
@Observable
final class HUDModel {
    enum Kind { case volume, brightness }

    var kind = Kind.volume
    var level = 0.5
    var muted = false
    /// Grown out of the notch (true) or tucked back into it.
    var visible = false
    /// Width of what is under the HUD (the compact capsule, or the notch): the HUD grows from it and folds back to it.
    var restWidth: CGFloat = 0
    /// The pointer is on the HUD / notch: the HUD itself swells (like the capsule does on hover) instead of the capsule beneath.
    var swelled = false
}

/// The volume / brightness HUD: the notch grows a wing on each side — icon and name on the left, percentage and a bar on the
/// right — for a moment, then tucks back. Its own click-through panel above the capsule, so the capsule's state is untouched.
@MainActor
final class NotchHUDController {
    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    private var appearTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    /// True while the HUD is out: the capsule below tucks away, and comes back when this turns false.
    var onVisibilityChange: ((Bool) -> Void)?

    static let wingWidth: CGFloat = 100

    /// `notch` is the notch's frame in screen coordinates; the HUD hangs from it.
    func show(_ level: SystemLevel, notch: CGRect, restWidth: CGFloat) {
        switch level {
        case let .volume(value, muted):
            model.kind = .volume
            model.level = value
            model.muted = muted
        case let .brightness(value):
            model.kind = .brightness
            model.level = value
            model.muted = false
        }
        let firstTime = panel == nil
        let panel = ensurePanel(notch: notch)
        panel.orderFrontRegardless()
        restoreTask?.cancel()
        if !model.visible {
            model.restWidth = max(restWidth, notch.width)
            if firstTime {
                // The very first time the panel and its SwiftUI view have just been created: changing `visible` in the same
                // turn would have nothing to animate from (the view appears already finished). Let it draw once first.
                appearTask?.cancel()
                appearTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled, let self, !model.visible else { return }
                    onVisibilityChange?(true)
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { model.visible = true }
                }
            } else {
                onVisibilityChange?(true) // the capsule's contents blur out as the HUD widens over it
                withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) { model.visible = true }
            }
        }
        watchHover(notch: notch)
        hideTask?.cancel()
        let seconds = AppSettings.shared.hudSeconds
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            hoverTask?.cancel()
            withAnimation(.spring(response: 0.36, dampingFraction: 0.85)) { model.visible = false; model.swelled = false }
            onVisibilityChange?(false) // the capsule's contents come back as the HUD folds onto it
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self.panel?.orderOut(nil)
        }
    }

    /// While the HUD is up the pointer is watched (the panel itself is click-through): over the HUD or the notch it swells, the
    /// same jelly swell the compact capsule has on hover, with the same trackpad tick when it is entered.
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
                if inside != model.swelled {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { model.swelled = inside }
                    if inside { HapticService.shared.play(.notchEnter) }
                }
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    func hideNow() {
        hoverTask?.cancel()
        model.swelled = false
        appearTask?.cancel()
        hideTask?.cancel()
        restoreTask?.cancel()
        onVisibilityChange?(false)
        model.visible = false
        panel?.orderOut(nil)
    }

    private func ensurePanel(notch: CGRect) -> NSPanel {
        let ear = NotchGeometry.earRadius
        let width = notch.width + 2 * (Self.wingWidth + ear) + 64
        let height = notch.height * 1.3 + 10
        let frame = CGRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height)
        if let panel {
            panel.setFrame(frame, display: false)
            if let hosting = panel.contentView?.subviews.first as? NSHostingView<NotchHUDView> {
                hosting.rootView = NotchHUDView(model: model, notchWidth: notch.width, height: notch.height)
            }
            return panel
        }
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 2
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let hosting = NSHostingView(rootView: NotchHUDView(model: model, notchWidth: notch.width, height: notch.height))
        // A plain subview, not the window's content view (same as the capsule's panel): as the content view the hosting view
        // adjusts the window's size limits during layout, which crashed the app with a constraint-update exception.
        hosting.sizingOptions = []
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        self.panel = panel
        return panel
    }
}

struct NotchHUDView: View {
    let model: HUDModel
    let notchWidth: CGFloat
    let height: CGFloat

    private static let iconSize: CGFloat = 18
    /// Where the name starts, measured from the capsule's left edge (unchanged when the icon size changes).
    private static let nameOffset: CGFloat = 36

    var body: some View {
        let ear = NotchGeometry.earRadius
        let full = notchWidth + 2 * NotchHUDController.wingWidth
        let swell = model.swelled && model.visible
        let scale = Tuning.shared
        let width = (model.visible ? full : max(model.restWidth, notchWidth)) * (swell ? scale.swellWidth : 1)
        let rowHeight = height * (swell ? scale.swellHeight : 1)
        let shape = NotchShape(bottomRadius: swell ? 14 : 12)
        // The icon sits as far from the capsule's edge as from its bottom; the gap to the name makes up the rest.
        let margin = max((height - Self.iconSize) / 2, 3)
        ZStack(alignment: .top) {
            // The HUD's own black fades out as it folds: it is a panel above the capsule, and an opaque one hid the capsule's
            // contents coming back until the panel was removed (the "black for a moment").
            shape.fill(Color.black)
                .opacity(model.visible ? 1 : 0)
                .animation(model.visible ? nil : .easeOut(duration: 0.2).delay(0.05), value: model.visible)
            // The contents have their final layout and are revealed like the song line (blur / fade / scale, same timing) while
            // the capsule widens; the capsule also clips them, so nothing is ever seen outside it.
            HStack(spacing: 0) {
                HStack(spacing: max(Self.nameOffset - margin - Self.iconSize, 6)) {
                    HUDIcon(kind: model.kind, level: model.level, muted: model.muted)
                        .frame(width: Self.iconSize, height: Self.iconSize)
                    Text(model.kind == .volume ? "音量" : "亮度")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.leading, margin)
                .frame(width: NotchHUDController.wingWidth, alignment: .leading)
                Color.clear.frame(width: notchWidth)
                HStack(spacing: 8) {
                    Text("\(Int((model.level * 100).rounded()))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize() // "100%" never wraps
                        .frame(width: 38, alignment: .trailing)
                    HUDBar(level: model.level)
                        .frame(width: 36, height: 5)
                }
                .padding(.trailing, margin)
                .frame(width: NotchHUDController.wingWidth, alignment: .trailing)
            }
            .frame(width: full, height: rowHeight)
            .scaleEffect(swell ? scale.swellWidth : 1)
            .modifier(RevealEffect(isVisible: model.visible, delay: 0.1, blurOnExit: true))
        }
        .frame(width: width + 2 * ear, height: rowHeight)
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    let kind: HUDModel.Kind
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
