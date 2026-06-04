import Foundation

struct IgnoredAssertionMatcher {
    func apply(rules: [IgnoredAssertionRule], to diagnosis: SleepDiagnosis) -> SleepDiagnosis {
        let signatures = Set(rules.map(\.signature))

        let activeProcessItems = diagnosis.processItems.filter {
            signatures.contains(AssertionTrendAnalyzer.signature(for: $0.assertion)) == false
        }
        let ignoredProcessItems = diagnosis.processItems.filter {
            signatures.contains(AssertionTrendAnalyzer.signature(for: $0.assertion))
        }
        let activeKernelItems = diagnosis.kernelItems.filter {
            signatures.contains(AssertionTrendAnalyzer.signature(for: $0.assertion)) == false
        }
        let ignoredKernelItems = diagnosis.kernelItems.filter {
            signatures.contains(AssertionTrendAnalyzer.signature(for: $0.assertion))
        }

        let criticalCount = activeProcessItems.filter { $0.analysis.risk == .critical }.count
        let warningCount = activeProcessItems.filter { $0.analysis.risk == .warning }.count
        let kernelAssertionCount = activeKernelItems.count
        let overallStatus = overallStatus(
            diagnosis: diagnosis,
            activeProcessItems: activeProcessItems,
            ignoredProcessItems: ignoredProcessItems,
            activeKernelItems: activeKernelItems,
            ignoredKernelItems: ignoredKernelItems,
            criticalCount: criticalCount,
            warningCount: warningCount,
            kernelAssertionCount: kernelAssertionCount
        )

        return SleepDiagnosis(
            parsed: diagnosis.parsed,
            overallStatus: overallStatus,
            processItems: activeProcessItems,
            kernelItems: activeKernelItems,
            ignoredProcessItems: ignoredProcessItems,
            ignoredKernelItems: ignoredKernelItems,
            recommendations: recommendations(
                processItems: activeProcessItems,
                kernelItems: activeKernelItems,
                ignoredProcessItems: ignoredProcessItems,
                ignoredKernelItems: ignoredKernelItems,
                overallStatus: overallStatus
            ),
            criticalCount: criticalCount,
            warningCount: warningCount,
            kernelAssertionCount: kernelAssertionCount
        )
    }

    static func rule(for item: AnalyzedProcessAssertion, createdAt: Date = Date()) -> IgnoredAssertionRule {
        IgnoredAssertionRule(
            signature: AssertionTrendAnalyzer.signature(for: item.assertion),
            kind: .process,
            name: item.assertion.processName,
            detail: "\(SleepAssertionType(rawPMSetValue: item.assertion.assertionType).displayName) · \(item.assertion.reason)",
            createdAt: createdAt
        )
    }

    static func rule(for item: AnalyzedKernelAssertion, createdAt: Date = Date()) -> IgnoredAssertionRule {
        IgnoredAssertionRule(
            signature: AssertionTrendAnalyzer.signature(for: item.assertion),
            kind: .kernel,
            name: item.assertion.owner,
            detail: "\(item.assertion.assertionCode) · \(item.assertion.description)",
            createdAt: createdAt
        )
    }

    func matches(_ rule: IgnoredAssertionRule, process assertion: ProcessAssertion) -> Bool {
        rule.signature == AssertionTrendAnalyzer.signature(for: assertion)
    }

    func matches(_ rule: IgnoredAssertionRule, kernel assertion: KernelAssertion) -> Bool {
        rule.signature == AssertionTrendAnalyzer.signature(for: assertion)
    }

    private func overallStatus(
        diagnosis: SleepDiagnosis,
        activeProcessItems: [AnalyzedProcessAssertion],
        ignoredProcessItems: [AnalyzedProcessAssertion],
        activeKernelItems: [AnalyzedKernelAssertion],
        ignoredKernelItems: [AnalyzedKernelAssertion],
        criticalCount: Int,
        warningCount: Int,
        kernelAssertionCount: Int
    ) -> OverallSleepStatus {
        let hasAnyListedItem = activeProcessItems.isEmpty == false
            || ignoredProcessItems.isEmpty == false
            || activeKernelItems.isEmpty == false
            || ignoredKernelItems.isEmpty == false

        if criticalCount > 0 {
            return .critical
        }
        if hasAnyListedItem == false && (diagnosis.parsed.systemStatus.preventSystemSleep || diagnosis.parsed.systemStatus.internalPreventSleep) {
            return .critical
        }
        if warningCount > 0 || kernelAssertionCount > 0 {
            return .warning
        }
        if hasAnyListedItem == false && (diagnosis.parsed.systemStatus.preventUserIdleSystemSleep || diagnosis.parsed.systemStatus.preventUserIdleDisplaySleep) {
            return .warning
        }
        return .normal
    }

    private func recommendations(
        processItems: [AnalyzedProcessAssertion],
        kernelItems: [AnalyzedKernelAssertion],
        ignoredProcessItems: [AnalyzedProcessAssertion],
        ignoredKernelItems: [AnalyzedKernelAssertion],
        overallStatus: OverallSleepStatus
    ) -> [String] {
        var items: [String] = []
        if overallStatus == .normal {
            items.append("当前无需处理。若 Mac 仍未休眠，可查看“睡眠日志”确认是否被频繁唤醒。")
        }
        if processItems.contains(where: { $0.analysis.risk == .critical }) {
            items.append("优先处理红色项目：手动退出对应应用或关闭其后台登录项，然后刷新验证。")
        }
        if kernelItems.isEmpty == false {
            items.append("USB 内核断言建议用排除法处理：先拔掉扩展坞/Hub/接收器，再逐个接回。")
        }
        if processItems.contains(where: { $0.assertion.processName.lowercased().contains("coreaudiod") }) {
            items.append("音频相关阻止项可通过停止播放、结束通话、关闭录音或断开虚拟音频设备排查。")
        }
        if ignoredProcessItems.isEmpty == false || ignoredKernelItems.isEmpty == false {
            items.append("已忽略项未参与整体判断；如现象仍存在，可在设置中取消忽略后复查。")
        }
        if items.isEmpty {
            items.append("继续观察持续时间；短暂活动通常会自动释放。")
        }
        return Array(Set(items)).sorted()
    }
}
