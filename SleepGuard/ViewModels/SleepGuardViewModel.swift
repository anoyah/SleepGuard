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
    private var autoRefreshTask: Task<Void, Never>?

    init(
        runner: PMSetRunning = PMSetCommandRunner(),
        assertionsParser: AssertionsParser = AssertionsParser(),
        sleepLogParser: SleepLogParser = SleepLogParser(),
        riskAnalyzer: RiskAnalyzer = RiskAnalyzer(),
        trendAnalyzer: AssertionTrendAnalyzer = AssertionTrendAnalyzer(),
        ignoredMatcher: IgnoredAssertionMatcher = IgnoredAssertionMatcher(),
        reportGenerator: ReportGenerator = ReportGenerator(),
        historyStore: LocalHistoryStore = LocalHistoryStore(),
        launchAtLoginManager: LaunchAtLoginManaging = LaunchAtLoginManager()
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
        self.history = Array(historyStore.load().reversed())
    }

    var menuBarSystemImage: String {
        switch diagnosis?.overallStatus ?? .normal {
        case .normal: return "moon.zzz.fill"
        case .warning: return "moon.zzz"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginManager.isEnabled
    }

    func start() async {
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
            let storedHistory = historyStore.load()
            let analyzedDiagnosis = riskAnalyzer.analyze(parsedAssertions)
            let trendedDiagnosis = trendAnalyzer.attachTrends(to: analyzedDiagnosis, history: storedHistory, now: now)
            let newDiagnosis = ignoredMatcher.apply(rules: settings.ignoredRules, to: trendedDiagnosis)
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
            let storedHistory = historyStore.load()
            let analyzedDiagnosis = riskAnalyzer.analyze(parsed)
            let trendedDiagnosis = trendAnalyzer.attachTrends(to: analyzedDiagnosis, history: storedHistory, now: now)
            let newDiagnosis = ignoredMatcher.apply(rules: settings.ignoredRules, to: trendedDiagnosis)
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
            launchAtLoginError = "无法更新登录项：\(error.localizedDescription)"
            objectWillChange.send()
        }
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

    private func reapplyIgnoredRules() {
        guard let diagnosis else { return }
        let allItemsDiagnosis = SleepDiagnosis(
            parsed: diagnosis.parsed,
            overallStatus: diagnosis.overallStatus,
            processItems: diagnosis.processItems + diagnosis.ignoredProcessItems,
            kernelItems: diagnosis.kernelItems + diagnosis.ignoredKernelItems,
            ignoredProcessItems: [],
            ignoredKernelItems: [],
            recommendations: diagnosis.recommendations,
            criticalCount: diagnosis.criticalCount,
            warningCount: diagnosis.warningCount,
            kernelAssertionCount: diagnosis.kernelAssertionCount
        )
        self.diagnosis = ignoredMatcher.apply(rules: settings.ignoredRules, to: allItemsDiagnosis)
    }
}
