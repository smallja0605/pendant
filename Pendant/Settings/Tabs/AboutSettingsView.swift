import SwiftUI

/// 7.4 About: version, updates (8.1) and uninstall (4.11).
struct AboutSettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var updater = UpdateChecker.shared

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pendant").font(.title3.weight(.semibold))
                        Text("版本 \(version)").foregroundStyle(.secondary)
                        Text("作者:smallja").foregroundStyle(.secondary)
                        Text("macOS 14+;Liquid Glass 外觀需 macOS 26+").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            updateSection
            if !LiquidGlass.isAvailable {
                Section("外觀") {
                    Text("「Liquid」分頁與 Liquid Glass 選項需要 macOS 26 以上，目前的系統已自動隱藏並使用標準材質。").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("解除安裝") {
                Button("解除安裝 Pendant⋯", role: .destructive) { UninstallService.confirmAndRun() }
                    .settingNote("會移除登入項目、資料夾與偏好設定,並把 App 移到垃圾桶;可選擇保留筆記。")
            }
        }
        .formStyle(.grouped)
    }

    private var updateSection: some View {
        Section("更新") {
            HStack {
                Button("檢查更新") { Task { await updater.check(userInitiated: true) } }
                    .disabled(isBusy)
                statusText
                Spacer()
            }
            if let release = updater.availableRelease {
                VStack(alignment: .leading, spacing: 6) {
                    Text("新版本 \(release.tagName)").font(.subheadline.weight(.semibold))
                    if let notes = release.body, !notes.isEmpty {
                        Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(8)
                    }
                    Button("下載並安裝") { Task { await updater.install() } }
                }
            }
            Toggle("自動檢查更新(啟動時與每 24 小時)", isOn: $settings.autoCheckUpdates)
            Toggle("發現新版本時自動下載並安裝", isOn: $settings.autoInstallUpdates).disabled(!settings.autoCheckUpdates)
            LabeledContent("更新頻道") {
                Picker("", selection: $settings.updateChannel) {
                    Text("正式版").tag("stable")
                    Text("含預覽版").tag("preview")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize() // as wide as its two segments, at the row's right edge
            }
            .settingNote("更新來源:~/Library/Application Support/Pendant/Updates(用 scripts/publish-update.sh 發佈新版本)。")
        }
    }

    private var isBusy: Bool {
        switch updater.state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    @ViewBuilder private var statusText: some View {
        switch updater.state {
        case .idle, .available: EmptyView()
        case .checking: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("檢查中…") }
        case .upToDate: Text("已是最新版本").foregroundStyle(.secondary)
        case let .downloading(fraction): HStack(spacing: 6) { ProgressView(value: fraction).frame(width: 120); Text("下載中") }
        case .installing: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("驗證並安裝中…") }
        case let .failed(message): Text(message).foregroundStyle(.red).font(.caption)
        }
    }
}
