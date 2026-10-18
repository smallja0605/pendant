import SwiftUI

/// The shared header line of the open capsule's modules: the calendar's month label sits in the middle of its date strip, and
/// the reminders title and the timer's mode picker are centred on that same line, so the three read as one row.
enum ModuleHeader {
    /// Distance from the top of a module to the centre of the header line (the calendar's `8 pt + half the strip`).
    @MainActor static var centerY: CGFloat { 8 + Tuning.shared.calStripHeight / 2 }

    /// Top padding that puts a header row of `rowHeight` on that line.
    @MainActor static func topPadding(rowHeight: CGFloat) -> CGFloat { max(centerY - rowHeight / 2, 0) }
}
