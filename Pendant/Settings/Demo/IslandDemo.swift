import SwiftUI

/// State of the island demo: a few made-up activities that obey the real settings (roles, priority, idle delay, display mode,
/// sizes) and the real island planner. Everything reacts to the pointer: click an island to pause it, scroll sideways to change
/// the song, scroll up/down for the volume (⌥ for the brightness), drag the file onto the notch, open the "編輯" menu.
@MainActor
@Observable
final class IslandDemoModel {
    private let settings = AppSettings.shared

    var pausedAt: [String: Date] = [:]
    var fileCount = 3
    var menuOpen = false
    var hovering = false
    var trackIndex = 0
    var coverBump = false
    var infoUntil: Date?
    var hud: HUD?
    var briefUntil: Date?
    var volume = 70.0
    var brightness = 60.0
    var lastSignature = ""

    struct HUD: Equatable {
        var isVolume: Bool
        var until: Date
    }

    /// How long a paused activity that already left the row waits before the demo "plays" it again.
    private let resumeAfterHidden: TimeInterval = 2.5
    @ObservationIgnored private var scrollAccumulated: CGFloat = 0
    @ObservationIgnored private var scrollLockedUntil = Date.distantPast

    func isPaused(_ id: String) -> Bool { pausedAt[id] != nil }

    func togglePause(_ id: String, now: Date) {
        guard id == "media" || id == "timer" else { return }
        if pausedAt[id] != nil { pausedAt[id] = nil } else { pausedAt[id] = now }
    }

    /// Paused activities leave after the idle delay and come back a moment later.
    func tick(_ now: Date) {
        for (id, since) in pausedAt where now.timeIntervalSince(since) > settings.mediaPauseRetention + resumeAfterHidden {
            pausedAt[id] = nil
        }
        if let until = briefUntil, now > until { briefUntil = nil }
        if let until = infoUntil, now > until { infoUntil = nil }
        if let hud, now > hud.until { self.hud = nil }
    }

    func isLive(_ id: String, now: Date) -> Bool {
        guard let since = pausedAt[id] else { return true }
        return now.timeIntervalSince(since) < settings.mediaPauseRetention
    }

    func arranged(now: Date) -> [LiveActivity] {
        var live: [String: LiveActivity] = [:]
        if isLive("media", now: now) {
            live["media"] = LiveActivity(id: "media", moduleID: "media", symbolName: "music.note",
                                         secondaryWidth: ActivityCenter.mediaIslandWidth(settings))
        }
        if isLive("timer", now: now) {
            live["timer"] = LiveActivity(id: "timer", moduleID: "timer", symbolName: "timer",
                                         secondaryWidth: ActivityCenter.timerIslandWidth())
        }
        let countWidth: CGFloat = settings.shelfShowsCount ? 6 + CGFloat(String(fileCount).count) * 9 : 0
        live["shelf"] = LiveActivity(id: "shelf", moduleID: "shelf", symbolName: "tray.and.arrow.down",
                                     secondaryWidth: ActivityCenter.sidePadding + 18 + countWidth + 4)
        return ActivityOrdering.arrange(live, settings: settings)
    }

    func songChanged(now: Date) {
        trackIndex += 1
        coverBump = true
        if settings.showTrackInfoOnChange { infoUntil = now.addingTimeInterval(settings.trackInfoSeconds) }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(170))
            coverBump = false
        }
    }

    func scrolled(dx: CGFloat, dy: CGFloat, option: Bool, now: Date) {
        if abs(dx) > abs(dy) {
            guard now > scrollLockedUntil else { return }
            scrollAccumulated += dx
            if abs(scrollAccumulated) >= 40 {
                scrollAccumulated = 0
                scrollLockedUntil = now.addingTimeInterval(0.45)
                songChanged(now: now)
            }
        } else if option {
            guard settings.hudBrightness else { return }
            brightness = min(max(brightness + dy * 0.5, 0), 100)
            hud = HUD(isVolume: false, until: now.addingTimeInterval(settings.hudSeconds))
        } else {
            guard settings.hudVolume else { return }
            volume = min(max(volume + dy * 0.5, 0), 100)
            hud = HUD(isVolume: true, until: now.addingTimeInterval(settings.hudSeconds))
        }
    }
}

struct IslandDemoView: View {
    @State private var model = IslandDemoModel()
    @State private var settings = AppSettings.shared
    @State private var tuning = Tuning.shared
    /// The settings page for the islands shows only size and layout (hover and the menu); the small-capsule page also reacts to
    /// clicks and the scroll wheel.
    var interactive = true

