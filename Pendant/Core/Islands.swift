import CoreGraphics

/// Which side of the main island a secondary island sits on.
enum IslandSide: String, CaseIterable, Sendable { case left, right }

/// How secondary islands are revealed (requirements 3.5.8 ③).
enum IslandDisplayMode: String, CaseIterable, Sendable { case always, brief, hoverOnly }

/// What an activity may be on the island row (7.7).
enum ActivityRole: String, CaseIterable, Sendable { case anyIsland, mainOnly, secondaryOnly, hidden }

/// An activity that is running right now (media playing, timer counting …).
struct LiveActivity: Equatable, Identifiable, Sendable {
    var id: String
    var moduleID: String
    var symbolName: String
    var canBeSecondary = true
    /// False for "secondary only" activities: they never take the main island while another activity can.
    var canBeMain = true
    /// Width of its secondary island (3.5.3: 44–64 pt).
    var secondaryWidth: CGFloat = 52
    /// Timer ended and nobody has reacted yet: the island pulses (3.5.4).
    var isAlerting = false

    var kind: ActivityKind? { ActivityKind(rawValue: id) }
}

/// Everything the island planner needs from the settings (3.5.3, 3.5.8 ⑤).
struct IslandSettings: Equatable, Sendable {
    var leftEnabled = true
    var rightEnabled = true
    var prioritySide: IslandSide = .right
    var gap: CGFloat = 9
    /// Main + secondary islands may span at most this fraction of the screen width.
    var maxSpanFraction: CGFloat = 0.4
    /// Manual horizontal shift per side, positive = away from the notch.
    var leftOffset: CGFloat = 0
    var rightOffset: CGFloat = 0
    var maxWidth: CGFloat = 100
    /// ④ Hang below the menu bar instead of covering it.
    var sinking = false
    /// ⑥ Free x-range in the menu bar (screen coordinates): islands outside it are dropped.
    var leftBound: CGFloat?
    var rightBound: CGFloat?
    static let maxSecondaries = 2
}

/// Where one island is drawn (screen coordinates, AppKit: y grows upward).
struct IslandPlacement: Equatable, Identifiable, Sendable {
    enum Role: Equatable, Sendable { case main, secondary(IslandSide) }
    var id: String
    var role: Role
    var rect: CGRect

    var side: IslandSide? { if case let .secondary(side) = role { side } else { nil } }
}

/// Pure layout of the island row: no UI, fully unit-tested.
enum IslandPlanner {
    // `activities` are ordered by level (highest first). The first one is the main island (at `mainRect`, the compact
    // body); the others become secondary islands if their role allows it. At most two are shown.
    // swiftlint:disable:next function_parameter_count
    static func plan(
        mainRect: CGRect, ear: CGFloat, screenFrame: CGRect, menuBarHeight: CGFloat,
        activities: [LiveActivity], settings: IslandSettings
    ) -> [IslandPlacement] {
        guard let main = activities.first else { return [] }
        let mainIsland = IslandPlacement(id: main.id, role: .main, rect: mainRect)
        var candidates = Array(activities.dropFirst().filter(\.canBeSecondary).prefix(IslandSettings.maxSecondaries))
        while true {
            let placed = place(candidates, mainRect: mainRect, ear: ear, screenFrame: screenFrame,
                               menuBarHeight: menuBarHeight, settings: settings)
            let all = [mainIsland] + placed
            let span = (all.map(\.rect.maxX).max() ?? 0) - (all.map(\.rect.minX).min() ?? 0)
            if span <= settings.maxSpanFraction * screenFrame.width || candidates.isEmpty { return all }
            candidates.removeLast() // lowest level goes first
        }
    }

    // swiftlint:disable:next function_parameter_count
    private static func place(
        _ candidates: [LiveActivity], mainRect: CGRect, ear: CGFloat, screenFrame: CGRect,
        menuBarHeight: CGFloat, settings: IslandSettings
    ) -> [IslandPlacement] {
        let sides: [IslandSide] = [IslandSide.left, .right].filter { $0 == .left ? settings.leftEnabled : settings.rightEnabled }
        guard !sides.isEmpty else { return [] }
        let other: IslandSide = settings.prioritySide == .left ? .right : .left
        let first = sides.contains(settings.prioritySide) ? settings.prioritySide : other
        let second = sides.count == 2 ? other : first

        var edges: [IslandSide: CGFloat] = [.left: mainRect.minX - ear, .right: mainRect.maxX + ear]
        let height = mainRect.height
        let top = screenFrame.maxY - (settings.sinking ? menuBarHeight : 0)
        var result: [IslandPlacement] = []
        var closed: Set<IslandSide> = []
        var shifted: Set<IslandSide> = []
        for (index, activity) in candidates.enumerated() {
            let side = index == 0 ? first : second
            guard !closed.contains(side), let edge = edges[side] else { continue }
            let width = min(activity.secondaryWidth, settings.maxWidth)
            let shift = shifted.contains(side) ? 0 : (side == .left ? settings.leftOffset : settings.rightOffset)
            let originX = side == .left ? edge - settings.gap - width - shift : edge + settings.gap + shift
            let rect = CGRect(x: originX, y: top - height, width: width, height: height)
            if let bound = settings.leftBound, rect.minX < bound { closed.insert(side); continue }
            if let bound = settings.rightBound, rect.maxX > bound { closed.insert(side); continue }
            shifted.insert(side)
            edges[side] = side == .left ? rect.minX : rect.maxX
            result.append(IslandPlacement(id: activity.id, role: .secondary(side), rect: rect))
        }
        return result
    }
}
