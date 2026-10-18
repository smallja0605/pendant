import Foundation
import Observation

/// Live-tunable layout / animation numbers. The defaults are the values the app ships with; the
/// developer options window (`Settings/Developer`, ⌥ on the menu bar menu or `--developer`) edits them at
/// runtime and the changes are saved in UserDefaults (`tuning.<id>`), so they survive relaunches.
@Observable
final class Tuning: @unchecked Sendable {
    static let shared = Tuning(loadSaved: true)
    static let keyPrefix = "tuning."

    init(loadSaved: Bool = false, defaults store: UserDefaults = .standard) {
        if loadSaved { load(defaults: store) }
    }

    // Expanded capsule
    var cellWidth = 72.0
    var contentInset = 18.0
    var moduleGap = 30.0
    /// Length of the separator between modules relative to the content height.
    var dividerLengthRatio = 0.88
    var expandedContentHeight = 190.0
    /// Space below the modules, inside the open capsule (the modules keep their size).
    var expandedBottomInset = 6.0
    // Media page
    var artSize = 118.0
    var artTextGap = 12.0
    var textLineSpacing = 3.0
    var topPadding = 12.0
    var bottomPadding = 8.0
    var sectionSpacing = 6.0
    var titleSize = 17.0
    var albumSize = 14.0
    var artistSize = 14.0
    var controlsSpacing = 8.0
    var skipIconSize = 15.0
    var playIconSize = 23.0
    var controlButtonWidth = 26.0
    var progressThin = 4.0
    var progressThick = 8.0
    // Calendar
    var calItemWidth = 42.0
    var calFocusSize = 26.0
    var calOtherSize = 15.0
    var calMonthSize = 22.0
    var calStripHeight = 54.0
    var calFocusGap = 10.0
    // Timer
    var timerButtonSize = 36.0
    /// Concentric with the capsule's 26 pt bottom corner: 26 − margin 8 = 18 → a full circle for a 36 pt button.
    var timerButtonRadius = 18.0
    /// Right and bottom margin; the bottom matches the other modules (8 pt).
    var timerEdgeMargin = 8.0
    var timerDividerMargin = 4.0
    // Compact capsule
    var iconMargin = 5.0
    var wingExtra = 0.0
    var swellWidth = 1.08
    var swellHeight = 1.22
    var peekExtra = 46.0
    /// Extra height for the one-line song info (the timer notice has two lines and uses `peekExtra`).
    var songInfoExtra = 28.0
    /// How far the capsule grows on one side while the previous / next icon shows.
    var stepGrow = 34.0
    /// The other side stretches a little too.
    var stepGrowOther = 8.0
    /// Distance between the three stages of the icon's step (appear, change, disappear).
    var stepSpacing = 27.0
    /// Size of the previous / next symbol relative to the cover.
    var stepIconScale = 0.5
    /// A fast flick counts this many times more per point of movement than a slow swipe.
    var swipeFastGain = 2.5
    /// Swipe speed (points per second) at which the full gain applies.
    var swipeFastSpeed = 1500.0
    // Animations
    var expandResponse = 0.5
    var expandDamping = 0.58
    var collapseResponse = 0.32
    var collapseDamping = 0.85
    var swellResponse = 0.3
    var swellDamping = 0.5
    var unswellResponse = 0.28
    var unswellDamping = 0.92
    var islandResponse = 0.42
    var islandDamping = 0.74
    var islandHoverScale = 1.07

    /// Changes whenever something that affects the panel geometry changes.
    var layoutSignature: [Double] {
        [
            cellWidth, contentInset, moduleGap, expandedContentHeight, wingExtra, swellWidth, swellHeight, peekExtra, songInfoExtra,
            expandedBottomInset,
        ]
    }
}

struct TuningParameter: Identifiable, @unchecked Sendable {
    let id: String
    let group: String
    let title: String
    let range: ClosedRange<Double>
    let keyPath: ReferenceWritableKeyPath<Tuning, Double>
}

