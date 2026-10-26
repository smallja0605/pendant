import Foundation

extension AppSettings {
    enum ScreenChoice: String, CaseIterable, Sendable { case main, underCursor, all }
    enum ShelfAutoClear: String, CaseIterable, Sendable { case never, onLogout, onReboot, afterDays }
}
