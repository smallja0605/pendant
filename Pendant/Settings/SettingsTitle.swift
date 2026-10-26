import SwiftUI

/// The page title of the settings window: it starts as the big heading at the top of the page's own content and, as the page scrolls,
/// shrinks while it rises and stays pinned to the top (like a Finder window's title), with the content fading out underneath it.
///
/// The heading inside the page only *measures* where the big title sits at rest (`TitleRestKey`, invisible once measured);
/// the visible title is `PageTitleOverlay`, drawn over the page from that frame and the scroll offset.
enum SettingsSpace { static let settings = "settingsPage" } // the page area of the settings window (not 小工具 `PageSpace`)

struct TitleRestKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = value ?? nextValue() }
}

private struct TitleHiddenKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// The overlay draws the title, so the one inside the page must not show.
    var settingsTitleHidden: Bool {
        get { self[TitleHiddenKey.self] }
        set { self[TitleHiddenKey.self] = newValue }
    }
}

/// The big heading in a page: the size and the place of the title at rest.
struct SettingsTitleText: View {
    let title: String
    @Environment(\.settingsTitleHidden) private var hidden

    var body: some View {
        Text(loc(title))
            .font(.system(size: PageTitleOverlay.bigSize, weight: .bold))
            .foregroundStyle(.primary)
            .textCase(nil)
            .opacity(hidden ? 0 : 1)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: TitleRestKey.self, value: proxy.frame(in: .named(SettingsSpace.settings)))
            })
    }
}

/// The visible title, from rest (big, scrolling with the page) to pinned (small, at the top), plus the fade under it.
struct PageTitleOverlay: View {
    let title: String
    let rest: CGRect
    let offset: CGFloat

    static let bigSize: CGFloat = 30
    static let pinnedSize: CGFloat = 17
    private static let pinnedTop: CGFloat = 14
    private static let bandHeight: CGFloat = 64

    /// 0 at rest, 1 once the title has reached the top.
    private var progress: CGFloat {
        let travel = max(rest.minY - Self.pinnedTop, 1)
        return min(max(offset / travel, 0), 1)
    }

    var body: some View {
        let pinning = progress
        let scale = 1 - (1 - Self.pinnedSize / Self.bigSize) * pinning
        let top = max(rest.minY - offset, Self.pinnedTop)
        ZStack(alignment: .topLeading) {
            // The frosted band under the pinned title: content passing beneath it dissolves instead of being cut off.
            ZStack {
                VisualEffectBackground(material: .menu, blending: .withinWindow)
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                                 .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
            }
            .frame(height: Self.bandHeight)
            .opacity(min(max((pinning - 0.5) * 2, 0), 1))
            Text(loc(title))
                .font(.system(size: Self.bigSize, weight: .bold))
                .fixedSize()
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: rest.minX, y: top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Quit and restart, in one Liquid Glass capsule of buttons (like the button groups in a Finder window's toolbar).
struct AppControlButtons: View {
    var body: some View {
        if #available(macOS 26, *), LiquidGlass.isEnabled {
            GlassEffectContainer { group.glassEffect(.regular.interactive(), in: .capsule) }
        } else {
            group.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        }
    }

    private var group: some View {
        HStack(spacing: 2) {
            GroupButton(symbol: "power", help: "結束 Pendant") { AppControl.quit() }
            GroupButton(symbol: "arrow.clockwise", help: "重新啟動") { AppControl.restart() }
        }
        .padding(3)
    }
}

private struct GroupButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 34, height: 28)
                .background(Capsule().fill(.white.opacity(hovering ? 0.16 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(loc(help))
        .accessibilityLabel(loc(help))
    }
}
