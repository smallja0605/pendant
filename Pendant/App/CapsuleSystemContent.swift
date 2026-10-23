import SwiftUI

/// What the capsule shows while it has widened into the volume / brightness HUD or a system-event card (charging, low battery, a
/// Bluetooth device). Both rows have their final layout and are revealed like the song line while the capsule's own shape grows;
/// the capsule clips them, so nothing shows outside it.
struct CapsuleSystemContent: View {
    let model: CapsuleModel
    let notchSize: CGSize

    var body: some View {
        if let layout = model.layout {
            let swell = model.levelHUDSwelled
            HUDRowContent(hud: model.levelHUD, notchWidth: notchSize.width, height: notchSize.height)
                .frame(width: layout.hudSize.width, height: notchSize.height * (swell ? Tuning.shared.swellHeight : 1))
                .scaleEffect(swell ? Tuning.shared.swellWidth : 1)
                .modifier(RevealEffect(isVisible: model.levelHUDVisible, delay: 0.1, blurOnExit: true))
            let card = layout.toastSize
            Group {
                if layout.notch.isVirtual {
                    ToastContent(toast: model.toast)
                } else {
                    ToastNotchContent(toast: model.toast, notchHeight: notchSize.height)
                }
            }
            .frame(width: card.width, height: card.height, alignment: .top)
            .allowsHitTesting(false)
            .modifier(RevealEffect(isVisible: model.toastVisible, delay: 0.1, blurOnExit: true))
        }
    }
}
