import Foundation

struct RiskAnalyzer {
    private let longRunningThreshold = 30 * 60

    func analyze(_ parsed: ParsedAssertions) -> SleepDiagnosis {
        let processItems = parsed.processAssertions.map { assertion in
            AnalyzedProcessAssertion(assertion: assertion, analysis: analyzeProcess(assertion), trend: nil)
        }
        let kernelItems = parsed.kernelAssertions.map { assertion in
            AnalyzedKernelAssertion(assertion: assertion, analysis: analyzeKernel(assertion), trend: nil)
        }

        let criticalCount = processItems.filter { $0.analysis.risk == .critical }.count
        let warningCount = processItems.filter { $0.analysis.risk == .warning }.count
        let kernelAssertionCount = kernelItems.count

        let overallStatus: OverallSleepStatus
        if criticalCount > 0 || parsed.systemStatus.preventSystemSleep || parsed.systemStatus.internalPreventSleep {
            overallStatus = .critical
        } else if warningCount > 0 || kernelAssertionCount > 0 || parsed.systemStatus.preventUserIdleSystemSleep || parsed.systemStatus.preventUserIdleDisplaySleep {
            overallStatus = .warning
        } else {
            overallStatus = .normal
        }

        let recommendations = buildRecommendations(
            processItems: processItems,
            kernelItems: kernelItems,
            overallStatus: overallStatus
        )

        return SleepDiagnosis(
            parsed: parsed,
            overallStatus: overallStatus,
            processItems: processItems,
            kernelItems: kernelItems,
            ignoredProcessItems: [],
            ignoredKernelItems: [],
            recommendations: recommendations,
            criticalCount: criticalCount,
            warningCount: warningCount,
            kernelAssertionCount: kernelAssertionCount
        )
    }

    func analyzeProcess(_ assertion: ProcessAssertion) -> RiskExplanation {
        let process = assertion.processName.lowercased()
        let reason = assertion.reason.lowercased()
        let type = assertion.assertionType
        let duration = assertion.durationSeconds ?? 0

        if process.contains("oplus_remote_service") || reason.contains("prevent sleep for my process") {
            return RiskExplanation(
                risk: .critical,
                explanation: "OPPO/OnePlus 互联服务正在长期声明阻止休眠，常见于后台互联组件异常占用。",
                recommendation: "如果当前不需要手机互联，建议退出相关服务或在登录项中禁用；不要直接由本工具终止进程。"
            )
        }

        if type == SleepAssertionType.preventSystemSleep.rawValue || type == SleepAssertionType.internalPreventSleep.rawValue {
            return RiskExplanation(
                risk: .critical,
                explanation: "该断言会明确阻止系统进入睡眠。",
                recommendation: "检查该进程正在执行的任务，确认结束后再观察休眠是否恢复。"
            )
        }

        if process.contains("neteasemusic") {
            return RiskExplanation(
                risk: .warning,
                explanation: "网易云音乐正在播放音乐，通常会正常阻止自动睡眠以避免播放中断。",
                recommendation: "停止播放或退出音乐应用后再次刷新。"
            )
        }

        if process.contains("coreaudiod") {
            let risk: RiskLevel = duration >= longRunningThreshold ? .critical : .warning
            return RiskExplanation(
                risk: risk,
                explanation: "系统音频服务被输入或输出设备占用，可能来自音乐、通话、麦克风或虚拟音频设备。",
                recommendation: "检查正在播放、录音、通话或使用麦克风的应用；若已持续超过 30 分钟，建议逐个退出相关音频应用。"
            )
        }

        if process.contains("backupd-helper") || process.contains("backupd") {
            return RiskExplanation(
                risk: .warning,
                explanation: "Time Machine 或系统备份任务正在运行，短时间阻止睡眠属于正常行为。",
                recommendation: "等待备份完成；如果长时间卡住，可打开 Time Machine 设置查看进度。"
            )
        }

        if process.contains("sharingd") || reason.contains("handoff") {
            return RiskExplanation(
                risk: .warning,
                explanation: "Apple 接力或共享服务正在活动，可能由附近设备或剪贴板触发。",
                recommendation: "如果频繁出现，可临时关闭接力功能后观察。"
            )
        }

        if process.contains("bluetoothd") || reason.contains("btstack") || reason.contains("bluetooth") {
            return RiskExplanation(
                risk: .warning,
                explanation: "蓝牙设备活动正在影响空闲判断，常见于键盘、鼠标、耳机或蓝牙连接请求。",
                recommendation: "检查蓝牙外设是否频繁唤醒或断连重连。"
            )
        }

        if process.contains("powerd") {
            return RiskExplanation(
                risk: .normal,
                explanation: "屏幕亮着时 powerd 阻止系统空闲睡眠属于正常系统行为。",
                recommendation: "让屏幕熄灭或降低显示器睡眠时间后再观察。"
            )
        }

        if type == SleepAssertionType.preventUserIdleSystemSleep.rawValue && duration >= longRunningThreshold {
            return RiskExplanation(
                risk: .critical,
                explanation: "未知进程长时间声明防止系统空闲睡眠，可能明确阻止自动休眠。",
                recommendation: "确认该进程用途；如果不是正在执行的重要任务，建议手动退出相关应用后复查。"
            )
        }

        if type == SleepAssertionType.preventUserIdleSystemSleep.rawValue || type == SleepAssertionType.preventUserIdleDisplaySleep.rawValue {
            return RiskExplanation(
                risk: .warning,
                explanation: "该进程正在短暂阻止空闲睡眠或显示器睡眠。",
                recommendation: "观察持续时间是否继续增长；超过 30 分钟仍存在时再重点排查。"
            )
        }

        return RiskExplanation(
            risk: .normal,
            explanation: "当前看起来是系统正常的短暂活动。",
            recommendation: "通常无需处理。"
        )
    }

    func analyzeKernel(_ assertion: KernelAssertion) -> RiskExplanation {
        let owner = assertion.owner.lowercased()
        let explanation: String
        if owner.contains("generic billboard device") {
            explanation = "Generic Billboard Device 通常是 USB-C 扩展坞或转接器协商设备，可能影响睡眠。"
        } else if owner.contains("hub") || owner.contains("dongle") || owner.contains("adapter") {
            explanation = "USB Hub、鼠标接收器或多口转接器可能持续触发 USB 内核断言。"
        } else {
            explanation = "USB 外设持有内核断言，可能影响 Mac 进入或维持睡眠。"
        }
        return RiskExplanation(
            risk: .usbWarning,
            explanation: explanation,
            recommendation: "建议逐个拔掉 USB-C 扩展坞、Hub、鼠标接收器或多口转接器，然后刷新确认。"
        )
    }

    private func buildRecommendations(
        processItems: [AnalyzedProcessAssertion],
        kernelItems: [AnalyzedKernelAssertion],
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
        if items.isEmpty {
            items.append("继续观察持续时间；短暂活动通常会自动释放。")
        }
        return Array(Set(items)).sorted()
    }
}