    private typealias Desk = DemoDesk<AnyView>
    private static let size = CGSize(width: DemoDesk<EmptyView>.screenWidth, height: 150)
    private static let viewport: CGFloat = 540
    private static var minX: CGFloat { DemoDesk<EmptyView>.minX(viewport: viewport) }

    var body: some View {
        VStack(spacing: 8) {
            DemoDesk(viewport: Self.viewport, height: Self.size.height) {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in stage(now: context.date) }
            }
        }
    }

    // MARK: Layout

    private func geometry() -> NotchGeometry {
        NotchGeometry(screenFrame: CGRect(origin: .zero, size: Self.size), safeAreaTop: 0, auxLeft: nil, auxRight: nil,
                      menuBarHeight: DemoDesk<EmptyView>.menuBarHeight, widthAdjustment: settings.notchWidthAdjust)
    }

    private struct Plan {
        var main: LiveActivity?
        var mainRect: CGRect
        var secondaries: [(IslandPlacement, LiveActivity)]
    }

    private func plan(now: Date) -> Plan {
        let geometry = geometry()
        var layout = CapsuleLayout(notch: geometry)
        let activities = model.arranged(now: now)
        if let mode = activities.first?.kind?.timerMode {
            layout.compactActivityExtra = TimerCompactMetrics.extraWing(standardWing: layout.compactWing, mode: mode)
        }
        let mainRect = activities.isEmpty ? geometry.notchRect : layout.bodyRect(for: .compact)
        let placements = IslandPlanner.plan(
            mainRect: mainRect, ear: NotchGeometry.earRadius, screenFrame: geometry.screenFrame,
            menuBarHeight: DemoDesk<EmptyView>.menuBarHeight, activities: activities, settings: settings.islandSettings)
        let secondaries = placements.filter { $0.side != nil }.compactMap { placement in
            activities.first { $0.id == placement.id }.map { (placement, $0) }
        }
        return Plan(main: activities.first, mainRect: mainRect, secondaries: secondaries)
    }

    /// Screen rect (y up) → desk rect (y down).
    private func deskRect(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: Self.size.height - rect.maxY, width: rect.width, height: rect.height)
    }

    private var revealed: Bool {
        switch settings.islandDisplayMode {
        case .always: true
        case .brief: model.briefUntil != nil
        case .hoverOnly: model.hovering
        }
    }

    // MARK: Stage

    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func stage(now: Date) -> some View {
        let plan = plan(now: now)
        let mainRect = deskRect(plan.mainRect)
        let signature = plan.secondaries.map(\.0.id).joined(separator: ",") + (plan.main?.id ?? "")
        let hiddenByMenu = model.menuOpen && settings.islandHideDuringMenus
        return ZStack(alignment: .topLeading) {
            menuBar
            if let main = plan.main {
                IslandShape(topRadius: 0, bottomRadius: 15).fill(Color.black)
                    .overlay { DemoIslandContent(activity: main, model: model, now: now, isMain: true) }
                    .frame(width: mainRect.width, height: mainRect.height)
                    .offset(x: mainRect.minX, y: mainRect.minY)
                    .onTapGesture { if interactive { model.togglePause(main.id, now: now) } }
            }
            if let hud = model.hud {
                DemoHUD(isVolume: hud.isVolume, level: hud.isVolume ? model.volume : model.brightness)
                    .frame(width: 300, height: DemoDesk<EmptyView>.menuBarHeight)
                    .offset(x: Self.size.width / 2 - 150, y: 0)
                    .transition(.opacity)
            }
            ForEach(plan.secondaries, id: \.0.id) { placement, activity in
                let rect = deskRect(placement.rect)
                let side = placement.side ?? .right
                Group {
                    if revealed {
                        Capsule().fill(Color.black)
                            .overlay { DemoIslandContent(activity: activity, model: model, now: now, isMain: false) }
                            .onTapGesture { if interactive { model.togglePause(activity.id, now: now) } }
                    } else {
                        Circle().fill(.white.opacity(0.55)).frame(width: 5, height: 5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: side == .left ? .trailing : .leading)
                    }
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .opacity(hiddenByMenu ? 0 : 1)
                .transition(.opacity.combined(with: .scale(scale: 0.5)))
            }
            if let until = model.infoUntil, until > now {
                Text("歌曲 \(model.trackIndex + 1) · 歌手")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 16).frame(height: 26)
                    .background(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12).fill(.black))
                    .offset(x: Self.size.width / 2 - 70, y: mainRect.maxY)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .overlay {
            if interactive { DemoScrollCatcher { dx, dy, option in model.scrolled(dx: dx, dy: dy, option: option, now: Date()) } }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active: model.hovering = true
            case .ended:
                model.hovering = false
                model.menuOpen = false
            }
        }
        .animation(AnimationTokens.island(reduceMotion: false), value: plan.secondaries.map(\.0))
        .animation(AnimationTokens.island(reduceMotion: false), value: revealed)
        .animation(AnimationTokens.island(reduceMotion: false), value: hiddenByMenu)
        .animation(AnimationTokens.island(reduceMotion: false), value: plan.main?.id)
        .animation(.easeOut(duration: 0.25), value: model.infoUntil != nil)
        .animation(.easeOut(duration: 0.2), value: model.hud)
        .onChange(of: signature) { _, new in
            if new != model.lastSignature, settings.islandDisplayMode == .brief {
                model.briefUntil = Date().addingTimeInterval(2.5)
            }
            model.lastSignature = new
        }
        .onChange(of: now) { _, date in model.tick(date) }
        .onChange(of: settings.islandDisplayMode) { _, mode in
            if mode == .brief { model.briefUntil = Date().addingTimeInterval(2.5) }
        }
    }

    private var menuBar: some View {
        HStack(spacing: 18) {
            Text("編輯")
                .font(.system(size: 15))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(model.menuOpen ? 0.25 : 0)))
                .onTapGesture { model.menuOpen.toggle() }
        }
        .foregroundStyle(.white)
        .padding(.leading, Self.minX + 12)
        .frame(height: DemoDesk<EmptyView>.menuBarHeight)
    }
}

