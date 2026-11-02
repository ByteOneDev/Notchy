import Foundation

/// In-app localization. Strings live in `Strings.table` so the language can change live
/// from the settings, without restarting the app.
enum Loc {
    nonisolated(unsafe) static var language: AppLanguage = .fr

    static var locale: Locale { language.locale }
}

/// Localized string for `key` in the current app language.
func L(_ key: String) -> String {
    guard let entry = Strings.table[key] else { return key }
    return Loc.language == .fr ? entry.fr : entry.en
}

/// Localized format string, e.g. `L("battery.percent", 42)`.
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), locale: Loc.locale, arguments: args)
}
