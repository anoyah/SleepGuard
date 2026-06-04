import Foundation

enum SleepGuardLocalization {
    static var preferredLanguageOverride: String?
}

/// Returns the Chinese string when the user's preferred language is zh-*, English otherwise.
func L(_ zh: String, _ en: String) -> String {
    let lang = SleepGuardLocalization.preferredLanguageOverride ?? Locale.preferredLanguages.first ?? "en"
    return lang.hasPrefix("zh") ? zh : en
}
