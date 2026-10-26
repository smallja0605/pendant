import AppKit

/// The two buttons of 設定 › 關於 › 設定檔: save every setting to a file, load a file (and restart to use it).
@MainActor
enum SettingsTransferPanel {
    static func exportToFile() {
        let panel = NSSavePanel()
        panel.title = tr("匯出設定")
        panel.nameFieldStringValue = tr("Pendant 設定.json")
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            try SettingsTransfer.export(from: .standard, appVersion: version).write(to: url, options: .atomic)
        } catch {
            show(tr("無法匯出設定"), tr("檔案沒有寫入，請換一個位置再試。"))
        }
    }

    static func importFromFile() {
        let panel = NSOpenPanel()
        panel.title = tr("匯入設定")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        alert.messageText = tr("匯入這份設定？")
        alert.informativeText = tr("目前的設定會被檔案裡有的項目取代（檔案裡沒有的、其他系統才有的項目會略過），Pendant 會重新啟動。")
        alert.addButton(withTitle: tr("匯入並重新啟動"))
        alert.addButton(withTitle: tr("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let data = try Data(contentsOf: url)
            try SettingsTransfer.apply(data, to: .standard)
            UserDefaults.standard.synchronize()
            restart()
        } catch let error as SettingsTransfer.TransferError {
            show(tr("無法匯入設定"), error.message)
        } catch {
            show(tr("無法匯入設定"), SettingsTransfer.TransferError.unreadable.message)
        }
    }

    private static func restart() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private static func show(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
