import IOKit.pwr_mgt
import XCTest
@testable import SleepGuard

final class SleepGuardTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SleepGuardLocalization.preferredLanguageOverride = "zh-Hans"
    }

    override func tearDown() {
        SleepGuardLocalization.preferredLanguageOverride = nil
        SleepGuardLocalization.appLanguage = .system
        super.tearDown()
    }

    func testAssertionsParserParsesSystemProcessesTimeoutAndKernelAssertions() {
        let sample = """
        2026-06-03 18:37:44 +0800
        Assertion status system-wide:
           BackgroundTask                 0
           ApplePushServiceTask           0
           UserIsActive                   1
           PreventUserIdleDisplaySleep    0
           PreventSystemSleep             0
           ExternalMedia                  0
           PreventUserIdleSystemSleep     1
           NetworkClientActive            0
        Listed by owning process:
           pid 752(sharingd): [0x000674ac0001a093] 00:04:51 PreventUserIdleSystemSleep named: "Handoff"
           pid 384(WindowServer): [0x00066e4300099f2e] 00:00:00 UserIsActive named: "Bluetooth LE HID Activity"
            Timeout will fire in 1200 secs Action=TimeoutActionRelease
           pid 327(powerd): [0x00066e4300019f28] 00:32:12 PreventUserIdleSystemSleep named: "Powerd - Prevent sleep while display is on"
        Kernel Assertions: 0x4=USB
           id=662  level=255 0x4=USB creat=2026/6/3, 08:34 description=com.apple.usb.externaldevice.00100000 owner=Generic Billboard Device
        """

        let parsed = AssertionsParser().parse(sample)

        XCTAssertTrue(parsed.systemStatus.preventUserIdleSystemSleep)
        XCTAssertFalse(parsed.systemStatus.preventSystemSleep)
        XCTAssertTrue(parsed.systemStatus.hasKernelAssertions)
        XCTAssertEqual(parsed.processAssertions.count, 3)
        XCTAssertEqual(parsed.processAssertions[0].pid, 752)
        XCTAssertEqual(parsed.processAssertions[0].processName, "sharingd")
        XCTAssertEqual(parsed.processAssertions[0].durationSeconds, 291)
        XCTAssertEqual(parsed.processAssertions[1].timeout, "Timeout will fire in 1200 secs Action=TimeoutActionRelease")
        XCTAssertEqual(parsed.kernelAssertions.count, 1)
        XCTAssertEqual(parsed.kernelAssertions[0].owner, "Generic Billboard Device")
        XCTAssertEqual(parsed.kernelAssertions[0].assertionCode, "0x4=USB")
    }

    func testRiskAnalyzerClassifiesKnownProcesses() {
        let assertions = [
            makeAssertion(process: "NeteaseMusic", type: "PreventUserIdleSystemSleep", reason: "NetEase CloudMusic is playing music", seconds: 60),
            makeAssertion(process: "coreaudiod", type: "PreventUserIdleSystemSleep", reason: "com.apple.audio.context.preventuseridlesleep", seconds: 3600),
            makeAssertion(process: "oplus_remote_service", type: "PreventUserIdleSystemSleep", reason: "Prevent sleep for my process", seconds: 60),
            makeAssertion(process: "backupd-helper", type: "PreventUserIdleSystemSleep", reason: "Mutexed Backup Block", seconds: 30),
            makeAssertion(process: "sharingd", type: "PreventUserIdleSystemSleep", reason: "Handoff", seconds: 30),
            makeAssertion(process: "bluetoothd", type: "PreventUserIdleSystemSleep", reason: "com.apple.BTStack", seconds: 30),
            makeAssertion(process: "powerd", type: "PreventUserIdleSystemSleep", reason: "Powerd - Prevent sleep while display is on", seconds: 1800)
        ]
        let parsed = ParsedAssertions(
            capturedAt: Date(),
            systemStatus: AssertionStatus(),
            processAssertions: assertions,
            kernelAssertions: [
                KernelAssertion(assertionCode: "0x4=USB", owner: "Generic Billboard Device", description: "com.apple.usb.externaldevice", rawLine: "owner=Generic Billboard Device")
            ],
            rawOutput: ""
        )

        let diagnosis = RiskAnalyzer().analyze(parsed)
        let risks = Dictionary(uniqueKeysWithValues: diagnosis.processItems.map { ($0.assertion.processName, $0.analysis.risk) })

        XCTAssertEqual(risks["NeteaseMusic"], .warning)
        XCTAssertEqual(risks["coreaudiod"], .critical)
        XCTAssertEqual(risks["oplus_remote_service"], .critical)
        XCTAssertEqual(risks["backupd-helper"], .warning)
        XCTAssertEqual(risks["sharingd"], .warning)
        XCTAssertEqual(risks["bluetoothd"], .warning)
        XCTAssertEqual(risks["powerd"], .normal)
        XCTAssertEqual(diagnosis.kernelItems.first?.analysis.risk, .usbWarning)
        XCTAssertEqual(diagnosis.overallStatus, .critical)
    }

    func testReportContainsCoreSections() {
        let parsed = ParsedAssertions(
            capturedAt: Date(),
            systemStatus: AssertionStatus(preventUserIdleSystemSleep: true),
            processAssertions: [
                makeAssertion(process: "oplus_remote_service", type: "PreventUserIdleSystemSleep", reason: "Prevent sleep for my process", seconds: 3600)
            ],
            kernelAssertions: [],
            rawOutput: ""
        )
        let diagnosis = RiskAnalyzer().analyze(parsed)
        let report = ReportGenerator().makeReport(diagnosis: diagnosis, sleepLog: nil)

        XCTAssertTrue(report.contains("SleepGuard 诊断报告"))
        XCTAssertTrue(report.contains("应用版本"))
        XCTAssertTrue(report.contains("整体判断"))
        XCTAssertTrue(report.contains("系统范围断言状态"))
        XCTAssertTrue(report.contains("进程阻止项"))
        XCTAssertTrue(report.contains("内核断言"))
        XCTAssertTrue(report.contains("原始类型"))
        XCTAssertTrue(report.contains("原始原因"))
        XCTAssertTrue(report.contains("推荐处理建议"))
        XCTAssertTrue(report.contains("oplus_remote_service"))
    }

    func testTrendAnalyzerCountsConsecutiveSnapshots() {
        let current = makeAssertion(process: "coreaudiod", type: "PreventUserIdleSystemSleep", reason: "audio active", seconds: 60)
        let parsed = ParsedAssertions(
            capturedAt: Date(timeIntervalSince1970: 300),
            systemStatus: AssertionStatus(preventUserIdleSystemSleep: true),
            processAssertions: [current],
            kernelAssertions: [],
            rawOutput: ""
        )
        let diagnosis = RiskAnalyzer().analyze(parsed)
        let snapshots = AssertionTrendAnalyzer.makeSnapshots(from: diagnosis)
        let history = [
            HistoryRecord(
                timestamp: Date(timeIntervalSince1970: 100),
                status: .warning,
                criticalCount: 0,
                warningCount: 1,
                kernelAssertionCount: 0,
                summary: "previous",
                assertionSnapshots: snapshots
            ),
            HistoryRecord(
                timestamp: Date(timeIntervalSince1970: 200),
                status: .warning,
                criticalCount: 0,
                warningCount: 1,
                kernelAssertionCount: 0,
                summary: "previous",
                assertionSnapshots: snapshots
            )
        ]

        let trended = AssertionTrendAnalyzer().attachTrends(
            to: diagnosis,
            history: history,
            now: Date(timeIntervalSince1970: 300)
        )

        XCTAssertEqual(trended.processItems.first?.trend?.consecutiveCount, 3)
        XCTAssertEqual(trended.processItems.first?.trend?.observedDurationSeconds, 200)
        XCTAssertEqual(trended.processItems.first?.trend?.summary, "已连续出现 3 次，约 3 分钟")
    }

    func testReportIncludesTrendSummary() {
        let parsed = ParsedAssertions(
            capturedAt: Date(),
            systemStatus: AssertionStatus(preventUserIdleSystemSleep: true),
            processAssertions: [
                makeAssertion(process: "coreaudiod", type: "PreventUserIdleSystemSleep", reason: "audio active", seconds: 60)
            ],
            kernelAssertions: [],
            rawOutput: ""
        )
        let diagnosis = RiskAnalyzer().analyze(parsed)
        let snapshots = AssertionTrendAnalyzer.makeSnapshots(from: diagnosis)
        let trended = AssertionTrendAnalyzer().attachTrends(
            to: diagnosis,
            history: [
                HistoryRecord(
                    timestamp: Date(timeIntervalSince1970: 100),
                    status: .warning,
                    criticalCount: 0,
                    warningCount: 1,
                    kernelAssertionCount: 0,
                    summary: "previous",
                    assertionSnapshots: snapshots
                )
            ],
            now: Date(timeIntervalSince1970: 160)
        )
        let report = ReportGenerator().makeReport(diagnosis: trended, sleepLog: nil)

        XCTAssertTrue(report.contains("连续出现"))
        XCTAssertTrue(report.contains("已连续出现 2 次"))
    }

    func testIgnoredRulesMatchProcessAndKernelAssertions() {
        let process = makeAssertion(process: "coreaudiod", type: "PreventUserIdleSystemSleep", reason: "audio active", seconds: 60)
        let kernel = KernelAssertion(assertionCode: "0x4=USB", owner: "Generic Billboard Device", description: "usb", rawLine: "owner=Generic Billboard Device")
        let diagnosis = RiskAnalyzer().analyze(ParsedAssertions(
            capturedAt: Date(),
            systemStatus: AssertionStatus(),
            processAssertions: [process],
            kernelAssertions: [kernel],
            rawOutput: ""
        ))
        let processRule = IgnoredAssertionMatcher.rule(for: diagnosis.processItems[0], createdAt: Date(timeIntervalSince1970: 0))
        let kernelRule = IgnoredAssertionMatcher.rule(for: diagnosis.kernelItems[0], createdAt: Date(timeIntervalSince1970: 0))
        let matcher = IgnoredAssertionMatcher()

        XCTAssertTrue(matcher.matches(processRule, process: process))
        XCTAssertTrue(matcher.matches(kernelRule, kernel: kernel))
    }

    func testIgnoredItemsDoNotContributeToCountsOrOverallStatus() {
        let parsed = ParsedAssertions(
            capturedAt: Date(),
            systemStatus: AssertionStatus(preventUserIdleSystemSleep: true),
            processAssertions: [
                makeAssertion(process: "oplus_remote_service", type: "PreventUserIdleSystemSleep", reason: "Prevent sleep for my process", seconds: 3600)
            ],
            kernelAssertions: [
                KernelAssertion(assertionCode: "0x4=USB", owner: "Generic Billboard Device", description: "usb", rawLine: "owner=Generic Billboard Device")
            ],
            rawOutput: ""
        )
        let diagnosis = RiskAnalyzer().analyze(parsed)
        let rules = [
            IgnoredAssertionMatcher.rule(for: diagnosis.processItems[0], createdAt: Date(timeIntervalSince1970: 0)),
            IgnoredAssertionMatcher.rule(for: diagnosis.kernelItems[0], createdAt: Date(timeIntervalSince1970: 0))
        ]

        let filtered = IgnoredAssertionMatcher().apply(rules: rules, to: diagnosis)

        XCTAssertEqual(filtered.overallStatus, .normal)
        XCTAssertEqual(filtered.criticalCount, 0)
        XCTAssertEqual(filtered.warningCount, 0)
        XCTAssertEqual(filtered.kernelAssertionCount, 0)
        XCTAssertTrue(filtered.processItems.isEmpty)
        XCTAssertTrue(filtered.kernelItems.isEmpty)
        XCTAssertEqual(filtered.ignoredProcessItems.count, 1)
        XCTAssertEqual(filtered.ignoredKernelItems.count, 1)
    }

    func testReportIncludesIgnoredItemsSection() {
        let parsed = ParsedAssertions(
            capturedAt: Date(),
            systemStatus: AssertionStatus(preventUserIdleSystemSleep: true),
            processAssertions: [
                makeAssertion(process: "oplus_remote_service", type: "PreventUserIdleSystemSleep", reason: "Prevent sleep for my process", seconds: 3600)
            ],
            kernelAssertions: [],
            rawOutput: ""
        )
        let diagnosis = RiskAnalyzer().analyze(parsed)
        let rule = IgnoredAssertionMatcher.rule(for: diagnosis.processItems[0], createdAt: Date(timeIntervalSince1970: 0))
        let filtered = IgnoredAssertionMatcher().apply(rules: [rule], to: diagnosis)
        let report = ReportGenerator().makeReport(diagnosis: filtered, sleepLog: nil)

        XCTAssertTrue(report.contains("已忽略项"))
        XCTAssertTrue(report.contains("已忽略项未参与整体判断"))
        XCTAssertTrue(report.contains("oplus_remote_service"))
    }

    func testSettingsStorePersistsIgnoredRules() {
        let suiteName = "SleepGuardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let rule = IgnoredAssertionRule(
            signature: "process|coreaudiod|prevent|audio",
            kind: .process,
            name: "coreaudiod",
            detail: "audio active",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let store = SettingsStore(defaults: defaults)
        store.addIgnoredRule(rule)
        let reloaded = SettingsStore(defaults: defaults)

        XCTAssertEqual(reloaded.ignoredRules, [rule])
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSettingsStorePersistsAppLanguage() {
        let suiteName = "SleepGuardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: defaults)
        store.appLanguage = .en
        let reloaded = SettingsStore(defaults: defaults)

        XCTAssertEqual(reloaded.appLanguage, .en)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testLocalizationUsesConfiguredAppLanguage() {
        SleepGuardLocalization.preferredLanguageOverride = nil
        SleepGuardLocalization.appLanguage = .en

        XCTAssertEqual(L("设置", "Settings"), "Settings")

        SleepGuardLocalization.appLanguage = .zhHans

        XCTAssertEqual(L("设置", "Settings"), "设置")
    }

    func testIgnoredProcessRuleDetailRelocalizesDisplayName() {
        SleepGuardLocalization.preferredLanguageOverride = nil
        SleepGuardLocalization.appLanguage = .zhHans
        let rule = IgnoredAssertionRule(
            signature: "process|coreaudiod|preventuseridlesystemsleep|com.apple.audio.context.preventuseridlesleep",
            kind: .process,
            name: "coreaudiod",
            detail: "Prevent User Idle System Sleep · com.apple.audio.context.preventuseridlesleep",
            createdAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(rule.localizedDetail, "防止系统空闲睡眠 · com.apple.audio.context.preventuseridlesleep")
    }

    func testSleepPreventionManagerCreatesDisplayAndSystemAssertions() {
        let powerManager = MockPowerAssertionManager()
        let manager = SleepPreventionManager(assertionManager: powerManager)

        manager.start(duration: .indefinite, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(powerManager.createdTypes, [
            String(kIOPMAssertionTypeNoDisplaySleep),
            String(kIOPMAssertionTypeNoIdleSleep)
        ])
        XCTAssertTrue(powerManager.releasedIDs.isEmpty)
        XCTAssertTrue(manager.state.isActive)
        XCTAssertEqual(manager.state.duration, .indefinite)
    }

    func testSleepPreventionManagerReleasesOldAssertionsWhenSwitchingDuration() {
        let powerManager = MockPowerAssertionManager()
        let manager = SleepPreventionManager(assertionManager: powerManager)

        manager.start(duration: .indefinite, now: Date(timeIntervalSince1970: 0))
        manager.start(duration: .oneHour, now: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(powerManager.releasedIDs, [1, 2])
        XCTAssertEqual(powerManager.createdTypes, [
            String(kIOPMAssertionTypeNoDisplaySleep),
            String(kIOPMAssertionTypeNoIdleSleep),
            String(kIOPMAssertionTypeNoDisplaySleep),
            String(kIOPMAssertionTypeNoIdleSleep)
        ])
        XCTAssertEqual(manager.state.duration, .oneHour)
    }

    func testSleepPreventionManagerStopsAndClearsState() {
        let powerManager = MockPowerAssertionManager()
        let manager = SleepPreventionManager(assertionManager: powerManager)

        manager.start(duration: .indefinite, now: Date(timeIntervalSince1970: 0))
        manager.stop()

        XCTAssertEqual(powerManager.releasedIDs, [1, 2])
        XCTAssertEqual(manager.state, .inactive)
    }

    func testSleepPreventionManagerTimedSessionCanExpire() {
        let powerManager = MockPowerAssertionManager()
        let manager = SleepPreventionManager(assertionManager: powerManager)

        manager.start(duration: .fifteenMinutes, now: Date(timeIntervalSince1970: 0))
        manager.expireCurrentSessionForTesting()

        XCTAssertEqual(powerManager.releasedIDs, [1, 2])
        XCTAssertEqual(manager.state, .inactive)
    }

    func testSleepPreventionStateUsesCurrentLanguage() {
        SleepGuardLocalization.preferredLanguageOverride = nil
        SleepGuardLocalization.appLanguage = .zhHans
        let state = SleepPreventionState(
            isActive: true,
            duration: .oneHour,
            startedAt: Date(timeIntervalSince1970: 0),
            endsAt: Date(timeIntervalSince1970: 3600)
        )

        XCTAssertEqual(state.statusTitle, "正在防止睡眠")
        XCTAssertEqual(state.detailText(now: Date(timeIntervalSince1970: 0)), "剩余 1 小时")
    }

    @MainActor
    func testMenuBarIconUsesSleepPreventionIconWhenActive() {
        let preventionManager = MockSleepPreventionManager()
        let viewModel = SleepGuardViewModel(
            historyStore: LocalHistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            sleepPreventionManager: preventionManager
        )

        XCTAssertEqual(viewModel.menuBarSystemImage, "moon.zzz.fill")
        XCTAssertEqual(viewModel.menuBarAccessibilityDescription, "SleepGuard")

        viewModel.startSleepPrevention(duration: .indefinite)
        XCTAssertEqual(viewModel.menuBarSystemImage, "cup.and.saucer.fill")
        XCTAssertEqual(viewModel.menuBarAccessibilityDescription, "正在防止睡眠")

        viewModel.stopSleepPrevention()
        XCTAssertEqual(viewModel.menuBarSystemImage, "moon.zzz.fill")
        XCTAssertEqual(viewModel.menuBarAccessibilityDescription, "SleepGuard")
    }

    @MainActor
    func testLaunchAtLoginManagerCanBeMockedFromViewModel() {
        let manager = MockLaunchAtLoginManager()
        let viewModel = SleepGuardViewModel(
            historyStore: LocalHistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            launchAtLoginManager: manager
        )

        viewModel.setLaunchAtLoginEnabled(true)

        XCTAssertTrue(manager.isEnabled)
        XCTAssertEqual(manager.requestedValues, [true])
        XCTAssertNil(viewModel.launchAtLoginError)
    }

    @MainActor
    func testViewModelRelocalizesCurrentDiagnosisWhenLanguageChanges() async {
        SleepGuardLocalization.preferredLanguageOverride = nil
        SleepGuardLocalization.appLanguage = .system
        let runner = MockPMSetRunner(assertionsOutput: """
        2026-06-03 18:37:44 +0800
        Assertion status system-wide:
           PreventUserIdleSystemSleep     1
        Listed by owning process:
           pid 384(coreaudiod): [0x00066e4300099f2e] 00:40:00 PreventUserIdleSystemSleep named: "com.apple.audio.context.preventuseridlesleep"
        """)
        let viewModel = SleepGuardViewModel(
            runner: runner,
            historyStore: LocalHistoryStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        )

        viewModel.settings.appLanguage = .en
        await viewModel.refreshAssertionsOnly()

        XCTAssertEqual(
            viewModel.diagnosis?.processItems.first?.analysis.explanation,
            "The system audio service is held by an input or output device — likely music, a call, microphone, or a virtual audio device."
        )
        XCTAssertTrue(
            viewModel.diagnosis?.recommendations.contains("Address critical (red) items first: quit the app or disable its Login Item, then refresh to verify.") == true
        )

        viewModel.settings.appLanguage = .zhHans

        XCTAssertEqual(
            viewModel.diagnosis?.processItems.first?.analysis.explanation,
            "系统音频服务被输入或输出设备占用，可能来自音乐、通话、麦克风或虚拟音频设备。"
        )
        XCTAssertTrue(
            viewModel.diagnosis?.recommendations.contains("优先处理红色项目：手动退出对应应用或关闭其后台登录项，然后刷新验证。") == true
        )
        XCTAssertEqual(viewModel.localizationRevision, 2)
    }

    func testDisplayNamesUseChineseLabels() {
        XCTAssertEqual(SleepAssertionType.preventUserIdleSystemSleep.displayName, "防止系统空闲睡眠")
        XCTAssertEqual(SleepAssertionType.preventSystemSleep.displayName, "防止系统睡眠")
        XCTAssertEqual(SleepAssertionType.preventUserIdleDisplaySleep.displayName, "防止显示器空闲睡眠")
        XCTAssertEqual(SleepAssertionType.internalPreventSleep.displayName, "内部防睡眠")
        XCTAssertEqual(SleepLogEventType.enteringSleep.displayName, "进入睡眠")
        XCTAssertEqual(SleepLogEventType.wakeFrom.displayName, "从睡眠唤醒")
        XCTAssertEqual(SleepLogEventType.wakeReason.displayName, "唤醒原因")
        XCTAssertEqual(SleepLogEventType.darkWake.displayName, "暗唤醒")
    }

    func testAppVersionDisplayText() {
        let info = AppVersionInfo(version: "1.2.3", build: "45", bundleIdentifier: "cc.anoya.SleepGuard")

        XCTAssertEqual(info.displayText, "版本 1.2.3（构建 45）")
        XCTAssertEqual(info.bundleIdentifier, "cc.anoya.SleepGuard")
    }

    func testHistoryStoreTrimsToLatestTwoHundredRecords() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history.json")
        let store = LocalHistoryStore(fileURL: url)

        for index in 0..<250 {
            store.append(HistoryRecord(
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                status: .warning,
                criticalCount: 0,
                warningCount: 1,
                kernelAssertionCount: 0,
                summary: "record \(index)"
            ))
        }

        let records = store.load()
        XCTAssertEqual(records.count, 200)
        XCTAssertEqual(records.first?.summary, "record 50")
        XCTAssertEqual(records.last?.summary, "record 249")
    }

    func testSleepLogParserKeepsLatestHundredAndDetectsLastNightSleep() {
        var lines: [String] = []
        for index in 0..<120 {
            lines.append("2026-06-02 20:\(String(format: "%02d", index % 60)):00 +0800 Sleep                Entering Sleep state due to 'Software Sleep pid=1'")
        }
        lines.append("2026-06-03 07:12:00 +0800 Wake                 Wake from Normal Sleep [CDNVA] : due to EC.LidOpen")
        lines.append("2026-06-03 07:12:01 +0800 Kernel Client Acks   Wake reason: EC.LidOpen")
        lines.append("2026-06-03 03:00:00 +0800 DarkWake             DarkWake from Normal Sleep")

        let now = ISO8601DateFormatter().date(from: "2026-06-03T12:00:00+08:00")!
        let summary = SleepLogParser().parse(lines.joined(separator: "\n"), now: now)

        XCTAssertEqual(summary.events.count, 100)
        XCTAssertTrue(summary.sleptLastNight)
        XCTAssertNotNil(summary.lastSleep)
        XCTAssertNotNil(summary.lastWake)
        XCTAssertEqual(summary.wakeReasons.count, 1)
        XCTAssertEqual(summary.darkWakes.count, 1)
        XCTAssertEqual(summary.wakeCount, 1)
        XCTAssertEqual(summary.darkWakeCount, 1)
        XCTAssertTrue(summary.suspiciousWakeReasons.isEmpty)
    }

    func testSleepLogParserClassifiesSuspiciousWakeReasons() {
        let sample = """
        2026-06-03 01:12:00 +0800 Wake                 Wake from Normal Sleep [CDNVA] : due to XHC
        2026-06-03 01:12:01 +0800 Kernel Client Acks   Wake reason: XHC USB HID Activity
        2026-06-03 02:12:01 +0800 Kernel Client Acks   Wake reason: Bluetooth BTStack
        2026-06-03 03:12:01 +0800 Kernel Client Acks   Wake reason: TCPKeepAlive network maintenance
        """

        let summary = SleepLogParser().parse(sample)

        XCTAssertEqual(Set(summary.suspiciousWakeReasons), Set([.externalDevice, .bluetooth, .network]))
        XCTAssertTrue(summary.hasSuspiciousWake)
        XCTAssertEqual(summary.recentWakeReason?.detail, "Wake reason: TCPKeepAlive network maintenance")
    }

    func testReportIncludesSleepQualitySummary() {
        let sample = """
        2026-06-03 01:12:00 +0800 Wake                 Wake from Normal Sleep [CDNVA] : due to XHC
        2026-06-03 01:12:01 +0800 Kernel Client Acks   Wake reason: XHC USB HID Activity
        2026-06-03 03:00:00 +0800 DarkWake             DarkWake from Normal Sleep
        """
        let sleepLog = SleepLogParser().parse(sample)
        let report = ReportGenerator().makeReport(diagnosis: nil, sleepLog: sleepLog)

        XCTAssertTrue(report.contains("唤醒次数：1"))
        XCTAssertTrue(report.contains("DarkWake 次数：1"))
        XCTAssertTrue(report.contains("疑似唤醒来源"))
        XCTAssertTrue(report.contains("外设"))
    }

    private func makeAssertion(process: String, type: String, reason: String, seconds: Int) -> ProcessAssertion {
        ProcessAssertion(
            pid: 1,
            processName: process,
            duration: "00:00:00",
            durationSeconds: seconds,
            assertionType: type,
            reason: reason,
            timeout: nil,
            rawLine: "\(process) \(type) \(reason)"
        )
    }
}

private final class MockLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled = false
    var requestedValues: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        isEnabled = enabled
    }
}

private struct MockPMSetRunner: PMSetRunning {
    let assertionsOutput: String
    var logOutput = ""

    func assertions() async throws -> String {
        assertionsOutput
    }

    func log() async throws -> String {
        logOutput
    }
}

private final class MockPowerAssertionManager: PowerAssertionManaging {
    private var nextID: IOPMAssertionID = 1
    private(set) var createdTypes: [String] = []
    private(set) var createdNames: [String] = []
    private(set) var releasedIDs: [IOPMAssertionID] = []

    func create(type: String, name: String) -> IOPMAssertionID? {
        createdTypes.append(type)
        createdNames.append(name)
        defer { nextID += 1 }
        return nextID
    }

    func release(_ id: IOPMAssertionID) {
        releasedIDs.append(id)
    }
}

private final class MockSleepPreventionManager: SleepPreventionManaging {
    private(set) var state: SleepPreventionState = .inactive {
        didSet {
            onStateChange?(state)
        }
    }

    var onStateChange: ((SleepPreventionState) -> Void)?

    func start(duration: SleepPreventionDuration, now: Date) {
        state = SleepPreventionState(isActive: true, duration: duration, startedAt: now, endsAt: duration.seconds.map { now.addingTimeInterval($0) })
    }

    func stop() {
        state = .inactive
    }
}
