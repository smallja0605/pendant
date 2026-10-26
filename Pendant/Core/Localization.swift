import SwiftUI

/// The app's own words are written in Traditional Chinese and used as the keys of `Localizable.xcstrings`; the English
/// column translates them. Literals handed straight to a SwiftUI view are looked up by SwiftUI itself, so these two helpers are for
/// text that arrives as a `String` (a row's title passed down to a shared view, a status message, an alert).
///
/// Never use them for user content (song titles, reminder or list names, notes): those must show as they are.
func loc(_ text: String) -> LocalizedStringKey { LocalizedStringKey(text) }

/// A `String` in the language the app runs in (alerts, menu items, error messages).
func tr(_ text: String.LocalizationValue) -> String { String(localized: text) }

/// Whether the app is showing its English texts (the system language, or the language chosen in 設定 › 一般).
var isEnglishUI: Bool { Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true }

extension Locale {
    /// The locale for dates and times the app writes itself (the virtual notch's clock): Taiwan Chinese, or US English in English mode.
    static var appDisplay: Locale { Locale(identifier: isEnglishUI ? "en_US" : "zh_TW") }
}
