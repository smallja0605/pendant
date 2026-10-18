import AppKit
import Observation
import SwiftUI

/// A system event shown as a card hanging from the notch (charging, low battery, a Bluetooth device): a ring on the left (a
/// charge level, optionally with a symbol in it), a title and a line under it, and a value or a device symbol on the right.
struct SystemToast: Equatable {
    enum Tint: Equatable { case green, red, blue }
    enum Trailing: Equatable {
        case value(String)
        case symbol(String)
    }

    var title: String
    var subtitle: String
    var progress: Double
    var tint: Tint
    var ringSymbol: String?
    var trailing: Trailing
    /// Stays until it is dismissed (the low-battery warning); otherwise it folds after the configured time.
    var persistent = false
}

@MainActor
@Observable
final class ToastModel {
    var toast = SystemToast(title: "", subtitle: "", progress: 0, tint: .green, ringSymbol: nil, trailing: .value(""))
    var visible = false
    /// Width of what is under the card (the capsule, or the notch): the card grows from it and folds back to it.
    var restWidth: CGFloat = 0
    /// A virtual notch: the card's row starts at the very top (menu bar included); with a physical notch it sits below it.
    var virtual = false
}

/// The system-event card: its own click-through panel above the capsule (like the volume HUD), so the capsule's state is untouched.
@MainActor
final class NotchToastController {
    /// Width of the card: narrower on a virtual notch (nothing to fit around, the content uses the menu bar's space too).
    static func cardWidth(virtual: Bool, notchWidth: CGFloat = 0, notchHeight: CGFloat = 0) -> CGFloat {
        virtual ? 340 : notchWidth + 2 * (notchHeight + notchTextHeight)
    }
    static let contentHeight: CGFloat = 56
    /// Beside a physical notch the ring and value sit in the menu-bar row next to it; only the text line hangs below.
    static let notchTextHeight: CGFloat = 44

    static func cardHeight(virtual: Bool, notchHeight: CGFloat) -> CGFloat {
        virtual ? contentHeight : notchHeight + notchTextHeight
    }

    private let model = ToastModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var appearTask: Task<Void, Never>?
    /// True while the card is out: the capsule below tucks its contents away, and brings them back when this turns false.
    var onVisibilityChange: ((Bool) -> Void)?

    var isShowing: Bool { model.visible }

