import SwiftUI

/// All animation parameters live here so they can be tuned in one place (values come from `Tuning`).
enum AnimationTokens {
    static var expand: Animation {
        .spring(response: Tuning.shared.expandResponse, dampingFraction: Tuning.shared.expandDamping)
    }

    static var collapse: Animation {
        .spring(response: Tuning.shared.collapseResponse, dampingFraction: Tuning.shared.collapseDamping)
    }

    /// Notch hover "swell" (3.4): short, slightly bouncy.
    static var hoverSwell: Animation {
        .spring(response: Tuning.shared.swellResponse, dampingFraction: Tuning.shared.swellDamping)
    }

    /// Swell / peek shrinking back: nearly critically damped, so the capsule never dips below its resting size.
    static var unswell: Animation {
        .spring(response: Tuning.shared.unswellResponse, dampingFraction: Tuning.shared.unswellDamping)
    }

    /// Split / merge / promote of the secondary islands (3.5.4).
    static var island: Animation {
        .spring(response: Tuning.shared.islandResponse, dampingFraction: Tuning.shared.islandDamping)
    }

    static func island(reduceMotion: Bool) -> Animation { reduceMotion ? reduced : island }

    /// Used when Reduce Motion is enabled.
    static let reduced = Animation.easeInOut(duration: 0.15)

    static func expand(reduceMotion: Bool) -> Animation { reduceMotion ? reduced : expand }
    static func collapse(reduceMotion: Bool) -> Animation { reduceMotion ? reduced : collapse }
}
