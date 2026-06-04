import Foundation

struct ReportGenerator {
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    func makeReport(diagnosis: SleepDiagnosis?, sleepLog: SleepLogSummary?) -> String {
        var lines: [String] = []
        let versionInfo = AppVersionInfo.current()
        lines.append(L("SleepGuard 诊断报告", "SleepGuard Diagnostic Report"))
        lines.append(L("应用版本：\(versionInfo.displayText)", "App Version: \(versionInfo.displayText)"))
        lines.append(L("生成时间：\(formatter.string(from: Date()))", "Generated: \(formatter.string(from: Date()))"))
        lines.append("")

        if let diagnosis {
            lines.append(L("整体判断：\(diagnosis.overallStatus.title)", "Overall Status: \(diagnosis.overallStatus.title)"))
            lines.append(L("摘要：\(diagnosis.overallStatus.summary)", "Summary: \(diagnosis.overallStatus.summary)"))
            lines.append(L("严重项目：\(diagnosis.criticalCount)", "Critical: \(diagnosis.criticalCount)"))
            lines.append(L("注意项目：\(diagnosis.warningCount)", "Warning: \(diagnosis.warningCount)"))
            lines.append(L("内核断言：\(diagnosis.kernelAssertionCount)", "Kernel Assertions: \(diagnosis.kernelAssertionCount)"))
            lines.append("")

            lines.append(L("系统范围断言状态：", "System-wide Assertion State:"))
            lines.append("- \(SleepAssertionType.preventUserIdleSystemSleep.displayName): \(diagnosis.parsed.systemStatus.preventUserIdleSystemSleep ? "1" : "0")")
            lines.append("- \(SleepAssertionType.preventSystemSleep.displayName): \(diagnosis.parsed.systemStatus.preventSystemSleep ? "1" : "0")")
            lines.append("- \(SleepAssertionType.preventUserIdleDisplaySleep.displayName): \(diagnosis.parsed.systemStatus.preventUserIdleDisplaySleep ? "1" : "0")")
            lines.append("- \(SleepAssertionType.internalPreventSleep.displayName): \(diagnosis.parsed.systemStatus.internalPreventSleep ? "1" : "0")")
            lines.append("- \(L("内核断言", "Kernel Assertions")): \(diagnosis.parsed.systemStatus.hasKernelAssertions ? "1" : "0")")
            lines.append("")

            lines.append(L("进程阻止项：", "Process Assertions:"))
            if diagnosis.processItems.isEmpty {
                lines.append(L("- 无", "- None"))
            } else {
                for item in diagnosis.processItems {
                    let assertion = item.assertion
                    lines.append("- \(assertion.processName) PID=\(assertion.pid) \(L("类型", "type"))=\(SleepAssertionType(rawPMSetValue: assertion.assertionType).displayName) \(L("持续时间", "duration"))=\(assertion.duration) \(L("风险", "risk"))=\(item.analysis.risk.title)")
                    if let trend = item.trend {
                        lines.append("  \(L("连续出现", "Seen")): \(trend.summary)")
                    }
                    lines.append("  \(L("原始类型", "Raw type")): \(assertion.assertionType)")
                    lines.append("  \(L("原始原因", "Raw reason")): \(assertion.reason)")
                    lines.append("  \(L("解释", "Explanation")): \(item.analysis.explanation)")
                    lines.append("  \(L("建议", "Recommendation")): \(item.analysis.recommendation)")
                }
            }
            lines.append("")

            lines.append(L("内核断言：", "Kernel Assertions:"))
            if diagnosis.kernelItems.isEmpty {
                lines.append(L("- 无", "- None"))
            } else {
                for item in diagnosis.kernelItems {
                    lines.append("- \(L("设备", "device"))=\(item.assertion.owner) \(L("代码", "code"))=\(item.assertion.assertionCode)")
                    if let trend = item.trend {
                        lines.append("  \(L("连续出现", "Seen")): \(trend.summary)")
                    }
                    lines.append("  \(L("描述", "Description")): \(item.assertion.description)")
                    lines.append("  \(L("原始行", "Raw line")): \(item.assertion.rawLine)")
                    lines.append("  \(L("解释", "Explanation")): \(item.analysis.explanation)")
                    lines.append("  \(L("建议", "Recommendation")): \(item.analysis.recommendation)")
                }
            }
            lines.append("")

            if diagnosis.ignoredProcessItems.isEmpty == false || diagnosis.ignoredKernelItems.isEmpty == false {
                lines.append(L("已忽略项：", "Ignored Items:"))
                lines.append(L("说明：已忽略项未参与整体判断。", "Note: Ignored items are excluded from the overall assessment."))
                for item in diagnosis.ignoredProcessItems {
                    let assertion = item.assertion
                    lines.append("- \(assertion.processName) PID=\(assertion.pid) \(L("类型", "type"))=\(SleepAssertionType(rawPMSetValue: assertion.assertionType).displayName) \(L("风险", "risk"))=\(item.analysis.risk.title)")
                    if let trend = item.trend {
                        lines.append("  \(L("连续出现", "Seen")): \(trend.summary)")
                    }
                    lines.append("  \(L("原始类型", "Raw type")): \(assertion.assertionType)")
                    lines.append("  \(L("原始原因", "Raw reason")): \(assertion.reason)")
                }
                for item in diagnosis.ignoredKernelItems {
                    lines.append("- \(L("设备", "device"))=\(item.assertion.owner) \(L("代码", "code"))=\(item.assertion.assertionCode) \(L("风险", "risk"))=\(item.analysis.risk.title)")
                    if let trend = item.trend {
                        lines.append("  \(L("连续出现", "Seen")): \(trend.summary)")
                    }
                    lines.append("  \(L("描述", "Description")): \(item.assertion.description)")
                    lines.append("  \(L("原始行", "Raw line")): \(item.assertion.rawLine)")
                }
                lines.append("")
            }

            lines.append(L("推荐处理建议：", "Recommendations:"))
            diagnosis.recommendations.forEach { lines.append("- \($0)") }
        } else {
            lines.append(L("整体判断：暂无检测结果", "Overall Status: No results yet"))
        }

        if let sleepLog {
            lines.append("")
            lines.append(L("睡眠日志：", "Sleep Log:"))
            lines.append(L(
                "昨晚是否进入睡眠：\(sleepLog.sleptLastNight ? "是" : "未发现")",
                "Slept last night: \(sleepLog.sleptLastNight ? "Yes" : "Not detected")"
            ))
            lines.append(L("唤醒次数：\(sleepLog.wakeCount)", "Wake count: \(sleepLog.wakeCount)"))
            lines.append(L("DarkWake 次数：\(sleepLog.darkWakeCount)", "DarkWake count: \(sleepLog.darkWakeCount)"))
            if let lastSleep = sleepLog.lastSleep {
                lines.append(L("最近睡眠：\(lastSleep.rawLine)", "Last sleep: \(lastSleep.rawLine)"))
            }
            if let lastWake = sleepLog.lastWake {
                lines.append(L("最近唤醒：\(lastWake.rawLine)", "Last wake: \(lastWake.rawLine)"))
            }
            if let wakeReason = sleepLog.wakeReasons.last {
                lines.append(L("最近唤醒原因：\(wakeReason.rawLine)", "Last wake reason: \(wakeReason.rawLine)"))
            }
            if sleepLog.suspiciousWakeReasons.isEmpty {
                lines.append(L(
                    "疑似唤醒来源：未发现明显外设/蓝牙/网络迹象",
                    "Suspicious wake: No suspicious device/bluetooth/network activity"
                ))
            } else {
                let reasons = sleepLog.suspiciousWakeReasons.map(\.explanation).joined(separator: L("、", ", "))
                lines.append(L("疑似唤醒来源：\(reasons)", "Suspicious wake: \(reasons)"))
            }
        }

        return lines.joined(separator: "\n")
    }
}
