import SwiftUI

/// The media player page of the expanded capsule (requirements 4.1).
@MainActor
final class MediaModule: PendantModule {
    let id = "media"
    let displayName = String(localized: "module.media", defaultValue: "媒體播放器")
    let symbolName = "music.note"
    let cells = CellRange(default: 5, range: 3...10)
    let supportsCompact = true
    let requiredPermissions: [PendantPermission] = [.automation]
    var isEnabled = true

    let controller: MediaController

    init(controller: MediaController) {
        self.controller = controller
    }

    func makeView(size: CGSize) -> AnyView {
        AnyView(MediaView(controller: controller).frame(width: size.width, height: size.height))
    }

    func makeSettingsView() -> AnyView { AnyView(MediaModuleSettings()) }

    var activityPriority: Int { 0 }

    func makeCompactView(role: IslandRole) -> AnyView? {
        role == .secondary ? AnyView(MediaIslandContent(controller: controller)) : nil
    }

    func activate() { controller.start() }
    func deactivate() { controller.stop() }
}

private struct MediaModuleSettings: View {
    @State private var settings = AppSettings.shared
    @State private var cacheSize = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("專輯色光暈背景", isOn: $settings.artworkGlow)
            Toggle("串流曲目線上補封面(Apple Music)", isOn: $settings.onlineArtwork)
            Text(
                "Apple Music 串流的歌曲無法從 App 取得封面時，只會把歌名與歌手送到 Apple 的公開搜尋服務(itunes.apple.com)取得封面，不含任何其他資料。關閉後這類歌曲不顯示封面。"
            )
            .font(.caption).foregroundStyle(.secondary)
            Toggle("快取專輯封面(換歌更即時)", isOn: $settings.artworkCache)
            HStack(spacing: 10) {
                Button("清除封面快取") {
                    Task { await ArtworkCache.shared.clear(); cacheSize = 0 }
                }
                Text(cacheSize == 0 ? "目前沒有快取" : "已使用 \(ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .task { cacheSize = await ArtworkCache.shared.sizeInBytes() }
            Text(
                "快取放在 ~/Library/Caches/com.smallja.pendant,只存縮小的封面圖(檔名是雜湊值，不含歌名),超過 40 MB 會自動刪最舊的。"
            )
            .font(.caption).foregroundStyle(.secondary)
            Picker("音樂來源", selection: $settings.mediaSourcePreference) {
                Text("自動").tag(MediaSourcePreference.auto)
                Text("Apple Music").tag(MediaSourcePreference.appleMusic)
                Text("Spotify").tag(MediaSourcePreference.spotify)
            }
            .frame(maxWidth: 260)
            Text("其他 Now Playing 來源(例如瀏覽器網頁)自 macOS 15.4 起無法被第三方 App 讀取，因此不支援。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Media as a secondary island: cover (or note icon) and the three waveform bars.
private struct MediaIslandContent: View {
    let controller: MediaController

    var body: some View {
        HStack(spacing: 9) {
            if AppSettings.shared.showCoverInCompact, let image = controller.artwork {
                Image(nsImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: "music.note").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            }
            if AppSettings.shared.showWaveformInCompact {
                WaveformBars(isPlaying: controller.nowPlaying?.isPlaying ?? false, isVisible: true)
            }
        }
    }
}
