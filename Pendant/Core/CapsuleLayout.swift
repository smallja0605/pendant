import CoreGraphics

/// Pure sizing for each capsule state on top of `NotchGeometry`.
/// "Body" rects exclude the reverse-corner ears; the drawn shape is `earRadius` wider on each side.
struct CapsuleLayout: Equatable, Sendable {
    /// Hover swell factors, taken from notch-hover.mp4 (width ≈ +8 %, height ≈ +22 %).
    static var swellScale: CGSize { CGSize(width: Tuning.shared.swellWidth, height: Tuning.shared.swellHeight) }
    /// Much smaller swell used when Reduce Motion is on.
    static let reducedSwellScale = CGSize(width: 1.02, height: 1.04)
    /// Room around the body inside the panel for the swell and its shadow.
    /// Extra height of the compact capsule while it shows the song / artist line.
    static var compactInfoHeight: CGFloat { Tuning.shared.peekExtra }
    static let panelPadding = CGSize(width: 36, height: 56)
    /// Width of each wing the capsule grows for the volume / brightness HUD.
    static let hudWing: CGFloat = 100

    var notch: NotchGeometry
    /// Compact extension per side. Default is square (≈ 1:1 with the notch height): just icon + margin.
    /// Extra width per side while the compact capsule shows a timer (room for the digits).
    var compactActivityExtra: CGFloat = 0
    /// A virtual notch carries content in its three parts (battery / clock / …): its wings are wide enough for that.
    var virtualContent = false
    /// The capsule floats below the top edge (a virtual notch with 懸浮膠囊態 on): rounded all round, no reverse corners.
    var isFloating: Bool { notch.floatGap > 0 }
    static let virtualWing: CGFloat = 50
    /// The virtual notch's idle bar (設定 虛擬瀏海 › 閒置時 › 縮成細條).
    static let virtualSliver = CGSize(width: 56, height: 5)
    var compactWing: CGFloat {
        let base = notch.size.height + Tuning.shared.wingExtra + compactActivityExtra
        return virtualContent ? max(base, Self.virtualWing + Tuning.shared.wingExtra) : base
    }
    var cellWidth: CGFloat = Tuning.shared.cellWidth
    /// Cells of each module on the current page (empty: nothing enabled → a small placeholder width).
    var expandedCells: [Int] = []
    var moduleGap: CGFloat = Tuning.shared.moduleGap
    /// Height of the module area below the notch.
    var expandedContentHeight: CGFloat = Tuning.shared.expandedContentHeight
    var contentInset: CGFloat = Tuning.shared.contentInset
    var screenMargin: CGFloat = 24
    /// The 功能 / 檔案中轉站 pill pair needs the strip beside the notch: the open capsule is never narrower than that.
    var reservesModeSwitcher = false
    static let modeSwitcherWidth: CGFloat = 210
    /// Notes and shelf fill the capsule's whole inner width instead of `cells × cellWidth`.
    var fillsWidth = false
    /// Secondary islands next to the compact capsule (3.5), in screen coordinates. Empty with a single activity.
    var secondaries: [IslandPlacement] = []

    func bodySize(for state: CapsuleState) -> CGSize {
        switch state {
        case .idle:
            return virtualContent ? bodySize(for: .compact) : notch.size
        case .compact:
            return CGSize(width: notch.size.width + 2 * compactWing, height: notch.size.height)
        case .expanded:
            let wanted = expandedCells.isEmpty
                ? 4 * cellWidth + 2 * contentInset
                : ModulePager.contentWidth(cellCounts: expandedCells, cellWidth: effectiveCellWidth, gap: moduleGap, inset: contentInset)
            let maxWidth = notch.screenFrame.width - 2 * screenMargin
            let switcherMin = reservesModeSwitcher ? notch.size.width + 2 * (Self.modeSwitcherWidth + 26) : 0
            let height = notch.size.height + expandedContentHeight + Tuning.shared.expandedBottomInset
            return CGSize(width: min(max(wanted, switcherMin), maxWidth), height: height)
        }
    }

    /// Width of one cell: the standard one, or smaller when all modules of the 功能 tab would not fit the screen.
    var effectiveCellWidth: CGFloat {
        let total = expandedCells.reduce(0, +)
        guard total > 0, expandedCells.count > 1 else { return cellWidth }
        let gaps = CGFloat(expandedCells.count - 1) * moduleGap
        let available = notch.screenFrame.width - 2 * screenMargin - 2 * contentInset - gaps
        return min(cellWidth, available / CGFloat(total))
    }

    func swelledSize(_ size: CGSize, reduceMotion: Bool) -> CGSize {
        let scale = reduceMotion ? Self.reducedSwellScale : Self.swellScale
        return CGSize(width: size.width * scale.width, height: size.height * scale.height)
    }

