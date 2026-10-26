import Foundation
import Observation
import SwiftUI

/// Owns the module instances and the user's choices: which are enabled, their order and their width in
/// cells. Everything is persisted immediately and reflected live in the capsule (requirements 4.10).
@MainActor
@Observable
final class ModuleRegistry {
    static let layoutKey = "modules.layout"
    /// The app's registry (module instances are registered by the window controller at launch).
    static let shared = ModuleRegistry()

    private(set) var state: ModuleLayoutState
    /// Which tab of the open capsule is showing (its id; falls back to the first tab that has something to show).
    var selectedTabID = TabConfig.mainID
    /// The module shown alone (its detailed page) in the open capsule; nil = the whole tab. Not saved: the capsule closes it.
    var focusedModuleID: String?
    /// Extra height the user dragged onto the detailed reminders page (points); back to 0 whenever that page opens or closes.
    var focusExtraHeight: CGFloat = 0
    var isResizingFocus = false
    /// The share of the detailed reminders page the list takes (the rest is the new-item box); 0.5 = 5 : 5. Back to 0.5 like the height.
    var focusSplit: CGFloat = 0.5
    /// True while a detailed page is opening or closing (modules move under a resting pointer: hover effects hold off).
    private(set) var focusTransitioning = false

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var focusTransitionEnd: Task<Void, Never>?
    @ObservationIgnored private var instances: [String: any PendantModule] = [:]

    init(defaults: UserDefaults = .standard, modules: [any PendantModule] = []) {
        self.defaults = defaults
        state = Self.load(from: defaults)
        for module in modules { instances[module.id] = module }
    }

    // MARK: Queries

    var order: [String] { state.order }
    var descriptors: [ModuleDescriptor] { state.order.compactMap(ModuleDescriptor.descriptor(for:)) }
    /// Enabled modules in display order.
    var activeIDs: [String] { state.order.filter { state.enabled.contains($0) } }

    // MARK: Tabs

    var tabs: [TabConfig] { state.tabs }

    /// Enabled modules of a tab, in the global display order.
    func modules(in tab: TabConfig) -> [String] {
        state.order.filter { tab.moduleIDs.contains($0) && state.enabled.contains($0) }
    }

    /// Tabs that have something to show, in display order.
    var availableTabs: [TabConfig] { state.tabs.filter { !modules(in: $0).isEmpty } }

    /// The tab actually shown.
    var effectiveTab: TabConfig? { availableTabs.first { $0.id == selectedTabID } ?? availableTabs.first }

    /// First visible tab that contains `moduleID` (used to jump to a module from an island).
    func tabID(containing moduleID: String) -> String? {
        availableTabs.first { $0.moduleIDs.contains(moduleID) }?.id
    }

    /// Switches the tab (cross-fade).
    func setTab(_ id: String) {
        guard id != effectiveTab?.id else { return }
        Task { @MainActor in
            withAnimation(AnimationTokens.expand) { selectedTabID = id }
        }
    }

    /// Keyboard: the next (+1) or previous (-1) tab; stops at the ends.
    func stepTab(by delta: Int) {
        let tabs = availableTabs
        guard let current = tabs.firstIndex(where: { $0.id == effectiveTab?.id }) else { return }
        let target = min(max(current + delta, 0), tabs.count - 1)
        setTab(tabs[target].id)
    }

    /// Keyboard: ⌘1…⌘9 jump to the n-th tab (1-based).
    func selectTab(number: Int) {
        let tabs = availableTabs
        guard tabs.indices.contains(number - 1) else { return }
        setTab(tabs[number - 1].id)
    }

    @discardableResult
    func addTab(title: String) -> String {
        let id = "tab-" + UUID().uuidString.prefix(8).lowercased()
        state.tabs.append(TabConfig(id: id, title: title, moduleIDs: []))
        didChange()
        return id
    }

    /// Removes a tab (the last one cannot be removed).
    func removeTab(_ id: String) {
        guard state.tabs.count > 1 else { return }
        state.tabs.removeAll { $0.id == id }
        didChange()
    }

