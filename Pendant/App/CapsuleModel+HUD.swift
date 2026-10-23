import SwiftUI

extension CapsuleModel {
    func presentLevelHUD(_ hud: LevelHUD) {
        levelHUD = hud
        levelHUDWanted = true
    }

    func setLevelHUDVisible(_ visible: Bool) {
        let spring = Animation.spring(response: visible ? 0.34 : 0.36, dampingFraction: visible ? 0.78 : 0.85)
        withAnimation(reduceMotion ? AnimationTokens.reduced : spring) {
            levelHUDVisible = visible
            if !visible { levelHUDSwelled = false }
        }
    }

    func setLevelHUDSwelled(_ swelled: Bool) {
        guard swelled != levelHUDSwelled else { return }
        withAnimation(reduceMotion ? AnimationTokens.reduced : .spring(response: 0.3, dampingFraction: 0.55)) { levelHUDSwelled = swelled }
    }

    func clearLevelHUD() { levelHUDWanted = false }

    /// Gone at once (no animation): a system card takes over, or the window shuts down.
    func resetLevelHUD() {
        levelHUDVisible = false
        levelHUDSwelled = false
        levelHUDWanted = false
    }

    // MARK: System-event card

    func presentToast(_ card: SystemToast) {
        toast = card
        toastWanted = true
    }

    func setToastVisible(_ visible: Bool) {
        let spring = Animation.spring(response: visible ? 0.4 : 0.38, dampingFraction: visible ? 0.76 : 0.86)
        withAnimation(reduceMotion ? AnimationTokens.reduced : spring) { toastVisible = visible }
    }

    func clearToast() { toastWanted = false }

    func resetToast() {
        toastVisible = false
        toastWanted = false
    }
}
