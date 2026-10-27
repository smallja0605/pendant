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
                        HStack(spacing: 6) {
                            Text("版本 \(version)").foregroundStyle(.secondary)
                            if UpdateChecker.bundleVersion.isPrerelease {
                                Text("測試版").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange)
                            }
                        }
                        Text("作者：smallja").foregroundStyle(.secondary)
                    }
                }
            }
            updateSection
            Section("設定檔") {
                TipRow(title: "匯出設定", tip: "把所有設定存成一個檔案，Windows 版也能讀；不含金鑰與這台電腦專屬的項目") {
                    Button("匯出…") { SettingsTransferPanel.exportToFile() }
                }
                TipRow(title: "匯入設定", tip: "讀取設定檔（Mac 或 Windows 版匯出的），對方沒有的功能會略過；匯入後會重新啟動") {
                    Button("匯入…") { SettingsTransferPanel.importFromFile() }
                }
            }
            Section {
                TipRow(title: "解除安裝", tip: "移除登入項目、資料夾與偏好設定，可保留筆記") {
                    Button("解除安裝…", role: .destructive) { UninstallService.confirmAndRun() }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var updateSection: some View {
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
            LabeledContent("更新來源") { Text(UpdateConfig.source.title).foregroundStyle(.secondary) }
            Toggle("自動檢查更新", isOn: $settings.autoCheckUpdates)
            Toggle("自動安裝更新", isOn: $settings.autoInstallUpdates).dimmed(when: !settings.autoCheckUpdates)
        }
        Section("測試者計畫") {
            TipRow(title: "加入測試者群組", tip: "提早收到測試版（beta）更新，可能不穩定；關閉後會在下一個正式版時切回正式版") {
                Toggle("", isOn: Binding(
                    get: { settings.updateChannel == UpdateRules.Channel.preview.rawValue },
                    set: { settings.updateChannel = ($0 ? UpdateRules.Channel.preview : .stable).rawValue }
                ))
                .labelsHidden()
            }
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