    func renameTab(_ id: String, to title: String) {
        guard let index = state.tabs.firstIndex(where: { $0.id == id }) else { return }
        state.tabs[index].title = title
        didChange()
    }

    /// Puts a module into a tab or takes it out of it.
    func setModule(_ moduleID: String, in tabID: String, _ included: Bool) {
        guard let index = state.tabs.firstIndex(where: { $0.id == tabID }) else { return }
        state.tabs[index].moduleIDs.removeAll { $0 == moduleID }
        if included { state.tabs[index].moduleIDs.append(moduleID) }
        didChange()
    }

    /// The one tab a module lives in (the first that holds it), as the settings show it.
    func primaryTabID(of moduleID: String) -> String? {
        state.tabs.first { $0.moduleIDs.contains(moduleID) }?.id
    }

    /// Moves a module to a single tab: it leaves every other tab.
    func moveModule(_ moduleID: String, toTab tabID: String) {
        guard state.tabs.contains(where: { $0.id == tabID }) else { return }
        for index in state.tabs.indices {
            state.tabs[index].moduleIDs.removeAll { $0 == moduleID }
            if state.tabs[index].id == tabID { state.tabs[index].moduleIDs.append(moduleID) }
        }
        didChange()
    }

    func tabs(containing moduleID: String) -> [String] {
        state.tabs.filter { $0.moduleIDs.contains(moduleID) }.map(\.id)
    }

    func isEnabled(_ id: String) -> Bool { state.enabled.contains(id) }

    func cells(for id: String) -> Int {
        state.cells[id] ?? ModuleDescriptor.descriptor(for: id)?.cells.default ?? 1
    }

    func module(for id: String) -> (any PendantModule)? { instances[id] }

    func register(_ modules: [any PendantModule]) {
        for module in modules { instances[module.id] = module }
    }

    /// Changes whenever something that affects the capsule's width / content changes.
    var layoutSignature: [String] {
        activeIDs + activeIDs.map { String(cells(for: $0)) }
            + ["focus\(focusedModuleID ?? "")", "tab\(effectiveTab?.id ?? "")", "h\(Int(focusExtraHeight))"]
            + state.tabs.map { $0.id + ($0.moduleIDs.joined(separator: ",")) }
    }

    /// Module ids shown right now.
    var currentPageIDs: [String] {
        let page = effectiveTab.map(modules(in:)) ?? []
        if let focused = focusedModuleID, page.contains(focused) { return [focused] }
        return page
    }

    /// Width of a module on the current page: its own, or the detailed page's while it is shown alone.
    func displayCells(for id: String) -> Int {
        focusedModuleID == id ? (module(for: id)?.focusCells ?? cells(for: id)) : cells(for: id)
    }

    /// The detailed reminders page starts (and returns) at the height and split chosen in 設定 › 獨立膠囊 › 待辦事項.
    private func applyFocusDefaults() {
        let settings = FocusCapsuleSettings.shared
        focusExtraHeight = CGFloat(settings.remindersExtraHeight)
        focusSplit = CGFloat(settings.remindersSplit) / 100
    }

    func focus(_ id: String) {
        guard focusedModuleID != id else { return }
        applyFocusDefaults()
        beginFocusTransition()
        withAnimation(AnimationTokens.expand) { focusedModuleID = id }
    }

    func unfocus() {
        guard focusedModuleID != nil else { return }
        applyFocusDefaults()
        Log.app.info("detail page closed, from: \(Log.callers(), privacy: .public)")
        beginFocusTransition()
        withAnimation(AnimationTokens.expand) { focusedModuleID = nil }
    }

