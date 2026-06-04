import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class SleepGuardViewModel: ObservableObject {
    @Published private(set) var diagnosis: SleepDiagnosis?
    @Published private(set) var sleepLog: SleepLogSummary?
    @Published private(set) var history: [HistoryRecord] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSleepLogRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var sleepLogError: String?
    @Published private(set) var launchAtLoginError: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var localizationRevision = 0
    @Published private(set) var sleepPreventionState: SleepPreventionState = .inactive
    @Published var settings = SettingsStore()

    private let runner: PMSetRunning
    private let assertionsParser: AssertionsParser
    private let sleepLogParser: SleepLogParser
    private let riskAnalyzer: RiskAnalyzer
    private let trendAnalyzer: AssertionTrendAnalyzer
    private let ignoredMatcher: IgnoredAssertionMatcher
    private let reportGenerator: ReportGenerator
    private let historyStore: LocalHistoryStore
    private let launchAtLoginManager: LaunchAtLoginManaging
    private let sleepPreventionManager: SleepPreventionManaging
    private var autoRefreshTask: Task<Void, Never>?
    private var isMenuOpen = false
    private var cancellables = Set<AnyCancellable>()

    init(
        runner: PMSetRunning = PMSetCommandRunner(),
        assertionsParser: AssertionsParser = AssertionsParser(),
        sleepLogParser: SleepLogParser = SleepLogParser(),
        riskAnalyzer: RiskAnalyzer = RiskAnalyzer(),
        trendAnalyzer: AssertionTrendAnalyzer = AssertionTrendAnalyzer(),
        ignoredMatcher: IgnoredAssertionMatcher = IgnoredAssertionMatcher(),
        reportGenerator: ReportGenerator = ReportGenerator(),
        historyStore: LocalHistoryStore = LocalHistoryStore(),
        launchAtLoginManager: LaunchAtLoginManaging = LaunchAtLoginManager(),
        sleepPreventionManager: SleepPreventionManaging = SleepPreventionManager()
    ) {
        self.runner = runner
        self.assertionsParser = assertionsParser
        self.sleepLogParser = sleepLogParser
        self.riskAnalyzer = riskAnalyzer
        self.trendAnalyzer = trendAnalyzer
        self.ignoredMatcher = ignoredMatcher
        self.reportGenerator = reportGenerator
        self.historyStore = historyStore
        self.launchAtLoginManager = launchAtLoginManager
        self.sleepPreventionManager = sleepPreventionManager
        self.history = Array(historyStore.load().reversed())
        self.sleepPreventionState = sleepPreventionManager.state

        self.sleepPreventionManager.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.sleepPreventionState = state
            }
        }

        SleepGuardLocalization.appLanguage = settings.appLanguage

        settings.$appLanguage
            .dropFirst()
            .sink { [weak self] language in
                SleepGuardLocalization.appLanguage = language
                self?.localizationRevision += 1
                self?.relocalizeCurrentState()
            }
            .store(in: &cancellables)

        settings.$refreshInterval
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isMenuOpen else { return }
                    self.restartAutoRefresh()
                }
            }
            .store(in: &cancellables)
    }

    var menuBarSystemImage: String {
        if sleepPreventionState.isActive {
            return "cup.and.saucer.fill"
        }

        switch diagnosis?.overallStatus ?? .normal {
        case .normal: return "moon.zzz.fill"
        case .warning: return "moon.zzz"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    var menuBarAccessibilityDescription: String {
        sleepPreventionState.isActive ? sleepPreventionStatusText : "SleepGuard"
    }

    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginManager.isEnabled
    }

    var sleepPreventionStatusText: String {
        sleepPreventionState.statusTitle
    }

    var sleepPreventionDetailText: String {
        sleepPreventionState.detailText()
    }

    func start() async {
        isMenuOpen = true
        if diagnosis == nil {
            await refreshAll()
        }
        restartAutoRefresh()
    }

    func refreshAll() async {
        guard isRefreshing == false else { return }
        isRefreshing = true
        lastError = nil

        do {
            let assertionsOutput = try await runner.assertions()
            let parsedAssertions = assertionsParser.parse(assertionsOutput)
            let now = Date()
            let newDiagnosis = makeDiagnosis(from: parsedAssertions, now: now)
            diagnosis = newDiagnosis
            lastRefresh = now
            appendHistory(for: newDiagnosis, at: now)
        } catch {
            lastError = error.localizedDescription
        }

        isRefreshing = false
    }

    func refreshAssertionsOnly() async {
        guard isRefreshing == false else { return }
        isRefreshing = true
        lastError = nil

        do {
            let output = try await runner.assertions()
            let parsed = assertionsParser.parse(output)
            let now = Date()
            let newDiagnosis = makeDiagnosis(from: parsed, now: now)
            diagnosis = newDiagnosis
            lastRefresh = now
            appendHistory(for: newDiagnosis, at: now)
        } catch {
            lastError = error.localizedDescription
        }

        isRefreshing = false
    }

    func refreshSleepLog() async {
        guard isSleepLogRefreshing == false else { return }
        isSleepLogRefreshing = true
        sleepLogError = nil

        do {
            let output = try await runner.log()
            sleepLog = sleepLogParser.parse(output)
        } catch {
            sleepLogError = error.localizedDescription
        }

        isSleepLogRefreshing = false
    }

    func copyReport() {
        let report = reportGenerator.makeReport(diagnosis: diagnosis, sleepLog: sleepLog)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    func ignoreProcess(_ item: AnalyzedProcessAssertion) {
        settings.addIgnoredRule(IgnoredAssertionMatcher.rule(for: item))
        reapplyIgnoredRules()
    }

    func ignoreKernel(_ item: AnalyzedKernelAssertion) {
        settings.addIgnoredRule(IgnoredAssertionMatcher.rule(for: item))
        reapplyIgnoredRules()
    }

    func removeIgnoredRule(_ rule: IgnoredAssertionRule) {
        settings.removeIgnoredRule(rule)
        reapplyIgnoredRules()
    }

    func removeIgnoredRule(signature: String) {
        settings.removeIgnoredRule(signature: signature)
        reapplyIgnoredRules()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            try launchAtLoginManager.setEnabled(enabled)
            objectWillChange.send()
        } catch {
            launchAtLoginError = L("无法更新登录项：\(error.localizedDescription)",
                                   "Failed to update login item: \(error.localizedDescription)")
            objectWillChange.send()
        }
    }

    func startSleepPrevention(duration: SleepPreventionDuration) {
        sleepPreventionManager.start(duration: duration, now: Date())
        sleepPreventionState = sleepPreventionManager.state
    }

    func stopSleepPrevention() {
        sleepPreventionManager.stop()
        sleepPreventionState = sleepPreventionManager.state
    }

    func restartAutoRefresh() {
        stopAutoRefresh()
        guard let seconds = settings.refreshInterval.seconds else { return }
        autoRefreshTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                guard Task.isCancelled == false else { return }
                await self?.refreshAll()
            }
        }
    }

    func stopAutoRefresh() {
        isMenuOpen = false
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    private func appendHistory(for diagnosis: SleepDiagnosis, at timestamp: Date) {
        let record = HistoryRecord(
            timestamp: timestamp,
            status: diagnosis.overallStatus,
            criticalCount: diagnosis.criticalCount,
            warningCount: diagnosis.warningCount,
            kernelAssertionCount: diagnosis.kernelAssertionCount,
            summary: diagnosis.overallStatus.summary,
            assertionSnapshots: AssertionTrendAnalyzer.makeSnapshots(from: diagnosis)
        )
        historyStore.append(record)
        history = Array(historyStore.load().reversed())
    }

    private func makeDiagnosis(from parsed: ParsedAssertions, now: Date) -> SleepDiagnosis {
        let storedHistory = historyStore.load()
        let analyzedDiagnosis = riskAnalyzer.analyze(parsed)
        let trendedDiagnosis = trendAnalyzer.attachTrends(to: analyzedDiagnosis, history: storedHistory, now: now)
        return ignoredMatcher.apply(rules: settings.ignoredRules, to: trendedDiagnosis)
    }

    private func relocalizeCurrentState() {
        guard let diagnosis else {
            objectWillChange.send()
            return
        }
        self.diagnosis = makeDiagnosis(from: diagnosis.parsed, now: lastRefresh ?? diagnosis.parsed.capturedAt)
    }

    private func reapplyIgnoredRules() {
        guard let diagnosis else { return }
        self.diagnosis = makeDiagnosis(from: diagnosis.parsed, now: lastRefresh ?? diagnosis.parsed.capturedAt)
    }
}
