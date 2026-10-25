import SwiftUI

/// The media player page of the expanded capsule (requirements 4.1).
@MainActor
final class MediaModule: PendantModule {
    let id = "media"
    let displayName = String(localized: "module.media", defaultValue: "音樂")
    let symbolName = "music.note"
    let cells = CellRange(default: 5, range: 3...10)
    let supportsCompact = true
    let requiredPermissions: [PendantPermission] = [.automation]
    var isEnabled = true

    let controller: MediaController

    init(controller: MediaController) {
        self.controller = controller
    }

    var focusTitle: String { "音樂" }

    // The page and the detailed page are the same view (only `focused` differs), so the player moves rather than being replaced.
    func makeView(size: CGSize) -> AnyView {
        AnyView(MediaFocusView(controller: controller, size: size, focused: false))
    }

    func makeFocusView(size: CGSize) -> AnyView? { AnyView(MediaFocusView(controller: controller, size: size, focused: true)) }

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

    static var canTap: Bool { if #available(macOS 14.2, *) { true } else { false } }
    private var barCount: Binding<Double> {
        Binding(get: { Double(settings.waveformBars) }, set: { settings.waveformBars = min(max(Int($0.rounded()), 3), 7) })
    }

    private var gain: Binding<Double> {
        Binding(get: { Double(settings.waveformGain) }, set: { settings.waveformGain = min(max(Int($0.rounded()), 50), 200) })
    }
    private var sensitivity: Binding<Double> {
        Binding(get: { Double(settings.waveformSensitivity) }, set: { settings.waveformSensitivity = min(max(Int($0.rounded()), 50), 200) })
    }

    var body: some View {
        ModuleForm(moduleID: "media") {
            Toggle("專輯光暈", isOn: $settings.artworkGlow)
            TipRow(title: "真實音波", tip: "依實際播放的聲音動，需要「系統音訊錄製」權限") {
                Toggle("", isOn: $settings.realWaveform).labelsHidden().disabled(!Self.canTap)
            }
            if settings.realWaveform { WaveformStatusRow() }
            SliderRow(title: "音波線條數量", value: barCount, range: 3...7, step: 1, unit: "條")
            if settings.realWaveform {
                SliderRow(title: "音波漲幅", value: gain, range: 50...200, step: 5, unit: "%")
                SliderRow(title: "音波靈敏度", value: sensitivity, range: 50...200, step: 5, unit: "%")
            }
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
            TipRow(title: "線上歌詞", tip: "歌名、歌手與長度會送到 lrclib.net") {
                Toggle("", isOn: $settings.onlineLyrics).labelsHidden()
            }
            DropdownRow(title: "歌詞來源", selection: $settings.lyricsSource, options: [
                (AppSettings.LyricsSource.auto, "自動"), (.player, "Apple Music"), (.online, "線上（lrclib.net）"),
            ])
            DropdownRow(title: "音樂來源", selection: $settings.mediaSourcePreference, options: [
                (MediaSourcePreference.auto, "自動"), (.appleMusic, "Apple Music"), (.spotify, "Spotify"),
            ])
        }
        .task { cacheSize = await ArtworkCache.shared.sizeInBytes() }
    }
}

/// What the real waveform is doing: waiting, working, or why not (checked once a second while the page is open).
private struct WaveformStatusRow: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            TipRow(title: "音波狀態") {
                Text(text).foregroundStyle(.secondary)
            }
        }
    }

    private var text: String {
        guard #available(macOS 14.2, *) else { return "需要 macOS 14.2 以上" }
        switch AudioSpectrum.shared.status {
        case .off: return "播放時才會啟動"
        case .starting: return "啟動中⋯"
        case let .failed(message): return message
        case .running: return AudioSpectrum.shared.seemsSilent ? "沒有收到聲音（可能還沒授權）" : "運作中"
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
