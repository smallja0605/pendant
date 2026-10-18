import SwiftUI

/// The tabs of the settings window, in display order (requirements 7). "外觀" (Liquid Glass) exists only on macOS 26+.
/// The raw values are kept stable: debug hooks and the persisted selection refer to them.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, activities, virtualNotch, system, pendant, shelf, gestures, statusBar, liquid, permissions, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "一般"
        case .activities: "動態島"
        case .virtualNotch: "虛擬瀏海"
        case .system: "即時提示"
        case .pendant: "小工具"
        case .shelf: "檔案中轉站"
        case .gestures: "手勢操控"
        case .statusBar: "狀態列"
        case .liquid: "外觀"
        case .permissions: "隱私"
        case .about: "關於"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .activities: "capsule"
        case .virtualNotch: "rectangle.topthird.inset.filled"
        case .system: "switch.2"
        case .pendant: "square.grid.2x2"
        case .shelf: "tray.full"
        case .gestures: "hand.draw"
        case .statusBar: "menubar.rectangle"
        case .liquid: "paintpalette"
        case .permissions: "hand.raised"
        case .about: "info.circle"
        }
    }

    /// Tabs that exist on this system.
    static var available: [SettingsTab] {
        allCases.filter { $0 != .liquid || LiquidGlass.isAvailable }
    }
}

/// Selected tab, shared between the toolbar (AppKit) and the content (SwiftUI).
@MainActor
@Observable
final class SettingsSelection {
    var tab: SettingsTab

    init(tab: SettingsTab = .general) { self.tab = tab }
}

/// What the custom traffic lights do (the system's are hidden: they would sit across the sidebar's edge).
enum SettingsWindowAction { case close, minimize, zoom }

/// How the sidebar looks, following Apple's two designs: macOS 26 floats it as a glass card inset from the window's edges,
/// macOS 27 (and earlier systems) draw it flush against the edge as a frosted material.
private enum SidebarStyle {
    case floatingGlass, flushFrosted

    static var current: SidebarStyle {
        if #available(macOS 27, *) { return .flushFrosted }
        if #available(macOS 26, *), LiquidGlass.isEnabled { return .floatingGlass }
        return .flushFrosted
    }
}

struct SettingsView: View {
    @State private var titleScrolledAway = false
    let selection: SettingsSelection
    var onShowTour: () -> Void = {}
    var onWindowAction: (SettingsWindowAction) -> Void = { _ in }

    var body: some View {
        let style = SidebarStyle.current
        HStack(spacing: 0) {
            SettingsSidebar(selection: selection, style: style, onShowTour: onShowTour, onWindowAction: onWindowAction)
                .frame(width: style == .floatingGlass ? 214 : 224)
                .padding(style == .floatingGlass ? EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 0) : EdgeInsets())
            Group {
                switch selection.tab {
                case .general: GeneralSettingsView()
                case .statusBar: StatusBarSettingsView()
                case .liquid: LiquidSettingsView()
                case .gestures: GesturesSettingsView()
                case .activities: ActivitiesSettingsView()
                case .virtualNotch: VirtualNotchSettingsView()
                case .system: SystemFeaturesSettingsView()
                case .pendant: PendantSettingsView()
                case .shelf: ShelfSettingsView()
                case .permissions: PermissionsSettingsView()
                case .about: AboutSettingsView()
                }
            }
            // The page title is the first thing in the page's own scroll content (see `SettingsTitleHeader`), and the page
            // is transparent: no header band, no seam; the glass window shows through the cards.
            .environment(\.settingsTitle, selection.tab.title)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ScrollPastTitleObserver { titleScrolledAway = $0 })
            .overlay(alignment: .top) { TitleBand(title: selection.tab.title, visible: titleScrolledAway) }
            .overlay(alignment: .bottom) { EdgeBlur(edge: .bottom, height: 22) }
            .id(selection.tab)
            .onChange(of: selection.tab) { _, _ in titleScrolledAway = false }
        }
        .frame(minWidth: 820, idealWidth: 900, maxWidth: .infinity, minHeight: 600, idealHeight: 820, maxHeight: .infinity)
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
                Color.black.opacity(0.28) // a little darker, like a dark glass pane
            }
            .ignoresSafeArea()
        )
        .ignoresSafeArea()
    }
}

private struct SettingsTitleKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var settingsTitle: String {
        get { self[SettingsTitleKey.self] }
        set { self[SettingsTitleKey.self] = newValue }
    }
}

