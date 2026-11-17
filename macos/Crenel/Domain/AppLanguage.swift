import Foundation

/// The language the interface is shown in. English is the development language; other
/// languages are added as String Catalog translations and picked up automatically.
/// Dates and numbers in the UI format with `AppLanguage.locale`, so they always match
/// the interface language rather than the system region.
enum AppLanguage {
    static var locale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }
}
