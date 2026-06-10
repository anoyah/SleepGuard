import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published var appLanguage: AppLanguage {
        didSet {
            defaults.set(appLanguage.rawValue, forKey: appLanguageKey)
        }
    }

    @Published var refreshInterval: RefreshInterval {
        didSet {
            defaults.set(refreshInterval.rawValue, forKey: refreshIntervalKey)
        }
    }

    @Published private(set) var ignoredRules: [IgnoredAssertionRule] {
        didSet {
            saveIgnoredRules()
        }
    }

    private let defaults: UserDefaults
    private let appLanguageKey = "appLanguage"
    private let refreshIntervalKey = "refreshInterval"
    private let ignoredRulesKey = "ignoredRules"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let languageValue = defaults.string(forKey: appLanguageKey) ?? AppLanguage.system.rawValue
        self.appLanguage = AppLanguage(rawValue: languageValue) ?? .system
        let value = defaults.string(forKey: refreshIntervalKey) ?? RefreshInterval.fiveMinutes.rawValue
        self.refreshInterval = RefreshInterval(rawValue: value) ?? .fiveMinutes
        self.ignoredRules = Self.loadIgnoredRules(from: defaults, key: ignoredRulesKey)
    }

    func addIgnoredRule(_ rule: IgnoredAssertionRule) {
        guard ignoredRules.contains(where: { $0.signature == rule.signature }) == false else { return }
        ignoredRules.append(rule)
    }

    func removeIgnoredRule(_ rule: IgnoredAssertionRule) {
        ignoredRules.removeAll { $0.signature == rule.signature }
    }

    func removeIgnoredRule(signature: String) {
        ignoredRules.removeAll { $0.signature == signature }
    }

    private func saveIgnoredRules() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(ignoredRules) else { return }
        defaults.set(data, forKey: ignoredRulesKey)
    }

    private static func loadIgnoredRules(from defaults: UserDefaults, key: String) -> [IgnoredAssertionRule] {
        guard let data = defaults.data(forKey: key) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([IgnoredAssertionRule].self, from: data)) ?? []
    }
}
