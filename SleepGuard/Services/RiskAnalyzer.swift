import Foundation

struct RiskAnalyzer {
    private let longRunningThreshold = 30 * 60

    func analyze(_ parsed: ParsedAssertions) -> SleepDiagnosis {
        let visibleProcessAssertions = parsed.processAssertions.filter { isSleepGuardPreventionAssertion($0) == false }
        let processItems = visibleProcessAssertions.map { assertion in
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

    private func isSleepGuardPreventionAssertion(_ assertion: ProcessAssertion) -> Bool {
        assertion.processName.caseInsensitiveCompare("SleepGuard") == .orderedSame
            && assertion.reason.localizedCaseInsensitiveContains("SleepGuard - Prevent")
    }

    func analyzeProcess(_ assertion: ProcessAssertion) -> RiskExplanation {
        let process = assertion.processName.lowercased()
        let reason = assertion.reason.lowercased()
        let type = assertion.assertionType
        let duration = assertion.durationSeconds ?? 0

        if process.contains("oplus_remote_service") || reason.contains("prevent sleep for my process") {
            return RiskExplanation(
                risk: .critical,
                explanation: L(
                    "OPPO/OnePlus 互联服务正在长期声明阻止休眠，常见于后台互联组件异常占用。",
                    "OPPO/OnePlus link service is holding a long-running sleep assertion, typically caused by an abnormal background component."
                ),
                recommendation: L(
                    "如果当前不需要手机互联，建议退出相关服务或在登录项中禁用；不要直接由本工具终止进程。",
                    "If phone linking is not needed, quit the service or disable it in Login Items. Do not kill processes directly from this tool."
                )
            )
        }

        if type == SleepAssertionType.preventSystemSleep.rawValue || type == SleepAssertionType.internalPreventSleep.rawValue {
            return RiskExplanation(
                risk: .critical,
                explanation: L(
                    "该断言会明确阻止系统进入睡眠。",
                    "This assertion explicitly prevents the system from sleeping."
                ),
                recommendation: L(
                    "检查该进程正在执行的任务，确认结束后再观察休眠是否恢复。",
                    "Check what task this process is running; observe whether sleep resumes after it finishes."
                )
            )
        }

        if process.contains("neteasemusic") {
            return RiskExplanation(
                risk: .warning,
                explanation: L(
                    "网易云音乐正在播放音乐，通常会正常阻止自动睡眠以避免播放中断。",
                    "NetEase Music is playing. It normally prevents auto-sleep to avoid interrupting playback."
                ),
                recommendation: L(
                    "停止播放或退出音乐应用后再次刷新。",
                    "Stop playback or quit the music app, then refresh."
                )
            )
        }

        if process.contains("coreaudiod") {
            let risk: RiskLevel = duration >= longRunningThreshold ? .critical : .warning
            return RiskExplanation(
                risk: risk,
                explanation: L(
                    "系统音频服务被输入或输出设备占用，可能来自音乐、通话、麦克风或虚拟音频设备。",
                    "The system audio service is held by an input or output device — likely music, a call, microphone, or a virtual audio device."
                ),
                recommendation: L(
                    "检查正在播放、录音、通话或使用麦克风的应用；若已持续超过 30 分钟，建议逐个退出相关音频应用。",
                    "Check apps using audio playback, recording, calls, or microphone. If this has persisted over 30 minutes, quit audio apps one by one."
                )
            )
        }

        if process.contains("backupd-helper") || process.contains("backupd") {
            return RiskExplanation(
                risk: .warning,
                explanation: L(
                    "Time Machine 或系统备份任务正在运行，短时间阻止睡眠属于正常行为。",
                    "Time Machine or a system backup is running. Briefly blocking sleep is normal."
                ),
                recommendation: L(
                    "等待备份完成；如果长时间卡住，可打开 Time Machine 设置查看进度。",
                    "Wait for the backup to finish. If stuck for a long time, check progress in Time Machine settings."
                )
            )
        }

        if process.contains("sharingd") || reason.contains("handoff") {
            return RiskExplanation(
                risk: .warning,
                explanation: L(
                    "Apple 接力或共享服务正在活动，可能由附近设备或剪贴板触发。",
                    "Apple Handoff or a sharing service is active, possibly triggered by a nearby device or clipboard."
                ),
                recommendation: L(
                    "如果频繁出现，可临时关闭接力功能后观察。",
                    "If this appears frequently, try disabling Handoff temporarily and observe."
                )
            )
        }

        if process.contains("bluetoothd") || reason.contains("btstack") || reason.contains("bluetooth") {
            return RiskExplanation(
                risk: .warning,
                explanation: L(
                    "蓝牙设备活动正在影响空闲判断，常见于键盘、鼠标、耳机或蓝牙连接请求。",
                    "Bluetooth device activity is affecting idle detection — common with keyboards, mice, headphones, or Bluetooth connection requests."
                ),
                recommendation: L(
                    "检查蓝牙外设是否频繁唤醒或断连重连。",
                    "Check whether Bluetooth peripherals are frequently waking or reconnecting."
                )
            )
        }

        if process.contains("powerd") {
            return RiskExplanation(
                risk: .normal,
                explanation: L(
                    "屏幕亮着时 powerd 阻止系统空闲睡眠属于正常系统行为。",
                    "powerd blocking idle sleep while the screen is on is normal system behavior."
                ),
                recommendation: L(
                    "让屏幕熄灭或降低显示器睡眠时间后再观察。",
                    "Let the screen turn off or reduce the display sleep timeout, then observe."
                )
            )
        }

        if type == SleepAssertionType.preventUserIdleSystemSleep.rawValue && duration >= longRunningThreshold {
            return RiskExplanation(
                risk: .critical,
                explanation: L(
                    "未知进程长时间声明防止系统空闲睡眠，可能明确阻止自动休眠。",
                    "An unknown process has held a prevent-idle-sleep assertion for a long time, likely blocking automatic sleep."
                ),
                recommendation: L(
                    "确认该进程用途；如果不是正在执行的重要任务，建议手动退出相关应用后复查。",
                    "Identify this process. If it is not doing important work, quit the app manually and re-check."
                )
            )
        }

        if type == SleepAssertionType.preventUserIdleSystemSleep.rawValue || type == SleepAssertionType.preventUserIdleDisplaySleep.rawValue {
            return RiskExplanation(
                risk: .warning,
                explanation: L(
                    "该进程正在短暂阻止空闲睡眠或显示器睡眠。",
                    "This process is briefly blocking idle or display sleep."
                ),
                recommendation: L(
                    "观察持续时间是否继续增长；超过 30 分钟仍存在时再重点排查。",
                    "Monitor whether the duration keeps growing. Investigate further if it persists beyond 30 minutes."
                )
            )
        }

        return RiskExplanation(
            risk: .normal,
            explanation: L(
                "当前看起来是系统正常的短暂活动。",
                "This appears to be normal, transient system activity."
            ),
            recommendation: L("通常无需处理。", "Usually no action required.")
        )
    }

    func analyzeKernel(_ assertion: KernelAssertion) -> RiskExplanation {
        let owner = assertion.owner.lowercased()
        let explanation: String
        if owner.contains("generic billboard device") {
            explanation = L(
                "Generic Billboard Device 通常是 USB-C 扩展坞或转接器协商设备，可能影响睡眠。",
                "Generic Billboard Device is typically a USB-C dock or adapter negotiation device that may affect sleep."
            )
        } else if owner.contains("hub") || owner.contains("dongle") || owner.contains("adapter") {
            explanation = L(
                "USB Hub、鼠标接收器或多口转接器可能持续触发 USB 内核断言。",
                "A USB hub, dongle, or multi-port adapter may be continuously triggering USB kernel assertions."
            )
        } else {
            explanation = L(
                "USB 外设持有内核断言，可能影响 Mac 进入或维持睡眠。",
                "A USB peripheral is holding a kernel assertion that may prevent the Mac from entering or maintaining sleep."
            )
        }
        return RiskExplanation(
            risk: .usbWarning,
            explanation: explanation,
            recommendation: L(
                "建议逐个拔掉 USB-C 扩展坞、Hub、鼠标接收器或多口转接器，然后刷新确认。",
                "Try unplugging USB-C docks, hubs, dongles, and multi-port adapters one by one, then refresh to confirm."
            )
        )
    }

    private func buildRecommendations(
        processItems: [AnalyzedProcessAssertion],
        kernelItems: [AnalyzedKernelAssertion],
        overallStatus: OverallSleepStatus
    ) -> [String] {
        var items: [String] = []
        if overallStatus == .normal {
            items.append(L(
                "当前无需处理。若 Mac 仍未休眠，可查看\"睡眠日志\"确认是否被频繁唤醒。",
                "No action needed. If your Mac still won't sleep, check the Sleep Log tab for frequent wake events."
            ))
        }
        if processItems.contains(where: { $0.analysis.risk == .critical }) {
            items.append(L(
                "优先处理红色项目：手动退出对应应用或关闭其后台登录项，然后刷新验证。",
                "Address critical (red) items first: quit the app or disable its Login Item, then refresh to verify."
            ))
        }
        if kernelItems.isEmpty == false {
            items.append(L(
                "USB 内核断言建议用排除法处理：先拔掉扩展坞/Hub/接收器，再逐个接回。",
                "For USB kernel assertions, use process of elimination: unplug your dock/hub/dongle, then reconnect devices one by one."
            ))
        }
        if processItems.contains(where: { $0.assertion.processName.lowercased().contains("coreaudiod") }) {
            items.append(L(
                "音频相关阻止项可通过停止播放、结束通话、关闭录音或断开虚拟音频设备排查。",
                "Audio-related blockers can be resolved by stopping playback, ending calls, stopping recordings, or disconnecting virtual audio devices."
            ))
        }
        if items.isEmpty {
            items.append(L(
                "继续观察持续时间；短暂活动通常会自动释放。",
                "Continue monitoring the duration. Transient activity typically releases on its own."
            ))
        }
        return Array(Set(items)).sorted()
    }
}
