import Foundation
import Testing
@testable import Pendant

struct ModuleLayoutStateTests {
    @Test func defaultsFollowTheRequirementsOrder() {
        let state = ModuleLayoutState.default
        #expect(state.order == ["media", "notes", "reminders", "calendar", "timer", "mirror", "shelf", "shortcuts", "quickApps"])
        #expect(state.enabled == ["media", "notes", "reminders", "calendar", "timer", "mirror", "shelf"]) // implemented + default-on modules
    }

    @Test func normalizeDropsUnknownAddsNewAndRepairsCells() {
        let stale = ModuleLayoutState(order: ["timer", "ghost", "media", "timer"], enabled: ["media", "ghost", "quickApps"],
                                      cells: ["media": 99, "ghost": 3, "mirror": 0],
                                      seenImplemented: Set(ModuleDescriptor.all.filter(\.implemented).map(\.id)))
        let fixed = stale.normalized()
        #expect(fixed.order.prefix(2) == ["timer", "media"])
        #expect(Set(fixed.order) == Set(ModuleDescriptor.all.map(\.id)))
        #expect(fixed.order.count == ModuleDescriptor.all.count)
        #expect(fixed.enabled == ["media"])                 // unknown + non-selectable removed
        #expect(fixed.cells["media"] == 10)                 // clamped to range
        #expect(fixed.cells["mirror"] == 2)
        #expect(fixed.cells["ghost"] == nil)
    }
}

struct ModulePagerTests {
    @Test func everythingFitsOnOnePage() {
        let pages = ModulePager.pages(cellCounts: [5, 4], cellWidth: 72, gap: 12, inset: 18, maxWidth: 1000)
        #expect(pages == [[0, 1]])
    }

    @Test func overflowStartsANewPage() {
        // 5+4 cells = 648 + gap 12 + inset 36 = 696 > 600
        let pages = ModulePager.pages(cellCounts: [5, 4, 2], cellWidth: 72, gap: 12, inset: 18, maxWidth: 600)
        #expect(pages == [[0], [1, 2]])
    }

    @Test func aModuleWiderThanTheScreenGetsItsOwnPage() {
        let pages = ModulePager.pages(cellCounts: [10, 2], cellWidth: 72, gap: 12, inset: 18, maxWidth: 400)
        #expect(pages == [[0], [1]])
    }

    @Test func contentWidthIncludesGapsAndInsets() {
        let width = ModulePager.contentWidth(cellCounts: [5, 4], cellWidth: 72, gap: 12, inset: 18)
        #expect(width == 696, "width was \(width)")
        #expect(ModulePager.contentWidth(cellCounts: [], cellWidth: 72, gap: 12, inset: 18) == 0)
    }
}

@MainActor
struct ModuleRegistryTests {
    private func registry(_ store: UserDefaults) -> ModuleRegistry { ModuleRegistry(defaults: store) }
    private func store() -> UserDefaults { UserDefaults(suiteName: "registry-tests-\(UUID().uuidString)")! }

    @Test func changesPersistAcrossInstances() {
        let defaults = store()
        let first = registry(defaults)
        first.setEnabled("notes", true)
        first.setEnabled("media", false)
        first.move(fromOffsets: IndexSet(integer: 4), toOffset: 0) // timer to the front
        first.setCells("media", 7)

        let second = registry(defaults)
        #expect(second.isEnabled("notes"))
        #expect(!second.isEnabled("media"))
        #expect(second.order.first == "timer")
        #expect(second.cells(for: "media") == 7)
        #expect(second.activeIDs == ["timer", "notes", "reminders", "calendar", "mirror", "shelf"].filter { second.isEnabled($0) })
    }

    @Test func quickAppsCannotBeEnabled() {
        let reg = registry(store())
        reg.setEnabled("quickApps", true)
        #expect(!reg.isEnabled("quickApps"))
    }

    @Test func cellCountsAreClamped() {
        let reg = registry(store())
        reg.setCells("mirror", 100)
        #expect(reg.cells(for: "mirror") == 6)
        reg.setCells("mirror", -3)
        #expect(reg.cells(for: "mirror") == 2)
    }

    @Test func defaultTabsAreFunctionNotesAndShelf() {
        let reg = registry(store())
        #expect(reg.tabs.map(\.title) == ["小工具", "筆記", "檔案中轉站"])
        #expect(reg.availableTabs.count == 3)
        #expect(reg.modules(in: reg.tabs[0]) == ["media", "reminders", "calendar", "timer", "mirror"])
        #expect(reg.currentPageIDs == reg.modules(in: reg.tabs[0]))
        reg.setEnabled("notes", false)
        #expect(reg.availableTabs.map(\.id) == [TabConfig.mainID, "shelf"]) // an empty tab is not offered
    }

