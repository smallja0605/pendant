import AppKit
import ServiceManagement

/// Uninstall (requirements 4.11): the login item, the app's own Library folders, its settings, then the app itself to
/// the Trash. Only whitelisted paths are deleted; each one is checked with `UninstallPlan.isSafe` first.
@MainActor
enum UninstallService {
    /// Set while uninstalling so the quit handlers do not write anything back.
    private(set) static var isUninstalling = false

    /// Asks for confirmation (with the "keep my notes" choice) and, if confirmed, uninstalls and quits.
    static func confirmAndRun() {
        let alert = NSAlert()
        alert.messageText = tr("解除安裝 Pendant?")
        alert.informativeText = """
        將移除:登入時啟動的設定、Application Support 裡的資料(筆記、檔案抽屜暫存)、偏好設定與快取,\
        最後把 App 移到垃圾桶並結束。
        """
        alert.alertStyle = .warning
        let keep = NSButton(checkboxWithTitle: tr("同時保留我的筆記"), target: nil, action: nil)
        keep.state = .on
        alert.accessoryView = keep
        alert.addButton(withTitle: tr("解除安裝"))
        alert.addButton(withTitle: tr("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        run(keepNotes: keep.state == .on)
    }

    static func run(keepNotes: Bool) {
        isUninstalling = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bundleID = Bundle.main.bundleIdentifier ?? "com.smallja.pendant"
        let temp = FileManager.default.temporaryDirectory
        try? SMAppService.mainApp.unregister()

        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(UninstallPlan.supportFolderName)
        let children = (try? FileManager.default.contentsOfDirectory(atPath: supportURL.path)) ?? []
        let targets = UninstallPlan.targets(home: home, bundleID: bundleID, keepNotes: keepNotes, supportChildren: children, temp: temp)
        for target in targets where UninstallPlan.isSafe(target, home: home, bundleID: bundleID, temp: temp) {
            try? FileManager.default.removeItem(at: target)
        }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
