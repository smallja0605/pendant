import SwiftUI

/// Content of the output popover (an `NSPopover` below the AirPlay icon, with the system arrow):
/// Apple Music's AirPlay devices (HomePod, speakers, Apple TV) plus the system's output devices.
struct OutputsPopover: View {
    let controller: MediaController
    /// Reports the height the list wants so the popover can resize (it animates natively).
    var onHeightChange: (CGFloat) -> Void = { _ in }
    @State private var outputs = MediaController.Outputs()
    @State private var loaded = false

    static let width: CGFloat = 290
    static let maxHeight: CGFloat = 260

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                if !outputs.airPlay.isEmpty {
                    ForEach(outputs.airPlay) { target in
                        OutputRow(
                            symbol: target.symbolName, name: target.name, isSelected: target.isSelected, checkbox: true,
                            volume: target.isSelected ? target.volume : nil,
                            onVolume: { controller.setAirPlayVolume(target.index, percent: $0) },
                            action: { toggleAirPlay(target) }
                        )
                    }
                }
                if loaded, outputs.airPlay.isEmpty {
                    Text("找不到 AirPlay 裝置").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).padding(8)
                }
            }
            .padding(8)
        }
        .frame(width: Self.width, height: min(contentHeight, Self.maxHeight))
        .task { await load() }
    }

    /// A ScrollView has no intrinsic height, so the height is derived from the rows (capped; it scrolls beyond).
    private var contentHeight: CGFloat {
        max(CGFloat(outputs.airPlay.count) * 28 + 18, 64)
    }

    /// Checking / unchecking adds / removes the device; at least one stays selected.
    private func toggleAirPlay(_ target: AirPlayTarget) {
        var targets = outputs.airPlay
        guard let position = targets.firstIndex(where: { $0.index == target.index }) else { return }
        let wasSelected = targets[position].isSelected
        if wasSelected, targets.filter(\.isSelected).count == 1 { return }
        targets[position].isSelected.toggle()
        outputs.airPlay = targets // optimistic; the reload confirms
        controller.setAirPlayTargets(targets.filter(\.isSelected).map(\.index))
        reload(after: 0.8)
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }

    private func load() async {
        outputs = await controller.loadOutputs()
        loaded = true
        onHeightChange(min(contentHeight, Self.maxHeight))
    }

    private func reload(after delay: Double) {
        Task {
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            await load()
        }
    }
}

private struct OutputRow: View {
    let symbol: String
    let name: String
    let isSelected: Bool
    var checkbox = false
    var volume: Int?
    var onVolume: (Int) -> Void = { _ in }
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Name area and checkbox toggle; the volume slider in between is not part of the button.
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 18)
                    Text(name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let volume {
                AirPlayVolumeSlider(initial: volume, onChange: onVolume)
            }
            Button(action: action) {
                if checkbox {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.4))
                } else if isSelected {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                }
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.78))
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hovering ? 0.12 : 0)))
        .contentShape(Rectangle())
        .onActiveHover { hovering = $0 != nil }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Small volume slider for one AirPlay device; one haptic per 5 %, Apple events throttled.
private struct AirPlayVolumeSlider: View {
    let initial: Int
    let onChange: (Int) -> Void
    @State private var value: Double
    @State private var tracker = StepTracker(unit: 0.05)
    @State private var lastSent = Date.distantPast

    init(initial: Int, onChange: @escaping (Int) -> Void) {
        self.initial = initial
        self.onChange = onChange
        _value = State(initialValue: Double(initial) / 100)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white).frame(width: max(width * value, 0))
            }
            .frame(height: 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { update(min(max($0.location.x / max(width, 1), 0), 1), final: false) }
                    .onEnded { update(min(max($0.location.x / max(width, 1), 0), 1), final: true) }
            )
        }
        .frame(width: 60, height: 22)
    }

    private func update(_ newValue: Double, final: Bool) {
        value = newValue
        if tracker.crossedBoundary(at: newValue) { HapticService.shared.play(.dragStep) }
        if final || Date().timeIntervalSince(lastSent) > 0.08 {
            lastSent = Date()
            onChange(Int((newValue * 100).rounded()))
        }
        if final { tracker.reset() }
    }
}

extension AudioOutputDevice.Transport {
    var symbolName: String {
        switch self {
        case .builtIn: "laptopcomputer"
        case .bluetooth: "headphones"
        case .airPlay: "airplayaudio"
        case .usb: "cable.connector"
        case .display: "display"
        case .other: "speaker.wave.2.fill"
        }
    }
}