    /// Body rect in global screen coordinates: top-centred on the screen.
    func bodyRect(for state: CapsuleState) -> CGRect {
        let size = bodySize(for: state)
        let frame = notch.screenFrame
        return CGRect(x: frame.midX - size.width / 2, y: frame.maxY - notch.floatGap - size.height, width: size.width, height: size.height)
    }

    /// Hover trigger zone: a few points larger than the body, reaching the very top edge.
    func triggerRect(for state: CapsuleState) -> CGRect {
        if state == .idle, virtualContent {
            var rect = bodyRect(for: .idle).insetBy(dx: -NotchGeometry.triggerMargin, dy: -NotchGeometry.triggerMargin)
            rect.size.height += NotchGeometry.triggerMargin + notch.floatGap
            return rect
        }
        if state == .idle { return notch.triggerRect }
        var rect = bodyRect(for: state).insetBy(dx: -NotchGeometry.triggerMargin, dy: -NotchGeometry.triggerMargin)
        rect.size.height += NotchGeometry.triggerMargin + notch.floatGap
        return rect
    }

    /// Region where the panel must accept mouse events for a state: the body including its hover states
    /// (swollen + song-info for compact), with the usual few points of tolerance. Everywhere else the panel
    /// is click-through.
    func hitRect(for state: CapsuleState) -> CGRect {
        switch state {
        case .idle, .expanded:
            return triggerRect(for: state)
        case .compact:
            let body = bodyRect(for: .compact)
            let swollen = swelledSize(body.size, reduceMotion: false)
            let height = swollen.height + Self.compactInfoHeight + 2 * NotchGeometry.triggerMargin
            let width = swollen.width + 2 * NotchGeometry.triggerMargin
            return CGRect(x: body.midX - width / 2, y: body.maxY - height, width: width, height: height)
        }
    }

    /// The system-event card (charging, low battery, a Bluetooth device): on a virtual notch a 56 pt row from the screen's top edge;
    /// beside a physical notch a square slot each side of it (the notch's height plus the text row), with the text under the notch.
    static let toastContentHeight: CGFloat = 56
    static let toastNotchTextHeight: CGFloat = 44
    static let virtualToastWidth: CGFloat = 340

    var toastSize: CGSize {
        if notch.isVirtual { return CGSize(width: Self.virtualToastWidth, height: Self.toastContentHeight) }
        let side = notch.size.height + Self.toastNotchTextHeight
        return CGSize(width: notch.size.width + 2 * side, height: side)
    }

    /// The capsule widened into the volume / brightness HUD: the notch plus a wing (`NotchHUDController.wingWidth`) each side.
    var hudSize: CGSize { CGSize(width: notch.size.width + 2 * Self.hudWing, height: notch.size.height) }

    /// The panel frame the HUD needs (swollen, with the usual room around it), clamped to the screen.
    func hudPanelFrame() -> CGRect { panelFrame(forBody: swelledSize(hudSize, reduceMotion: false)) }

    func toastPanelFrame() -> CGRect { panelFrame(forBody: toastSize) }

    /// A top-centred body of `size` with the usual room around it, clamped to the screen.
    private func panelFrame(forBody size: CGSize) -> CGRect {
        let frame = notch.screenFrame
        let dx = NotchGeometry.earRadius + Self.panelPadding.width
        let rect = CGRect(x: frame.midX - size.width / 2 - dx, y: frame.maxY - size.height - Self.panelPadding.height,
                          width: size.width + 2 * dx, height: size.height + Self.panelPadding.height + notch.floatGap)
        return rect.intersection(frame)
    }

    /// Panel frame for a state: body + ears + room for swell/shadow, clamped to the screen.
    func panelFrame(for state: CapsuleState) -> CGRect {
        var body = bodyRect(for: state)
        if state == .compact {
            // Room for the hover states: swollen capsule plus the song / artist area.
            let swollen = swelledSize(body.size, reduceMotion: false)
            body = CGRect(x: body.midX - swollen.width / 2, y: body.maxY - swollen.height - Self.compactInfoHeight,
                          width: swollen.width, height: swollen.height + Self.compactInfoHeight)
        }
        let dx = NotchGeometry.earRadius + Self.panelPadding.width
        var rect = CGRect(x: body.minX - dx, y: body.minY - Self.panelPadding.height,
                          width: body.width + 2 * dx, height: body.height + Self.panelPadding.height + notch.floatGap)
        if state == .compact, !secondaries.isEmpty {
            // Room for the secondary islands (kept symmetric around the notch, like the body).
            let pad: CGFloat = 24
            let mid = notch.screenFrame.midX
            let half = secondaries.reduce(rect.width / 2) {
                max($0, abs($1.rect.minX - mid) + pad, abs($1.rect.maxX - mid) + pad)
            }
            let low = min(rect.minY, (secondaries.map(\.rect.minY).min() ?? rect.minY) - pad)
            rect = CGRect(x: mid - half, y: low, width: 2 * half, height: rect.maxY - low)
        }
        rect = rect.intersection(notch.screenFrame)
        return rect
    }
}
