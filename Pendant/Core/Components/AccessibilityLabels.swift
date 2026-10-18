import SwiftUI

/// VoiceOver names for the icon-only buttons (the symbol name alone would be read out).
enum SymbolLabel {
    static func text(for symbol: String) -> String {
        switch symbol {
        case "play.fill": "播放"
        case "pause.fill": "暫停"
        case "backward.fill": "上一首"
        case "forward.fill": "下一首"
        case "airplayaudio": "AirPlay 輸出裝置"
        case "arrow.counterclockwise": "重設"
        case _ where symbol.hasPrefix("speaker"): "音量"
        default: ""
        }
    }
}

extension View {
    /// Makes a gesture-driven view a proper button for VoiceOver and the keyboard-less accessibility actions.
    func accessibilityButton(_ label: String, selected: Bool = false) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
