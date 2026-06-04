import Foundation

struct ReportGenerator {
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    func makeReport(diagnosis: SleepDiagnosis?, sleepLog: SleepLogSummary?) -> String {
        var lines: [String] = []
        let versionInfo = AppVersionInfo.current()
        lines.append("SleepGuard 诊断报告")
        lines.append("应用版本：\(versionInfo.displayText)")
        lines.append("生成时间：\(formatter.string(from: Date()))")
        lines.append("")

        if let diagnosis {
            lines.append("整体判断：\(diagnosis.overallStatus.title)")
            lines.append("摘要：\(diagnosis.overallStatus.summary)")
            lines.append("严重项目：\(diagnosis.criticalCount)")
            lines.append("注意项目：\(diagnosis.warningCount)")
            lines.append("内核断言：\(diagnosis.kernelAssertionCount)")
            lines.append("")

            lines.append("系统范围断言状态：")
            lines.append("- \(SleepAssertionType.preventUserIdleSystemSleep.displayName)：\(diagnosis.parsed.systemStatus.preventUserIdleSystemSleep ? "1" : "0")")
            lines.append("- \(SleepAssertionType.preventSystemSleep.displayName)：\(diagnosis.parsed.systemStatus.preventSystemSleep ? "1" : "0")")
            lines.append("- \(SleepAssertionType.preventUserIdleDisplaySleep.displayName)：\(diagnosis.parsed.systemStatus.preventUserIdleDisplaySleep ? "1" : "0")")
            lines.append("- \(SleepAssertionType.internalPreventSleep.displayName)：\(diagnosis.parsed.systemStatus.internalPreventSleep ? "1" : "0")")
            lines.append("- 内核断言：\(diagnosis.parsed.systemStatus.hasKernelAssertions ? "1" : "0")")
            lines.append("")

            lines.append("进程阻止项：")
            if diagnosis.processItems.isEmpty {
                lines.append("- 无")
            } else {
                for item in diagnosis.processItems {
                    let assertion = item.assertion
                    lines.append("- \(assertion.processName) 进程 ID=\(assertion.pid) 类型=\(SleepAssertionType(rawPMSetValue: assertion.assertionType).displayName) 持续时间=\(assertion.duration) 风险=\(item.analysis.risk.title)")
                    if let trend = item.trend {
                        lines.append("  连续出现：\(trend.summary)")
                    }
                    lines.append("  原始类型：\(assertion.assertionType)")
                    lines.append("  原始原因：\(assertion.reason)")
                    lines.append("  解释：\(item.analysis.explanation)")
                    lines.append("  建议：\(item.analysis.recommendation)")
                }
            }
            lines.append("")

            lines.append("内核断言：")
            if diagnosis.kernelItems.isEmpty {
                lines.append("- 无")
            } else {
                for item in diagnosis.kernelItems {
                    lines.append("- 设备=\(item.assertion.owner) 代码=\(item.assertion.assertionCode)")
                    if let trend = item.trend {
                        lines.append("  连续出现：\(trend.summary)")
                    }
                    lines.append("  描述：\(item.assertion.description)")
                    lines.append("  原始行：\(item.assertion.rawLine)")
                    lines.append("  解释：\(item.analysis.explanation)")
                    lines.append("  建议：\(item.analysis.recommendation)")
                }
            }
            lines.append("")

            if diagnosis.ignoredProcessItems.isEmpty == false || diagnosis.ignoredKernelItems.isEmpty == false {
                lines.append("已忽略项：")
                lines.append("说明：已忽略项未参与整体判断。")
                for item in diagnosis.ignoredProcessItems {
                    let assertion = item.assertion
                    lines.append("- \(assertion.processName) 进程 ID=\(assertion.pid) 类型=\(SleepAssertionType(rawPMSetValue: assertion.assertionType).displayName) 风险=\(item.analysis.risk.title)")
                    if let trend = item.trend {
                        lines.append("  连续出现：\(trend.summary)")
                    }
                    lines.append("  原始类型：\(assertion.assertionType)")
                    lines.append("  原始原因：\(assertion.reason)")
                }
                for item in diagnosis.ignoredKernelItems {
                    lines.append("- 设备=\(item.assertion.owner) 代码=\(item.assertion.assertionCode) 风险=\(item.analysis.risk.title)")
                    if let trend = item.trend {
                        lines.append("  连续出现：\(trend.summary)")
                    }
                    lines.append("  描述：\(item.assertion.description)")
                    lines.append("  原始行：\(item.assertion.rawLine)")
                }
                lines.append("")
            }

            lines.append("推荐处理建议：")
            diagnosis.recommendations.forEach { lines.append("- \($0)") }
        } else {
            lines.append("整体判断：暂无检测结果")
        }

        if let sleepLog {
            lines.append("")
            lines.append("睡眠日志：")
            lines.append("昨晚是否进入睡眠：\(sleepLog.sleptLastNight ? "是" : "未发现")")
            lines.append("唤醒次数：\(sleepLog.wakeCount)")
            lines.append("DarkWake 次数：\(sleepLog.darkWakeCount)")
            if let lastSleep = sleepLog.lastSleep {
                lines.append("最近睡眠：\(lastSleep.rawLine)")
            }
            if let lastWake = sleepLog.lastWake {
                lines.append("最近唤醒：\(lastWake.rawLine)")
            }
            if let wakeReason = sleepLog.wakeReasons.last {
                lines.append("最近唤醒原因：\(wakeReason.rawLine)")
            }
            if sleepLog.suspiciousWakeReasons.isEmpty {
                lines.append("疑似唤醒来源：未发现明显外设/蓝牙/网络迹象")
            } else {
                let reasons = sleepLog.suspiciousWakeReasons.map(\.explanation).joined(separator: "、")
                lines.append("疑似唤醒来源：\(reasons)")
            }
        }

        return lines.joined(separator: "\n")
    }
}