    @Test func tabsCanBeAddedRenamedFilledAndRemoved() {
        let defaults = store()
        let reg = registry(defaults)
        let id = reg.addTab(title: "工作")
        #expect(reg.availableTabs.map(\.id).contains(id) == false) // empty
        reg.setModule("timer", in: id, true)
        reg.setModule("calendar", in: id, true) // a module may be in several tabs
        #expect(reg.modules(in: reg.tabs.first { $0.id == id }!) == ["calendar", "timer"])
        #expect(reg.tabs(containing: "timer").sorted() == [TabConfig.mainID, id].sorted())
        reg.renameTab(id, to: "專注")
        reg.setModule("timer", in: id, false)
        #expect(reg.tabs.first { $0.id == id }?.moduleIDs == ["calendar"])

        let again = registry(defaults) // persisted
        #expect(again.tabs.first { $0.id == id }?.title == "專注")
        again.removeTab(id)
        #expect(again.tabs.map(\.id) == [TabConfig.mainID, "notes", "shelf"])
        for tab in again.tabs.dropFirst(2) { again.removeTab(tab.id) }
        again.removeTab("notes")
        #expect(again.tabs.count == 1) // the last tab stays
        again.removeTab(TabConfig.mainID)
        #expect(again.tabs.count == 1)
    }

    @Test func aTabWhoseModulesAreOffFallsBack() {
        let reg = registry(store())
        reg.selectedTabID = "notes"
        #expect(reg.effectiveTab?.id == "notes" && reg.currentPageIDs == ["notes"])
        reg.setEnabled("notes", false)
        #expect(reg.effectiveTab?.id == TabConfig.mainID)
        #expect(reg.tabID(containing: "shelf") == "shelf")
    }

    @Test func resetRestoresDefaults() {
        let reg = registry(store())
        reg.setEnabled("notes", true)
        reg.resetToDefaults()
        #expect(reg.state == ModuleLayoutState.default)
    }

    @Test func corruptStoredDataFallsBackToDefaults() {
        let defaults = store()
        defaults.set(Data([1, 2, 3]), forKey: ModuleRegistry.layoutKey)
        #expect(registry(defaults).state == ModuleLayoutState.default)
    }
}

@MainActor
struct AppSettingsTests {
    private func store() -> UserDefaults { UserDefaults(suiteName: "settings-tests-\(UUID().uuidString)")! }

    @Test func defaultsMatchTheRequirements() {
        let settings = AppSettings(defaults: store())
        #expect(settings.hoverEffectEnabled)
        #expect(settings.hoverExpandMode == .off)
        #expect(settings.hoverDelay == 0.3)
        #expect(settings.collapseDelay == 0.3)
        #expect(settings.hotkeyEnabled)
        #expect(settings.hotkeyKeyCode == 49)
        #expect(settings.activityPriority == ["media", "timer", "stopwatch", "reminders", "shelf"])
        #expect(settings.notchWidthAdjust == 0)
    }

    @Test func activitiesAddedLaterJoinACustomOrder() {
        let defaults = store()
        let first = AppSettings(defaults: defaults)
        first.activityPriority = ["reminders", "timer", "media"]
        let second = AppSettings(defaults: defaults)
        #expect(second.activityPriority == ["reminders", "timer", "stopwatch", "media", "shelf"])
    }

    @Test func everyChangeIsPersistedImmediately() {
        let defaults = store()
        let first = AppSettings(defaults: defaults)
        first.hoverExpandMode = .always
        first.hoverDelay = 0.8
        first.swipeReversed = true
        first.notchWidthAdjust = -6
        first.activityPriority = ["timer", "media", "stopwatch", "reminders", "shelf"]
        first.disabledActivities = ["timer"]
        first.mediaSourcePreference = .spotify
        first.shelfAutoClear = .afterDays

        let second = AppSettings(defaults: defaults)
        #expect(second.hoverExpandMode == .always)
        #expect(second.hoverDelay == 0.8)
        #expect(second.swipeReversed)
        #expect(second.notchWidthAdjust == -6)
        #expect(second.activityPriority == ["timer", "media", "stopwatch", "reminders", "shelf"])
        #expect(second.disabledActivities == ["timer"])
        #expect(second.mediaSourcePreference == .spotify)
        #expect(second.shelfAutoClear == .afterDays)
    }

