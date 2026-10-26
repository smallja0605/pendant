import Foundation

extension AppSettings {
    enum ScreenChoice: String, CaseIterable, Sendable { case main, underCursor, all }
    enum ShelfAutoClear: String, CaseIterable, Sendable { case never, onLogout, onReboot, afterDays }

    /// Island settings as the pure planner wants them (the smart-avoid bounds are filled in by the window controller).
    var islandSettings: IslandSettings {
        IslandSettings(
            leftEnabled: islandLeftEnabled, rightEnabled: islandRightEnabled, prioritySide: islandPrioritySide,
            gap: islandGap, maxSpanFraction: islandMaxSpanPercent / 100,
            leftOffset: islandLeftOffset, rightOffset: islandRightOffset,
            maxWidth: islandMaxWidth, sinking: islandSinking
        )
    }
}
