import SwiftUI

/// 授權 tab → permission status (requirements 7.8). This app needs no licence key.
struct PermissionsSettingsView: View {
    @State private var states: [PermissionKind: PermissionState] = [:]

    private struct Row {
        let kind: PermissionKind
        let title: String
        let detail: String
        let symbol: String
    }

    private static let rows = [
        Row(kind: .calendars, title: "行事曆", detail: "日曆模組顯示你的行程", symbol: "calendar"),
        Row(kind: .reminders, title: "提醒事項", detail: "待辦模組讀寫提醒事項", symbol: "checklist"),
        Row(kind: .camera, title: "相機", detail: "鏡子模組僅在可見時使用前鏡頭", symbol: "web.camera"),
        Row(kind: .bluetooth, title: "藍牙", detail: "連接裝置時顯示名稱與電量", symbol: "dot.radiowaves.left.and.right"),
        Row(kind: .automationMusic, title: "自動化：Music", detail: "顯示與控制 Apple Music 播放", symbol: "music.note"),
        Row(kind: .automationSpotify, title: "自動化：Spotify", detail: "顯示與控制 Spotify 播放", symbol: "music.note"),
    ]

    var body: some View {
        Form {
            SettingsTitleHeader()
            Section {
                ForEach(Self.rows, id: \.kind) { row in
                    HStack(spacing: 12) {
                        Image(systemName: row.symbol).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Buttons share one column, the state text another, so the rows line up.
                        Group {
                            switch states[row.kind] {
                            case .notDetermined:
                                Button("請求權限") {
                                    Task {
                                        await PermissionsService.request(row.kind)
                                        await refresh()
                                    }
                                }
                            case .denied:
                                Button("開啟系統設定") { openSettings(row.kind) }
                            default:
                                Color.clear
                            }
                        }
                        .frame(width: 112, alignment: .trailing)
                        StateText(state: states[row.kind] ?? .unknown).frame(width: 64, alignment: .trailing)
                    }
                }
            } footer: {
                Text("資料只留在本機，不蒐集遙測。權限在首次使用該功能時請求。")
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
    }

    private func refresh() async {
        for kind in PermissionKind.allCases {
            states[kind] = await PermissionsService.state(for: kind)
        }
    }

    private func openSettings(_ kind: PermissionKind) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsPane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct StateText: View {
    let state: PermissionState

    var body: some View {
        let (text, color): (String, Color) = switch state {
        case .allowed: ("已允許", .green)
        case .notDetermined: ("尚未詢問", .secondary)
        case .denied: ("已拒絕", .red)
        case .unknown: ("—", .secondary)
        }
        Text(text).font(.callout).foregroundStyle(color)
    }
}
