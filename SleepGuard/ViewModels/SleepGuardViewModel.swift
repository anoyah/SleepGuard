import AppKit
import Combine
import Foundation
import SwiftUI
import UserNotifications

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
    private var storedHistory: [HistoryRecord] = []
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
        self.storedHistory = historyStore.load()
        self.history = Array(storedHistory.reversed())
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
                    self?.restartAutoRefresh()
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

    func startBackgroundRefresh() async {
        await refreshAll()
        restartAutoRefresh()
    }

    func start() async {
        if diagnosis == nil {
            await refreshAll()
        }
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
            let previousStatus = diagnosis?.overallStatus
            diagnosis = newDiagnosis
            lastRefresh = now
            appendHistoryIfNeeded(for: newDiagnosis, at: now)
            sendCriticalNotificationIfNeeded(newStatus: newDiagnosis.overallStatus, previousStatus: previousStatus)
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
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        guard let seconds = settings.refreshInterval.seconds else { return }
        autoRefreshTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(seconds))
                guard Task.isCancelled == false else { return }
                await self?.refreshAll()
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    private func appendHistoryIfNeeded(for diagnosis: SleepDiagnosis, at timestamp: Date) {
        let last = storedHistory.last
        let statusChanged = last?.status != diagnosis.overallStatus
        let hourElapsed = last.map { timestamp.timeIntervalSince($0.timestamp) >= 3600 } ?? true
        guard statusChanged || hourElapsed else { return }

        let record = HistoryRecord(
            timestamp: timestamp,
            status: diagnosis.overallStatus,
            criticalCount: diagnosis.criticalCount,
            warningCount: diagnosis.warningCount,
            kernelAssertionCount: diagnosis.kernelAssertionCount,
            summary: diagnosis.overallStatus.summary,
            assertionSnapshots: AssertionTrendAnalyzer.makeSnapshots(from: diagnosis)
        )
        storedHistory.append(record)
        if storedHistory.count > 200 {
            storedHistory.removeFirst(storedHistory.count - 200)
        }
        historyStore.save(storedHistory)
        history = Array(storedHistory.reversed())
    }

    private func makeDiagnosis(from parsed: ParsedAssertions, now: Date) -> SleepDiagnosis {
        let analyzedDiagnosis = riskAnalyzer.analyze(parsed)
        let trendedDiagnosis = trendAnalyzer.attachTrends(to: analyzedDiagnosis, history: storedHistory, now: now)
        return ignoredMatcher.apply(rules: settings.ignoredRules, to: trendedDiagnosis)
    }

    private func sendCriticalNotificationIfNeeded(newStatus: OverallSleepStatus, previousStatus: OverallSleepStatus?) {
        guard newStatus == .critical, previousStatus != .critical else { return }
        let content = UNMutableNotificationContent()
        content.title = "SleepGuard"
        content.body = L(
            "发现明确阻止休眠的项目，点击查看详情。",
            "Sleep blockers detected. Tap to view details."
        )
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "sleepguard.critical",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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