private struct IslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: topRadius, bottomLeadingRadius: bottomRadius,
                               bottomTrailingRadius: bottomRadius, topTrailingRadius: topRadius).path(in: rect)
    }
}

/// What an island shows. Pausing a player only changes the waveform; a paused timer's digits stay.
private struct DemoIslandContent: View {
    let activity: LiveActivity
    let model: IslandDemoModel
    let now: Date
    let isMain: Bool
    @State private var settings = AppSettings.shared

    var body: some View {
        switch activity.id {
        case "media": media
        case "timer": timer
        default: shelf
        }
    }

    private var cover: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(LinearGradient(colors: [.orange, Color(red: 1, green: 0.3, blue: 0.5)], startPoint: .top, endPoint: .bottom))
            .frame(width: 20, height: 20)
            .scaleEffect(model.coverBump ? 0.65 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: model.coverBump)
    }

    /// The main island carries the cover on its far left and the waveform on its far right; a secondary island is one small pill.
    @ViewBuilder private var media: some View {
        let wave = DemoWaveform(active: !model.isPaused("media"))
        if isMain {
            HStack(spacing: 0) {
                if settings.showCoverInCompact { cover }
                Spacer(minLength: 8)
                if settings.showWaveformInCompact { wave }
            }
            .padding(.horizontal, 12)
            .overlay {
                if !settings.showCoverInCompact && !settings.showWaveformInCompact {
                    Image(systemName: "music.note").foregroundStyle(.white)
                }
            }
        } else {
            HStack(spacing: 9) {
                if settings.showCoverInCompact { cover }
                if settings.showWaveformInCompact { wave }
                if !settings.showCoverInCompact && !settings.showWaveformInCompact {
                    Image(systemName: "music.note").foregroundStyle(.white)
                }
            }
        }
    }

    private var timer: some View {
        HStack(spacing: 8) {
            if settings.timerRing {
                Circle().trim(from: 0, to: 0.72).stroke(Color.green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 16, height: 16)
            } else {
                Image(systemName: "timer").foregroundStyle(.white)
            }
            Text("04:32").font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
        }
        .opacity(model.isPaused("timer") ? 0.55 : 1)
    }

    private var shelf: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            if settings.shelfShowsCount {
                Text("\(model.fileCount)").font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
            }
        }
    }
}

private struct DemoWaveform: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !active)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { index in
                    let level = active ? 0.35 + 0.65 * abs(sin(time * 5 + Double(index) * 1.3)) : 0.2
                    Capsule().fill(.white).frame(width: 2.5, height: 14 * level)
                }
            }
            .frame(height: 14)
        }
    }
}

private struct DemoHUD: View {
    let isVolume: Bool
    let level: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isVolume ? "speaker.wave.2.fill" : "sun.max.fill").font(.system(size: 14))
            Capsule().fill(.white.opacity(0.25)).frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in Capsule().fill(.white).frame(width: proxy.size.width * level / 100) }
                }
            Text("\(Int(level))").font(.system(size: 13, weight: .semibold).monospacedDigit()).frame(width: 28, alignment: .trailing)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 15, bottomTrailingRadius: 15).fill(.black))
    }
}
