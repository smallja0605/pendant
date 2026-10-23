import Foundation

/// Trackpad haptic patterns (maps to `NSHapticFeedbackManager.FeedbackPattern`).
enum HapticPattern: Sendable {
    case alignment, generic, levelChange
}

/// Every situation in requirements 5.1 that produces feedback.
enum HapticEvent: String, CaseIterable, Sendable {
    // No haptics for hovering (the notch, the controls, the tabs): they were removed on purpose.
    /// The capsule starts opening (hover dwell or click).
    case expandStarted
    /// Collapse animation finished.
    case stateSettled
    /// Progress / volume slider crossed a step unit.
    case dragStep
    /// One unit crossed while scrubbing: calendar day, timer digit (the same event, so they feel identical).
    case dateChanged
    /// Timer finished (played twice).
    case timerFinished
    /// A swipe changed the track (two-finger horizontal gesture on the media page).
    case swipeSwitch
    /// The moment a swipe changes the track: one big haptic (the strongest pattern), nothing else while the swipe travels.
    case swipeCommit
    var pattern: HapticPattern {
        switch self {
        case .dragStep, .dateChanged: .alignment
        case .swipeSwitch: .generic
        case .expandStarted, .stateSettled, .timerFinished, .swipeCommit: .levelChange
        }
    }

    /// Minimum spacing between two firings of the same event (5.2 / 3.4 rule 5).
    var minimumInterval: TimeInterval {
        switch self {
        case .expandStarted, .stateSettled: 0.10
        case .dragStep, .dateChanged: 0.04
        case .swipeSwitch: 0.12
        case .timerFinished, .swipeCommit: 0
        }
    }

    /// Extra repeats after the first firing, with the delay between them.
    var repeats: (times: Int, delay: TimeInterval) {
        self == .timerFinished ? (1, 0.18) : (0, 0)
    }
}