    /// `notch` is the notch's frame in screen coordinates; the card hangs from it. `seconds` = nil: until `hideNow()`.
    func show(_ toast: SystemToast, notch: CGRect, virtual: Bool, restWidth: CGFloat, seconds: Double?) {
        model.toast = toast
        model.virtual = virtual
        let firstTime = panel == nil
        let panel = ensurePanel(notch: notch)
        panel.orderFrontRegardless()
        hideTask?.cancel()
        if !model.visible {
            model.restWidth = max(restWidth, notch.width)
            if firstTime {
                // Let the freshly created view draw once, or there is nothing to animate from.
                appearTask?.cancel()
                appearTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(60))
                    guard !Task.isCancelled, let self, !model.visible else { return }
                    onVisibilityChange?(true)
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.76)) { model.visible = true }
                }
            } else {
                onVisibilityChange?(true)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.76)) { model.visible = true }
            }
        }
        guard let seconds else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.fold()
        }
    }

    /// Folds the card back into the notch.
    func fold() {
        guard model.visible else { return }
        hideTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { model.visible = false }
        onVisibilityChange?(false)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(480))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    func hideNow() {
        appearTask?.cancel()
        hideTask?.cancel()
        if model.visible { onVisibilityChange?(false) }
        model.visible = false
        panel?.orderOut(nil)
    }

    private func ensurePanel(notch: CGRect) -> NSPanel {
        let ear = NotchGeometry.earRadius
        let width = Self.cardWidth(virtual: model.virtual, notchWidth: notch.width, notchHeight: notch.height) + 2 * ear + 64
        let height = Self.cardHeight(virtual: model.virtual, notchHeight: notch.height) + 16
        let frame = CGRect(x: notch.midX - width / 2, y: notch.maxY - height, width: width, height: height)
        if let panel {
            panel.setFrame(frame, display: false)
            if let hosting = panel.contentView?.subviews.first as? NSHostingView<NotchToastView> {
                hosting.rootView = NotchToastView(model: model, notchWidth: notch.width, notchHeight: notch.height)
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
        let hosting = NSHostingView(rootView: NotchToastView(model: model, notchWidth: notch.width, notchHeight: notch.height))
        // A plain subview of a container (see the HUD panel): as the content view the hosting view crashed the app.
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

struct NotchToastView: View {
    let model: ToastModel
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    var body: some View {
        let ear = NotchGeometry.earRadius
        let full = NotchToastController.cardWidth(virtual: model.virtual, notchWidth: notchWidth, notchHeight: notchHeight)
        let height = NotchToastController.cardHeight(virtual: model.virtual, notchHeight: notchHeight)
        let width = model.visible ? full : max(model.restWidth, notchWidth)
        let rowHeight = model.visible ? height : notchHeight
        let shape = NotchShape(bottomRadius: model.visible ? 28 : 12)
        ZStack(alignment: .top) {
            shape.fill(Color.black)
                .opacity(model.visible ? 1 : 0)
                .animation(model.visible ? nil : .easeOut(duration: 0.2).delay(0.05), value: model.visible)
            Group {
                if model.virtual {
                    ToastContent(toast: model.toast)
                } else {
                    ToastNotchContent(toast: model.toast, notchHeight: notchHeight)
                }
            }
            .frame(width: full, height: height, alignment: .top)
                .modifier(RevealEffect(isVisible: model.visible, delay: 0.1, blurOnExit: true))
        }
        .frame(width: width + 2 * ear, height: rowHeight, alignment: .top)
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityHidden(true)
    }
}

/// The card's row in three parts: a square slot on the left with the ring, the title and its line centred in the middle, and a
/// square slot of the same size on the right with the value (or the device symbol).
struct ToastContent: View {
    let toast: SystemToast

    var body: some View {
        let slot = NotchToastController.contentHeight
        ZStack {
            VStack(spacing: 1) {
                Text(toast.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(toast.subtitle).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            .multilineTextAlignment(.center)
            HStack(spacing: 0) {
                ToastRing(progress: toast.progress, tint: toast.tint, symbol: toast.ringSymbol)
                    .frame(width: slot * 0.68, height: slot * 0.68)
                    .frame(width: slot, height: slot)
                Spacer(minLength: 0)
                Group {
                    switch toast.trailing {
                    case let .value(text):
                        Text(text).font(.system(size: 21, weight: .regular, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    case let .symbol(name):
                        ToastDeviceBadge(symbol: name, tint: toast.tint)
                    }
                }
                .frame(width: slot + 16, height: slot)
            }
        }
    }
}

/// For a physical notch: a square slot on each side spans the whole card height (menu-bar row plus the part that hangs below)
/// with the ring on the left and the value on the right; in the middle the notch on top and the title with its line under it.
struct ToastNotchContent: View {
    let toast: SystemToast
    let notchHeight: CGFloat

    var body: some View {
        let side = notchHeight + NotchToastController.notchTextHeight
        HStack(spacing: 0) {
            ToastRing(progress: toast.progress, tint: toast.tint, symbol: toast.ringSymbol, lineWidth: 4.5, symbolSize: 17)
                .frame(width: side * 0.7, height: side * 0.7)
                .frame(width: side, height: side)
            HStack(spacing: 6) {
                Text(toast.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Text(toast.subtitle).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: NotchToastController.notchTextHeight)
            .frame(maxHeight: .infinity, alignment: .bottom)
            Group {
                switch toast.trailing {
                case let .value(text):
                    Text(text).font(.system(size: 22, weight: .regular, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                case let .symbol(name):
                    ToastDeviceBadge(symbol: name, tint: toast.tint)
                }
            }
            .frame(width: side, height: side)
        }
    }
}

extension SystemToast.Tint {
    var color: Color {
        switch self {
        case .green: Color(red: 0.19, green: 0.84, blue: 0.45)
        case .red: Color(red: 1, green: 0.27, blue: 0.23)
        case .blue: Color(red: 0.25, green: 0.65, blue: 1)
        }
    }
}

/// A ring that fills with the charge; a symbol in the middle (a bolt while charging, the Bluetooth mark for a device).
struct ToastRing: View {
    let progress: Double
    let tint: SystemToast.Tint
    let symbol: String?
    var lineWidth: CGFloat = 4
    var symbolSize: CGFloat = 15

    var body: some View {
        ZStack {
            Circle().stroke(tint.color.opacity(0.25), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(min(progress, 1), 0.02))
                .stroke(tint.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if symbol == "bluetooth" {
                BluetoothMark().stroke(.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 11, height: 17)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: symbolSize, weight: .bold)).foregroundStyle(.white)
            }
        }
        .animation(.easeOut(duration: 0.3), value: progress)
    }
}

/// The device's kind (headphones, mouse…) in a softly glowing circle.
struct ToastDeviceBadge: View {
    let symbol: String
    let tint: SystemToast.Tint

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(tint.color)
            .frame(width: 44, height: 44)
            .background(Circle().fill(tint.color.opacity(0.18)))
            .overlay(Circle().stroke(tint.color.opacity(0.55), lineWidth: 1.5))
    }
}

/// The Bluetooth rune (SF Symbols has no mark for it).
struct BluetoothMark: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: rect.minX + fx * rect.width, y: rect.minY + fy * rect.height) }
        var path = Path()
        path.move(to: point(0.05, 0.28))
        path.addLine(to: point(0.95, 0.72))
        path.addLine(to: point(0.5, 1))
        path.addLine(to: point(0.5, 0))
        path.addLine(to: point(0.95, 0.28))
        path.addLine(to: point(0.05, 0.72))
        return path
    }
}
