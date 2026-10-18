import Foundation

/// The app was renamed and got a new bundle identifier, so its preferences live in a new place. Once, at the first launch,
/// the settings, module layout and tuning values saved under the old identifier are copied over.
enum LegacyDefaultsMigration {
    static let oldDomain = "com.smallja.nook"
    private static let doneKey = "settings.migratedFromLegacyDomain"
    private static let prefixes = ["settings.", "tuning.", "modules."]

    /// The entries of the old domain that belong to the app (never macOS's own keys).
    static func migratedValues(from old: [String: Any]) -> [String: Any] {
        old.filter { key, _ in prefixes.contains { key.hasPrefix($0) } }
    }

    static func run(defaults: UserDefaults = .standard, oldDomain: String = oldDomain) {
        guard defaults.object(forKey: doneKey) == nil else { return }
        if let old = defaults.persistentDomain(forName: oldDomain) {
            for (key, value) in migratedValues(from: old) where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}
