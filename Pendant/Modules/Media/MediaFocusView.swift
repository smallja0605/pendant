import SwiftUI

/// The media page, and its detailed version (`focused`): the player on the left, the synchronised lyrics on the right. It is one view
/// either way, so opening and closing the detailed page moves the player instead of swapping it.
struct MediaFocusView: View {
    let controller: MediaController
    let size: CGSize
    let focused: Bool

    /// The player's width beside the lyrics: 5 cells or 56 % of the page, whichever is smaller — unless the setting moved it.
    private var playerWidth: CGFloat {
        let share = FocusCapsuleSettings.shared.playerShare
        if share == 56 { return min(CGFloat(5) * Tuning.shared.cellWidth, size.width * 0.56) }
        return size.width * CGFloat(share) / 100
    }

    var body: some View {
        let left = focused ? playerWidth : size.width
        HStack(spacing: 0) {
            MediaView(controller: controller, focused: focused).frame(width: left, height: size.height)
            if focused {
                Rectangle().fill(.white.opacity(0.18)).frame(width: 2, height: size.height * Tuning.shared.dividerLengthRatio)
                    .frame(width: 20, height: size.height)
                    .transition(.opacity)
                LyricsPane(controller: controller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
    }
}

private struct LyricsPane: View {
    let controller: MediaController
    @State private var lyrics = LyricsStore.shared
    @State private var settings = AppSettings.shared

    var body: some View {
        LyricsView(controller: controller, lyrics: lyrics, enabled: settings.lyricsAvailable)
            .task(id: "\(controller.nowPlaying?.snapshot.trackKey ?? "")|\(settings.lyricsSourcesSignature)") {
                if let snapshot = controller.nowPlaying?.snapshot { lyrics.load(for: snapshot) }
            }
    }
}

/// How the lyrics look and move (設定 › 小工具 › 獨立膠囊 › 音樂 › 歌詞外觀), read from the settings once per drawing.
struct LyricsStyle {
    var size: CGFloat
    var weight: Font.Weight
    var centered: Bool
    var othersOpacity: Double
    var othersScale: CGFloat
    var scroll: Animation
    /// The cover's colour for the line being sung, or white.
    var fill: Color
    var tapToSeek: Bool

    init(_ settings: FocusCapsuleSettings, palette: [Color]?) {
        size = CGFloat(settings.lyricsFontSize)
        weight = [Font.Weight.regular, .medium, .semibold, .bold, .heavy][min(max(settings.lyricsFontWeight, 0), 4)]
        centered = settings.lyricsCentered
        othersOpacity = Double(settings.lyricsOthersOpacity) / 100
        othersScale = CGFloat(settings.lyricsOthersScale) / 100
        scroll = settings.lyricsScrollSpring ? .spring(response: settings.lyricsScrollDuration, dampingFraction: 0.72)
            : .easeInOut(duration: settings.lyricsScrollDuration)
        fill = settings.lyricsFillArtwork ? (palette?.first ?? .white) : .white
        tapToSeek = settings.lyricsTapToSeek
    }

    var alignment: Alignment { centered ? .center : .leading }
    var textAlignment: TextAlignment { centered ? .center : .leading }
    var anchor: UnitPoint { centered ? .center : .leading }
}

/// Lyrics that follow the song: the current line is white and centred, the others fade away above and below it.
struct LyricsView: View {
    let controller: MediaController
    let lyrics: LyricsStore
    let enabled: Bool
    @State private var registry = ModuleRegistry.shared
    @State private var focusSettings = FocusCapsuleSettings.shared

    private var style: LyricsStyle { LyricsStyle(focusSettings, palette: controller.artworkPalette) }

    var body: some View {
        Group {
            if !enabled {
                note("歌詞來源已關閉")
            } else if controller.nowPlaying == nil {
                EmptyView()
            } else {
                switch lyrics.state {
                case .idle, .loading: ProgressView().controlSize(.small).tint(.white)
                case .none: note("沒有歌詞")
                case let .plain(lines): plain(lines)
                case let .synced(lines): synced(lines)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: lyrics.state)
    }

    private func note(_ text: String) -> some View {
        Text(loc(text)).font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.4))
    }

    /// Lyrics without timing (the player's own): the view follows the song's progress by proportion, which is only a guess at
    /// where the singing is, so no line is marked as current.
    private func plain(_ lines: [String]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line).font(.system(size: style.size - 2, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(style.textAlignment).frame(maxWidth: .infinity, alignment: style.alignment).id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
            }
            .mask(edgeFade)
            // Opening the page (and the animation that follows it) lands on the estimated line.
            .task(id: lines.count) {
                for delay in [60, 300, 700] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    proxy.scrollTo(estimatedIndex(lines.count, at: Date()), anchor: .center)
                }
            }
            .onChange(of: registry.focusTransitioning) { _, moving in
                if !moving { proxy.scrollTo(estimatedIndex(lines.count, at: Date()), anchor: .center) }
            }
            .background {
                TimelineView(.periodic(from: .now, by: 4)) { context in
                    Color.clear.onChange(of: estimatedIndex(lines.count, at: context.date)) { _, index in
                        withAnimation(style.scroll) { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            }
        }
    }

    private func estimatedIndex(_ count: Int, at date: Date) -> Int {
        guard count > 1, let now = controller.nowPlaying, now.snapshot.duration > 0 else { return 0 }
        let progress = min(max(now.position(at: date) / now.snapshot.duration, 0), 1)
        return min(Int((progress * Double(count)).rounded(.down)), count - 1)
    }

    private func synced(_ lines: [LyricLine]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(lines) { line in
                        LyricRow(line: line, controller: controller, lines: lines, style: style)
                            .id(line.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 60)
            }
            .mask(edgeFade)
            // Opening the page lands on the line being sung (the timer below only reacts to a change of line).
            .task(id: lines.count) {
                for delay in [60, 300, 700] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    proxy.scrollTo(currentIndex(lines, at: Date()), anchor: .center)
                }
            }
            .onChange(of: registry.focusTransitioning) { _, moving in
                if !moving { proxy.scrollTo(currentIndex(lines, at: Date()), anchor: .center) }
            }
            .background {
                TimelineView(.periodic(from: .now, by: 0.3)) { context in
                    Color.clear.onChange(of: currentIndex(lines, at: context.date)) { _, index in
                        withAnimation(style.scroll) { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            }
        }
    }

    private var edgeFade: some View {
        LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                               .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }

    private func currentIndex(_ lines: [LyricLine], at date: Date) -> Int {
        guard let now = controller.nowPlaying else { return 0 }
        let position = lyricPosition(of: now, at: date)
        return lines.lastIndex { $0.time <= position + 0.25 } ?? 0
    }
}

private struct LyricRow: View {
    let line: LyricLine
    let controller: MediaController
    let lines: [LyricLine]
    let style: LyricsStyle
    @State private var hovering = false

    /// How visible a line is while it is not being sung (a little more under the pointer when a tap jumps to it).
    private var dimmed: Double { hovering && style.tapToSeek ? min(style.othersOpacity + 0.28, 1) : style.othersOpacity }

    var body: some View {
        // Word-timed lines of the current line redraw every frame (the fill follows the song); the rest tick slowly.
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let position = controller.nowPlaying.map { lyricPosition(of: $0, at: context.date) } ?? 0
            let current = (lines.lastIndex { $0.time <= position + 0.25 } ?? 0) == line.id
            Group {
                if line.isInterlude {
                    // An interlude (or "na na na"): three dots that fill up until the next line.
                    let end = line.id + 1 < lines.count ? lines[line.id + 1].time : line.time + 5
                    let progress = current ? LyricsLineProgress.fraction(position, from: line.time, to: end) : 0
                    LyricDots(progress: progress, size: 8, tint: style.fill)
                        .opacity(current ? 1 : 0.35)
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: style.alignment)
                } else if current && !line.words.isEmpty {
                    WordFillText(line: line, controller: controller, style: style)
                } else {
                    Text(line.displayParts.joined(separator: "\n"))
                        .font(.system(size: style.size, weight: style.weight))
                        .foregroundStyle(style.fill.opacity(current ? 1 : dimmed))
                        .multilineTextAlignment(style.textAlignment)
                        .frame(maxWidth: .infinity, alignment: style.alignment)
                }
            }
            .scaleEffect(current ? 1 : style.othersScale, anchor: style.anchor)
            .animation(.easeOut(duration: 0.3), value: current)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // A tap jumps the song to this line.
        .onTapGesture { if style.tapToSeek { controller.seek(to: line.time - AppSettings.shared.lyricsOffset) } }
    }
}

/// The line being sung, filled word by word: sung words are white, the word being sung fills in as it is sung, the rest stay dim.
private struct WordFillText: View {
    let line: LyricLine
    let controller: MediaController
    let style: LyricsStyle

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let position = controller.nowPlaying.map { lyricPosition(of: $0, at: context.date) } ?? 0
            line.words.reduce(Text("")) { result, word in
                result + Text(word.text).foregroundColor(style.fill.opacity(0.35 + 0.65 * LyricsLineProgress.value(of: word, at: position)))
            }
            .font(.system(size: style.size, weight: style.weight))
            .multilineTextAlignment(style.textAlignment)
            .frame(maxWidth: .infinity, alignment: style.alignment)
        }
    }
}

enum LyricsLineProgress {
    /// How far `position` is from `start` to `end`, 0…1.
    static func fraction(_ position: TimeInterval, from start: TimeInterval, to end: TimeInterval) -> Double {
        end > start ? min(max((position - start) / (end - start), 0), 1) : 1
    }

    /// 0 before the word is sung, 1 after, in between while it is.
    static func value(of word: LyricWord, at position: TimeInterval) -> Double {
        guard word.end > word.start else { return position >= word.start ? 1 : 0 }
        return min(max((position - word.start) / (word.end - word.start), 0), 1)
    }
}

/// Three dots that light up one after the other as `progress` goes from 0 to 1 (an interlude counting down to the next line).
struct LyricDots: View {
    let progress: Double
    var size: CGFloat = 8
    var tint = Color.white

    var body: some View {
        HStack(spacing: size * 0.7) {
            ForEach(0..<3, id: \.self) { index in
                let fill = min(max(progress * 3 - Double(index), 0), 1)
                Circle()
                    .fill(tint.opacity(0.3 + 0.7 * fill))
                    .frame(width: size, height: size)
                    .scaleEffect(0.85 + 0.25 * fill)
            }
        }
        .animation(.easeOut(duration: 0.25), value: Int(progress * 3))
    }
}
