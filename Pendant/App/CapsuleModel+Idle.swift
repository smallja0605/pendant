import Foundation

extension CapsuleModel {
    /// A virtual notch with nothing live, at rest: drawn as a thin bar or not at all (the settings' 閒置時); `off` otherwise.
    /// Hovering it (the swell) brings the small capsule back.
    var idleConcealment: VirtualIdleHide {
        guard layout?.virtualContent == true, state == .idle, !isSwelled, !hudShowing else { return .off }
        return AppSettings.shared.virtualIdleHide
    }

    /// Fully hidden and the pointer is not allowed to bring it back (the setting is off): no hover, no click at the notch's place.
    var idleTriggerBlocked: Bool {
        layout?.virtualContent == true && state == .idle && AppSettings.shared.virtualIdleHide == .hidden
            && !AppSettings.shared.virtualIdleHover
    }
}
