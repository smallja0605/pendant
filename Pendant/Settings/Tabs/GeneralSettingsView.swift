import SwiftUI

/// 7.1 General.
struct GeneralSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @State private var haptics = HapticService.shared.isEnabled

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section("啟動") {
                Toggle("登入時啟動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        loginError = LoginItem.set(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
                    .settingNote(loginError.map { "無法變更:\($0)" } ?? (LoginItem.needsApproval ? "請在「系統設定 → 一般 → 登入項目」中允許 Pendant。" : nil))
            }
            Section("顯示") {
                Toggle("在選單列顯示圖示", isOn: $settings.showMenuBarIcon)
                    .settingNote(settings.showMenuBarIcon ? nil : "圖示隱藏後，在瀏海上按右鍵即可開啟設定或結束程式。")
                Toggle("全螢幕時顯示", isOn: $settings.showInFullscreen)
                Picker("顯示螢幕", selection: $settings.screenChoice) {
                    Text("主螢幕").tag(AppSettings.ScreenChoice.main)
                    Text("游標所在螢幕").tag(AppSettings.ScreenChoice.underCursor)
                    Text("所有螢幕同時顯示").tag(AppSettings.ScreenChoice.all)
                }
            }
            Section("展開") {
                Picker("懸停展開", selection: $settings.hoverExpandMode) {
                    Text("關閉").tag(HoverExpandMode.off)
                    Text("僅小膠囊顯示時").tag(HoverExpandMode.compactOnly)
                    Text("永遠啟用").tag(HoverExpandMode.always)
                }
                LabeledContent("懸停延遲") {
                    HStack {
                        HapticSlider(value: $settings.hoverDelay, in: 0...1.5, step: 0.05)
                        Text(String(format: "%.2f s", settings.hoverDelay)).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                .disabled(settings.hoverExpandMode == .off)
                LabeledContent("離開後收合延遲") {
                    HStack {
                        HapticSlider(value: $settings.collapseDelay, in: 0.1...1.5, step: 0.05)
                        Text(String(format: "%.2f s", settings.collapseDelay)).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                HotkeyRow(settings: settings)
            }
            Section("音樂與回饋") {
                Picker("音樂來源", selection: $settings.mediaSourcePreference) {
                    Text("自動").tag(MediaSourcePreference.auto)
                    Text("Apple Music").tag(MediaSourcePreference.appleMusic)
                    Text("Spotify").tag(MediaSourcePreference.spotify)
                }
                Toggle("觸覺回饋", isOn: $haptics)
                    .onChange(of: haptics) { _, enabled in HapticService.shared.isEnabled = enabled }
                    .settingNote("關閉後所有震動都會停用，瀏海膨脹動畫不受影響。")
            }
            Section("語言") {
                Picker("語言", selection: $settings.languageOverride) {
                    Text("跟隨系統").tag("system")
                    Text("繁體中文").tag("zh-Hant")
                    Text("English").tag("en")
                }
                .onChange(of: settings.languageOverride) { _, value in applyLanguage(value) }
                .settingNote("重新啟動後生效。")
            }
            #if DEBUG
            HapticPlayground()
            #endif
        }
        .formStyle(.grouped)
    }

    private func applyLanguage(_ value: String) {
        if value == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([value], forKey: "AppleLanguages")
        }
    }
}

/// Global shortcut switch plus a recorder: click it, press the new combination.
private struct HotkeyRow: View {
    @Bindable var settings: AppSettings
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Toggle("全域快捷鍵", isOn: $settings.hotkeyEnabled)
        LabeledContent("快捷鍵") {
            Button(recording ? "請按下新的組合⋯" : shortcutText) {
                if recording { stopRecording() } else { startRecording() }
            }
            .disabled(!settings.hotkeyEnabled)
        }
    }

    private var shortcutText: String {
        GlobalHotkey.displayString(keyCode: settings.hotkeyKeyCode, modifiers: settings.hotkeyModifiers)
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53 { // Esc cancels
                stopRecording()
                return nil
            }
            guard !flags.isEmpty else { return nil } // need at least one modifier
            settings.hotkeyKeyCode = Int(event.keyCode)
            settings.hotkeyModifiers = Int(flags.rawValue)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