    @Test func hotkeyDisplayAndModifierConversion() {
        #expect(GlobalHotkey.displayString(keyCode: 49, modifiers: 1 << 19) == "⌥Space")
        #expect(GlobalHotkey.displayString(keyCode: 40, modifiers: (1 << 20) | (1 << 17)) == "⇧⌘K")
        #expect(GlobalHotkey.carbonModifiers(from: 0) == 0)
        #expect(GlobalHotkey.carbonModifiers(from: 1 << 19) != 0)
    }
}

struct NewlyImplementedModuleTests {
    @Test func aModuleImplementedAfterSavingIsEnabledOnceForExistingUsers() {
        // Saved when only media was implemented, the user turned nothing on.
        let old = ModuleLayoutState(order: ModuleDescriptor.all.map(\.id), enabled: ["media"], cells: [:], seenImplemented: ["media"])
        let migrated = old.normalized()
        #expect(migrated.enabled == ["media", "notes", "reminders", "calendar", "timer", "mirror", "shelf"])
        // Saving again records them as seen, so switching one off sticks.
        var again = migrated
        again.enabled.remove("calendar")
        #expect(again.normalized().enabled == ["media", "notes", "reminders", "timer", "mirror", "shelf"])
    }
}

@MainActor
struct ModuleReorderTests {
    private func registry() -> ModuleRegistry {
        let reg = ModuleRegistry(defaults: UserDefaults(suiteName: "reorder-tests-\(UUID().uuidString)")!)
        for id in ["media", "notes", "reminders", "calendar", "timer", "mirror", "shelf"] { reg.setEnabled(id, false) }
        for id in ["media", "calendar", "mirror"] { reg.setEnabled(id, true) }
        return reg
    }

    @Test func shiftActiveSwapsWithTheNextEnabledModuleSkippingDisabledOnes() {
        let reg = registry()
        #expect(reg.activeIDs == ["media", "calendar", "mirror"])
        #expect(reg.shiftActive("media", by: 1))
        #expect(reg.activeIDs == ["calendar", "media", "mirror"])
        #expect(reg.shiftActive("mirror", by: -1))
        #expect(reg.activeIDs == ["calendar", "mirror", "media"])
    }

    @Test func shiftActiveStopsAtTheEnds() {
        let reg = registry()
        #expect(!reg.shiftActive("media", by: -1))
        #expect(!reg.shiftActive("mirror", by: 1))
        #expect(reg.activeIDs == ["media", "calendar", "mirror"])
    }

    @Test func moveToIndexKeepsEveryModule() {
        let reg = registry()
        #expect(reg.move("timer", toIndex: 0))
        #expect(reg.order.first == "timer")
        #expect(Set(reg.order) == Set(ModuleDescriptor.all.map(\.id)))
        #expect(!reg.move("timer", toIndex: 0))
        #expect(!reg.move("timer", toIndex: 99))
    }

    @Test func reorderingPersists() {
        let defaults = UserDefaults(suiteName: "reorder-persist-\(UUID().uuidString)")!
        let first = ModuleRegistry(defaults: defaults)
        first.move("calendar", toIndex: 0)
        #expect(ModuleRegistry(defaults: defaults).order.first == "calendar")
    }
}

@MainActor
struct TabKeyboardTests {
    private func registry() -> ModuleRegistry {
        ModuleRegistry(defaults: UserDefaults(suiteName: "tab-keys-\(UUID().uuidString)")!)
    }

    @Test func arrowsStepThroughTabsAndStopAtTheEnds() async {
        let reg = registry()
        let ids = reg.availableTabs.map(\.id)
        #expect(ids.count >= 3)
        reg.stepTab(by: -1)
        await Task.yield()
        #expect(reg.effectiveTab?.id == ids[0])
        reg.stepTab(by: 1)
        await Task.yield()
        #expect(reg.effectiveTab?.id == ids[1])
        for _ in 0..<10 { reg.stepTab(by: 1); await Task.yield() }
        #expect(reg.effectiveTab?.id == ids.last)
    }

    @Test func numbersJumpToTheNthTabAndIgnoreMissingOnes() async {
        let reg = registry()
        let ids = reg.availableTabs.map(\.id)
        reg.selectTab(number: 3)
        await Task.yield()
        #expect(reg.effectiveTab?.id == ids[2])
        reg.selectTab(number: 9)
        await Task.yield()
        #expect(reg.effectiveTab?.id == ids[2])
    }
}
