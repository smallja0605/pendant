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
        ModuleForm(moduleID: "media") {
            Toggle("專輯光暈", isOn: $settings.artworkGlow)
            TipRow(title: "線上封面", tip: "歌名與歌手會送到 Apple 搜尋服務") {
                Toggle("", isOn: $settings.onlineArtwork).labelsHidden()
            }
            TipRow(title: "封面快取") {
                HStack(spacing: 10) {
                    Text(cacheSize == 0 ? "無" : ByteCountFormatter.string(fromByteCount: Int64(cacheSize), countStyle: .file))
                        .foregroundStyle(.secondary)
                    Button("清除") { Task { await ArtworkCache.shared.clear(); cacheSize = 0 } }
                    Toggle("", isOn: $settings.artworkCache).labelsHidden().toggleStyle(.switch)
                }
            }
            DropdownRow(title: "音樂來源", selection: $settings.mediaSourcePreference, options: [
                (MediaSourcePreference.auto, "自動"), (.appleMusic, "Apple Music"), (.spotify, "Spotify"),
            ])
        }
        .task { cacheSize = await ArtworkCache.shared.sizeInBytes() }
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
