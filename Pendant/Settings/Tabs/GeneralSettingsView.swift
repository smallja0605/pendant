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
            Section {
                Toggle("登入時啟動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        loginError = LoginItem.set(enabled)
                        launchAtLogin = LoginItem.isEnabled
                    }
                    .settingNote(loginError.map { "無法變更：\($0)" } ?? (LoginItem.needsApproval ? "請在「系統設定 › 一般 › 登入項目」允許 Pendant" : nil))
            }
            Section("顯示") {
                TipRow(title: "在選單列顯示圖示", tip: "隱藏後可在瀏海按右鍵開啟設定") {
                    Toggle("", isOn: $settings.showMenuBarIcon).labelsHidden()
                }
                Toggle("全螢幕時顯示", isOn: $settings.showInFullscreen)
                DropdownRow(title: "顯示螢幕", selection: $settings.screenChoice, options: [
                    (AppSettings.ScreenChoice.main, "主螢幕"), (.underCursor, "游標所在螢幕"), (.all, "所有螢幕同時顯示"),
                ])
            }
            Section("瀏海") {
                TipRow(title: "瀏海懸停效果", tip: "控制膨脹動畫與進入震動") {
                    Toggle("", isOn: $settings.hoverEffectEnabled).labelsHidden()
                }
                SliderRow(title: "實體瀏海寬度微調", value: $settings.notchWidthAdjust, range: -30...30, unit: "pt",
                          accessory: AnyView(Button("重設") { settings.notchWidthAdjust = 0 }))
            }
            Section("展開") {
                DropdownRow(title: "懸停展開", selection: $settings.hoverExpandMode, options: [
                    (HoverExpandMode.off, "關閉"), (.compactOnly, "僅小膠囊顯示時"), (.always, "永遠啟用"),
                ])
                SliderRow(title: "懸停延遲", value: $settings.hoverDelay, range: 0...1.5, step: 0.05, unit: "秒", fractionDigits: 2)
                    .dimmed(when: settings.hoverExpandMode == .off)
                SliderRow(title: "離開後收合延遲", value: $settings.collapseDelay, range: 0.1...1.5, step: 0.05, unit: "秒", fractionDigits: 2)
            }
            Section("快捷鍵") { HotkeyRow(settings: settings) }
            Section {
                TipRow(title: "觸覺回饋", tip: "關閉後停用所有震動") {
                    Toggle("", isOn: $haptics).labelsHidden()
                        .onChange(of: haptics) { _, enabled in HapticService.shared.isEnabled = enabled }
                }
                DropdownRow(title: "語言", tip: "重新啟動後生效", selection: $settings.languageOverride, options: [
                    ("system", "跟隨系統"), ("zh-Hant", "繁體中文"), ("en", "English"),
                ])
                .onChange(of: settings.languageOverride) { _, value in applyLanguage(value) }
            }
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
        TipRow(title: "快捷鍵") {
            Button(recording ? "請按下組合鍵…" : shortcutText) {
                if recording { stopRecording() } else { startRecording() }
            }
            .dimmed(when: !settings.hotkeyEnabled)
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