    private func beginFocusTransition() {
        focusTransitioning = true
        focusTransitionEnd?.cancel()
        focusTransitionEnd = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.focusTransitioning = false
        }
    }

    // MARK: Changes

    func setEnabled(_ id: String, _ enabled: Bool) {
        guard ModuleDescriptor.descriptor(for: id)?.selectable == true else { return }
        if enabled { state.enabled.insert(id) } else { state.enabled.remove(id) }
        didChange()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        state.order.move(fromOffsets: source, toOffset: destination)
        didChange()
    }

    /// Drag-and-drop reorder in the preview bar: puts `id` right before `target`.
    func move(_ id: String, before target: String) {
        guard id != target, let from = state.order.firstIndex(of: id), let to = state.order.firstIndex(of: target) else { return }
        state.order.move(fromOffsets: IndexSet(integer: from), toOffset: from < to ? to + 1 : to)
        didChange()
    }

    /// Moves `id` one place within the *enabled* modules (what the capsule shows): -1 = earlier, +1 = later.
    /// Returns false when it is already at that end.
    @discardableResult
    func shiftActive(_ id: String, by delta: Int) -> Bool {
        let active = activeIDs
        guard let index = active.firstIndex(of: id), active.indices.contains(index + delta) else { return false }
        let neighbour = active[index + delta]
        guard let from = state.order.firstIndex(of: id), let to = state.order.firstIndex(of: neighbour) else { return false }
        state.order.move(fromOffsets: IndexSet(integer: from), toOffset: delta > 0 ? to + 1 : to)
        didChange()
        return true
    }

    /// Like `shiftActive`, but among the modules of one tab (`ids`, in display order).
    @discardableResult
    func shift(_ id: String, by delta: Int, within ids: [String]) -> Bool {
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + delta),
              let from = state.order.firstIndex(of: id), let to = state.order.firstIndex(of: ids[index + delta]) else { return false }
        state.order.move(fromOffsets: IndexSet(integer: from), toOffset: delta > 0 ? to + 1 : to)
        didChange()
        return true
    }

    /// Moves `id` to `index` within the full ordered list (used by the settings list while dragging).
    @discardableResult
    func move(_ id: String, toIndex index: Int) -> Bool {
        guard let from = state.order.firstIndex(of: id), state.order.indices.contains(index), from != index else { return false }
        state.order.move(fromOffsets: IndexSet(integer: from), toOffset: index > from ? index + 1 : index)
        didChange()
        return true
    }

    func setCells(_ id: String, _ cells: Int) {
        guard let descriptor = ModuleDescriptor.descriptor(for: id) else { return }
        state.cells[id] = min(max(cells, descriptor.cells.range.lowerBound), descriptor.cells.range.upperBound)
        didChange()
    }

    func resetToDefaults() {
        state = ModuleLayoutState.default
        didChange()
    }

    #if DEBUG
    /// Visual checks only: enables exactly these modules without saving anything.
    func debugSetEnabled(_ ids: [String]) {
        state.enabled = Set(ids).intersection(ModuleDescriptor.all.filter(\.selectable).map(\.id))
    }
    #endif

    // MARK: Persistence

    private func didChange() {
        state = state.normalized()
        if let data = try? JSONEncoder().encode(Stored(state)) {
            defaults.set(data, forKey: Self.layoutKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> ModuleLayoutState {
        guard let data = defaults.data(forKey: layoutKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return ModuleLayoutState.default }
        return stored.state.normalized()
    }

    private struct Stored: Codable {
        var order: [String]
        var enabled: [String]
        var cells: [String: Int]
        /// Missing in data saved by older versions (then nothing counts as seen, so new defaults apply).
        var seenImplemented: [String]?
        /// Missing in data saved before tabs existed (then the default tabs apply).
        var tabs: [TabConfig]?

        init(_ state: ModuleLayoutState) {
            order = state.order
            enabled = state.enabled.sorted()
            cells = state.cells
            seenImplemented = state.seenImplemented.sorted()
            tabs = state.tabs
        }

        var state: ModuleLayoutState {
            // Data from before `seenImplemented` existed: only media was implemented back then.
            ModuleLayoutState(order: order, enabled: Set(enabled), cells: cells,
                              seenImplemented: Set(seenImplemented ?? ["media"]), tabs: tabs ?? TabConfig.defaults)
        }
    }
}
