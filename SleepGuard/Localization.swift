import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return L("跟随系统", "System")
        case .zhHans:
            return "简体中文"
        case .en:
            return "English"
        }
    }

    var languageIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .zhHans:
            return rawValue
        case .en:
            return rawValue
        }
    }
}

enum SleepGuardLocalization {
    static var preferredLanguageOverride: String?
    static var appLanguage: AppLanguage = .system
}

/// Returns the Chinese string when the user's preferred language is zh-*, English otherwise.
func L(_ zh: String, _ en: String) -> String {
    let lang = SleepGuardLocalization.preferredLanguageOverride
        ?? SleepGuardLocalization.appLanguage.languageIdentifier
        ?? Locale.preferredLanguages.first
        ?? "en"
    return lang.hasPrefix("zh") ? zh : en
}
