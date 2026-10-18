import Foundation
import Testing
@testable import Pendant

struct TuningTests {
    private func isolatedStore() -> UserDefaults {
        UserDefaults(suiteName: "tuning-tests-\(UUID().uuidString)")!
    }

    @Test func savedValuesSurviveAReload() {
        let store = isolatedStore()
        let tuning = Tuning(defaults: store)
        tuning.cellWidth = 80
        tuning.expandDamping = 0.7
        tuning.save(defaults: store)

        let reloaded = Tuning(loadSaved: true, defaults: store)
        #expect(reloaded.cellWidth == 80)
        #expect(reloaded.expandDamping == 0.7)
        #expect(reloaded.artSize == Tuning.defaults["artSize"])
    }

    @Test func onlyChangedValuesAreStored() {
        let store = isolatedStore()
        let tuning = Tuning(defaults: store)
        tuning.artSize = 111
        tuning.save(defaults: store)
        #expect(store.object(forKey: Tuning.keyPrefix + "artSize") != nil)
        #expect(store.object(forKey: Tuning.keyPrefix + "cellWidth") == nil)
        tuning.artSize = Tuning.defaults["artSize"] ?? 100
        tuning.save(defaults: store)
        #expect(store.object(forKey: Tuning.keyPrefix + "artSize") == nil)
    }

    @Test func resetRestoresDefaultsAndClearsSavedValues() {
        let store = isolatedStore()
        let tuning = Tuning(defaults: store)
        tuning.cellWidth = 90
        tuning.save(defaults: store)
        tuning.resetAll(defaults: store)
        #expect(tuning.cellWidth == Tuning.defaults["cellWidth"])
        #expect(Tuning(loadSaved: true, defaults: store).cellWidth == Tuning.defaults["cellWidth"])
    }

    @Test func corruptValuesAreClampedToTheirRange() {
        let store = isolatedStore()
        store.set(10_000.0, forKey: Tuning.keyPrefix + "cellWidth")
        store.set(Double.nan, forKey: Tuning.keyPrefix + "artSize")
        let tuning = Tuning(loadSaved: true, defaults: store)
        let range = Tuning.parameters.first { $0.id == "cellWidth" }!.range
        #expect(tuning.cellWidth == range.upperBound)
        #expect(tuning.artSize == Tuning.defaults["artSize"])
    }

    @Test func everyParameterHasAUniqueIdAndADefaultInsideItsRange() {
        let ids = Tuning.parameters.map(\.id)
        #expect(Set(ids).count == ids.count)
        for parameter in Tuning.parameters {
            let value = Tuning.defaults[parameter.id]
            #expect(value != nil)
            #expect(value.map(parameter.range.contains) == true)
        }
    }
}