extension Tuning {
    static let parameters: [TuningParameter] = [
        .init(id: "cellWidth", group: "大膠囊", title: "每格寬度", range: 40...110, keyPath: \.cellWidth),
        .init(id: "contentInset", group: "大膠囊", title: "左右內距", range: 4...40, keyPath: \.contentInset),
        .init(id: "dividerLengthRatio", group: "大膠囊", title: "分隔線長度(佔內容高度)", range: 0.4...1, keyPath: \.dividerLengthRatio),
        .init(id: "expandedBottomInset", group: "大膠囊", title: "下方留白(模組之下)", range: 0...40, keyPath: \.expandedBottomInset),
        .init(id: "moduleGap", group: "大膠囊", title: "模組間距", range: 0...40, keyPath: \.moduleGap),
        .init(id: "expandedContentHeight", group: "大膠囊", title: "內容高度", range: 110...240, keyPath: \.expandedContentHeight),
        .init(id: "topPadding", group: "媒體頁", title: "上方內距(離瀏海)", range: 0...40, keyPath: \.topPadding),
        .init(id: "bottomPadding", group: "媒體頁", title: "下方內距", range: 0...30, keyPath: \.bottomPadding),
        .init(id: "sectionSpacing", group: "媒體頁", title: "封面列與進度條間距", range: 0...24, keyPath: \.sectionSpacing),
        .init(id: "artSize", group: "媒體頁", title: "封面大小", range: 60...150, keyPath: \.artSize),
        .init(id: "artTextGap", group: "媒體頁", title: "封面與文字間距", range: 0...40, keyPath: \.artTextGap),
        .init(id: "textLineSpacing", group: "媒體頁", title: "文字行距", range: 0...12, keyPath: \.textLineSpacing),
        .init(id: "titleSize", group: "媒體頁", title: "歌名字級", range: 10...28, keyPath: \.titleSize),
        .init(id: "albumSize", group: "媒體頁", title: "專輯字級", range: 9...24, keyPath: \.albumSize),
        .init(id: "artistSize", group: "媒體頁", title: "藝人字級", range: 9...24, keyPath: \.artistSize),
        .init(id: "controlsSpacing", group: "控制項", title: "按鈕間距", range: 0...50, keyPath: \.controlsSpacing),
        .init(id: "skipIconSize", group: "控制項", title: "上/下一首圖示", range: 8...30, keyPath: \.skipIconSize),
        .init(id: "playIconSize", group: "控制項", title: "播放圖示", range: 10...40, keyPath: \.playIconSize),
        .init(id: "controlButtonWidth", group: "控制項", title: "按鈕點擊寬度", range: 16...50, keyPath: \.controlButtonWidth),
        .init(id: "progressThin", group: "進度條", title: "平常粗細", range: 1...12, keyPath: \.progressThin),
        .init(id: "progressThick", group: "進度條", title: "hover 粗細", range: 2...20, keyPath: \.progressThick),
        .init(id: "calItemWidth", group: "日曆", title: "日期間距", range: 28...70, keyPath: \.calItemWidth),
        .init(id: "calFocusSize", group: "日曆", title: "焦點日期字級", range: 16...40, keyPath: \.calFocusSize),
        .init(id: "calOtherSize", group: "日曆", title: "其他日期字級", range: 10...24, keyPath: \.calOtherSize),
        .init(id: "calMonthSize", group: "日曆", title: "月份字級", range: 14...34, keyPath: \.calMonthSize),
        .init(id: "calStripHeight", group: "日曆", title: "日期條高度", range: 36...80, keyPath: \.calStripHeight),
        .init(id: "calFocusGap", group: "日曆", title: "焦點兩側留白", range: 0...30, keyPath: \.calFocusGap),
        .init(id: "timerButtonSize", group: "計時器", title: "按鈕大小", range: 26...48, keyPath: \.timerButtonSize),
        .init(id: "timerButtonRadius", group: "計時器", title: "按鈕圓角", range: 4...24, keyPath: \.timerButtonRadius),
        .init(id: "timerDividerMargin", group: "計時器", title: "按鈕離分隔線", range: 0...30, keyPath: \.timerDividerMargin),
        .init(id: "timerEdgeMargin", group: "計時器", title: "按鈕離邊緣", range: 6...30, keyPath: \.timerEdgeMargin),
        .init(id: "iconMargin", group: "小膠囊", title: "圖示邊距", range: 2...16, keyPath: \.iconMargin),
        .init(id: "wingExtra", group: "小膠囊", title: "側翼額外寬度", range: -10...40, keyPath: \.wingExtra),
        .init(id: "swellWidth", group: "小膠囊", title: "膨脹寬度倍率", range: 1...1.4, keyPath: \.swellWidth),
        .init(id: "swellHeight", group: "小膠囊", title: "膨脹高度倍率", range: 1...1.8, keyPath: \.swellHeight),
        .init(id: "peekExtra", group: "小膠囊", title: "資訊態額外高度", range: 20...90, keyPath: \.peekExtra),
        .init(id: "songInfoExtra", group: "小膠囊", title: "歌曲資訊額外高度", range: 18...60, keyPath: \.songInfoExtra),
        .init(id: "stepGrow", group: "小膠囊", title: "切歌圖示膨脹寬度", range: 16...60, keyPath: \.stepGrow),
        .init(id: "stepGrowOther", group: "小膠囊", title: "切歌另一側膨脹寬度", range: 0...30, keyPath: \.stepGrowOther),
        .init(id: "stepSpacing", group: "小膠囊", title: "切歌圖示階段間距", range: 12...50, keyPath: \.stepSpacing),
        .init(id: "stepIconScale", group: "小膠囊", title: "切歌圖示大小(相對封面)", range: 0.15...0.9, keyPath: \.stepIconScale),
        .init(id: "swipeFastGain", group: "小膠囊", title: "快滑時距離放大倍率", range: 1...5, keyPath: \.swipeFastGain),
        .init(id: "swipeFastSpeed", group: "小膠囊", title: "快滑速度(pt/s)", range: 600...4000, keyPath: \.swipeFastSpeed),
        .init(id: "expandResponse", group: "動畫", title: "展開 response", range: 0.1...1.2, keyPath: \.expandResponse),
        .init(id: "expandDamping", group: "動畫", title: "展開 damping", range: 0.2...1, keyPath: \.expandDamping),
        .init(id: "collapseResponse", group: "動畫", title: "收合 response", range: 0.1...1.2, keyPath: \.collapseResponse),
        .init(id: "collapseDamping", group: "動畫", title: "收合 damping", range: 0.2...1, keyPath: \.collapseDamping),
        .init(id: "swellResponse", group: "動畫", title: "膨脹 response", range: 0.1...1, keyPath: \.swellResponse),
        .init(id: "swellDamping", group: "動畫", title: "膨脹 damping", range: 0.2...1, keyPath: \.swellDamping),
        .init(id: "unswellResponse", group: "動畫", title: "縮回 response", range: 0.1...1, keyPath: \.unswellResponse),
        .init(id: "unswellDamping", group: "動畫", title: "縮回 damping", range: 0.2...1, keyPath: \.unswellDamping),
        .init(id: "islandResponse", group: "動態島", title: "分島 response", range: 0.15...1, keyPath: \.islandResponse),
        .init(id: "islandDamping", group: "動態島", title: "分島 damping", range: 0.3...1, keyPath: \.islandDamping),
        .init(id: "islandHoverScale", group: "動態島", title: "副島 hover 放大", range: 1...1.3, keyPath: \.islandHoverScale),
    ]

