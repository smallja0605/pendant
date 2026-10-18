import Foundation

/// The three capsule forms (requirements 3). One view morphs between them.
enum CapsuleState: Equatable, Sendable {
    case idle      // A. same size as the physical notch
    case compact   // B. wings on both sides, live info
    case expanded  // C. full panel
}

/// Hover-to-expand setting (3.3 / 7.1).
enum HoverExpandMode: String, CaseIterable, Sendable {
    case off
    case compactOnly
    case always
}

enum ExpandPolicy {
    /// Whether dwelling on the notch for the hover delay should open the capsule.
    static func shouldAutoExpand(mode: HoverExpandMode, state: CapsuleState) -> Bool {
        switch (mode, state) {
        case (.off, _), (_, .expanded): false
        case (.compactOnly, .idle): false
        case (.compactOnly, .compact), (.always, .idle), (.always, .compact): true
        }
    }

    /// Where the capsule settles after collapsing.
    static func restingState(hasActivity: Bool) -> CapsuleState {
        hasActivity ? .compact : .idle
    }
}