/// The big page title ("一般", "關於"…), the first row of every settings page: it scrolls away with the content.
struct SettingsTitleHeader: View {
    @Environment(\.settingsTitle) private var title

    var body: some View {
        Section {} header: {
            Text(title)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.primary)
                .textCase(nil)
                .padding(.top, 34)
                .padding(.bottom, 4)
        }
    }
}

/// Left column: traffic lights, app name, the pages with their icons, and the tour at the bottom.
private struct SettingsSidebar: View {
    let selection: SettingsSelection
    let style: SidebarStyle
    let onShowTour: () -> Void
    let onWindowAction: (SettingsWindowAction) -> Void

    @Namespace private var glassSpace

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TrafficLights(onAction: onWindowAction)
                .padding(.top, 8).padding(.leading, 6)
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                Text("Pendant").font(.system(size: 19, weight: .bold))
            }
            .padding(.top, 20)
            .padding(.bottom, 14)
            .padding(.horizontal, 10)
            rows
            Spacer(minLength: 0)
            SimulationButton()
            Button(action: onShowTour) {
                Label("重新觀看導覽", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(
            style == .floatingGlass
                ? EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
                : EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        )
        .frame(maxHeight: .infinity, alignment: .top)
        .modifier(SidebarBackground(style: style))
    }

    @ViewBuilder private var rows: some View {
        if #available(macOS 26, *), LiquidGlass.isEnabled {
            // The selection is one Liquid Glass plate (shared glass ID), so choosing another page morphs it over to that row.
            GlassEffectContainer(spacing: 4) {
                VStack(alignment: .leading, spacing: 4) { ForEach(SettingsTab.available) { row($0, glass: true) } }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) { ForEach(SettingsTab.available) { row($0, glass: false) } }
        }
    }

    private func row(_ tab: SettingsTab, glass: Bool) -> some View {
        let selected = selection.tab == tab
        return Button {
            withAnimation(.bouncy(duration: 0.4, extraBounce: 0.1)) { selection.tab = tab }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.symbolName).frame(width: 22).font(.system(size: 15, weight: .medium))
                Text(tab.title).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .modifier(RowSelection(selected: selected, glass: glass, namespace: glassSpace))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// The selected row's plate: Liquid Glass (macOS 26+) with a shared ID, or a plain translucent fill.
private struct RowSelection: ViewModifier {
    let selected: Bool
    let glass: Bool
    let namespace: Namespace.ID

    @ViewBuilder func body(content: Content) -> some View {
        if glass, #available(macOS 26, *) {
            if selected {
                content
                    .glassEffect(.regular.tint(.white.opacity(0.10)), in: .rect(cornerRadius: 11))
                    .glassEffectID("selection", in: namespace)
            } else {
                content
            }
        } else {
            content.background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selected ? Color.white.opacity(0.14) : .clear))
        }
    }
}

private struct SidebarBackground: ViewModifier {
    let style: SidebarStyle

    @ViewBuilder func body(content: Content) -> some View {
        switch style {
        case .floatingGlass:
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: .rect(cornerRadius: 24))
            } else {
                content
            }
        case .flushFrosted:
            content.background(VisualEffectBackground(material: .sidebar, blending: .behindWindow).ignoresSafeArea())
        }
    }
}

/// The window's three buttons drawn in the sidebar: close, minimise, zoom; their glyphs show while the pointer is over them.
private struct TrafficLights: View {
    let onAction: (SettingsWindowAction) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            light(.red, symbol: "xmark", action: .close)
            light(.yellow, symbol: "minus", action: .minimize)
            light(.green, symbol: "plus", action: .zoom)
        }
        .onHover { hovering = $0 }
    }

    private func light(_ color: Color, symbol: String, action: SettingsWindowAction) -> some View {
        Button { onAction(action) } label: {
            Circle().fill(color).frame(width: 12, height: 12)
                .overlay {
                    Image(systemName: symbol).font(.system(size: 7, weight: .black)).foregroundStyle(.black.opacity(0.55))
                        .opacity(hovering ? 1 : 0)
                }
        }
        .buttonStyle(.plain)
    }
}

/// An `NSVisualEffectView` as a SwiftUI background (blur of what is behind the window).
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

extension View {
    /// An explanation that belongs to this control: it sits under it *inside the same row*, so the form draws no separator
    /// line between them (a separate note row always got one). `nil` = no note.
    func settingNote(_ text: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            frame(maxWidth: .infinity, alignment: .leading)
            if let text { Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}