    /// Reference defaults captured at launch, for the "reset" button.
    static let defaults: [String: Double] = {
        let fresh = Tuning(loadSaved: false)
        return Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, fresh[keyPath: $0.keyPath]) })
    }()

    /// Saved values override the built-in defaults; only values that differ are stored.
    func load(defaults store: UserDefaults = .standard) {
        for parameter in Self.parameters {
            if let value = store.object(forKey: Self.keyPrefix + parameter.id) as? Double, value.isFinite {
                // Clamp so a corrupt preference can never produce an unusable layout.
                self[keyPath: parameter.keyPath] = min(max(value, parameter.range.lowerBound), parameter.range.upperBound)
            }
        }
    }

    func save(defaults store: UserDefaults = .standard) {
        for parameter in Self.parameters {
            let value = self[keyPath: parameter.keyPath]
            if abs(value - (Self.defaults[parameter.id] ?? value)) < 0.0005 {
                store.removeObject(forKey: Self.keyPrefix + parameter.id)
            } else {
                store.set(value, forKey: Self.keyPrefix + parameter.id)
            }
        }
    }

    func resetAll(defaults store: UserDefaults = .standard) {
        for parameter in Self.parameters {
            guard let value = Self.defaults[parameter.id] else { continue }
            self[keyPath: parameter.keyPath] = value
        }
        save(defaults: store)
    }

    /// Plain text of every value, to paste back into the chat.
    func report() -> String {
        Self.parameters
            .map { "\($0.id) = \(String(format: "%.3f", self[keyPath: $0.keyPath]))" }
            .joined(separator: "\n")
    }
}
