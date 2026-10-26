import AppKit
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

/// The system-event card's timing: the capsule itself widens and grows downward into the card (charging, low battery, a Bluetooth
/// device) and folds back. This controller only decides when; the capsule model holds the state and `CapsuleView` draws it.
@MainActor
final class NotchToastController {
    private let model: CapsuleModel
    private var hideTask: Task<Void, Never>?
    /// True while the card is out: the capsule's own contents tuck away, and come back when this turns false.
    var onVisibilityChange: ((Bool) -> Void)?
    /// Asks the window to make its panel as big as the card needs (before it grows) or small again (after it has folded).
    var updatePanel: (() -> Void)?

    init(model: CapsuleModel) { self.model = model }

    var isShowing: Bool { model.toastWanted }

    /// `seconds` = nil: until `fold()` / `hideNow()`.
    func show(_ toast: SystemToast, seconds: Double?) {
        model.presentToast(toast)
        updatePanel?() // room first, then the animation
        hideTask?.cancel()
        if !model.toastVisible {
            onVisibilityChange?(true)
            model.setToastVisible(true)
        }
        guard let seconds else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.fold()
        }
    }

    /// Folds the card back into the capsule.
    func fold() {
        guard model.toastVisible else { return }
        hideTask?.cancel()
        model.setToastVisible(false)
        onVisibilityChange?(false)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            model.clearToast()
            updatePanel?()
        }
    }

    func hideNow() {
        hideTask?.cancel()
        let wasOut = model.toastVisible
        model.resetToast()
        if wasOut { onVisibilityChange?(false) }
        updatePanel?()
    }
}

/// The card's row in three parts: a square slot on the left with the ring, the title and its line centred in the middle, and a
/// square slot of the same size on the right with the value (or the device symbol).
struct ToastContent: View {
    let toast: SystemToast

    var body: some View {
        let slot = CapsuleLayout.toastContentHeight
        ZStack {
            VStack(spacing: 1) {
                Text(loc(toast.title)).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(loc(toast.subtitle)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
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
        let side = notchHeight + CapsuleLayout.toastNotchTextHeight
        HStack(spacing: 0) {
            ToastRing(progress: toast.progress, tint: toast.tint, symbol: toast.ringSymbol, lineWidth: 4.5, symbolSize: 17)
                .frame(width: side * 0.7, height: side * 0.7)
                .frame(width: side, height: side)
            HStack(spacing: 6) {
                Text(loc(toast.title)).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Text(loc(toast.subtitle)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: CapsuleLayout.toastNotchTextHeight)
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
