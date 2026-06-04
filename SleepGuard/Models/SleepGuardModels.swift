import Foundation
import SwiftUI

enum SleepAssertionType: String, Codable, CaseIterable, Hashable {
    case preventUserIdleSystemSleep = "PreventUserIdleSystemSleep"
    case preventSystemSleep = "PreventSystemSleep"
    case preventUserIdleDisplaySleep = "PreventUserIdleDisplaySleep"
    case internalPreventSleep = "InternalPreventSleep"
    case userIsActive = "UserIsActive"
    case backgroundTask = "BackgroundTask"
    case applePushServiceTask = "ApplePushServiceTask"
    case externalMedia = "ExternalMedia"
    case networkClientActive = "NetworkClientActive"
    case other

    init(rawPMSetValue: String) {
        self = SleepAssertionType(rawValue: rawPMSetValue) ?? .other
    }

    var displayName: String {
        switch self {
        case .preventUserIdleSystemSleep:
            return L("防止系统空闲睡眠", "Prevent User Idle System Sleep")
        case .preventSystemSleep:
            return L("防止系统睡眠", "Prevent System Sleep")
        case .preventUserIdleDisplaySleep:
            return L("防止显示器空闲睡眠", "Prevent User Idle Display Sleep")
        case .internalPreventSleep:
            return L("内部防睡眠", "Internal Prevent Sleep")
        case .userIsActive:
            return L("用户处于活动状态", "User Is Active")
        case .backgroundTask:
            return L("后台任务", "Background Task")
        case .applePushServiceTask:
            return L("Apple 推送服务任务", "Apple Push Service Task")
        case .externalMedia:
            return L("外部媒体", "External Media")
        case .networkClientActive:
            return L("网络客户端活动", "Network Client Active")
        case .other:
            return L("其他断言", "Other Assertion")
        }
    }
}

enum RiskLevel: String, Codable, CaseIterable {
    case normal
    case warning
    case critical
    case usbWarning

    var title: String {
        switch self {
        case .normal: return L("正常", "Normal")
        case .warning: return L("注意", "Warning")
        case .critical: return L("严重", "Critical")
        case .usbWarning: return L("USB 注意", "USB Warning")
        }
    }

    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .usbWarning: return .orange
        }
    }
}

enum OverallSleepStatus: String, Codable {
    case normal
    case warning
    case critical

    var title: String {
        switch self {
        case .normal: return L("正常", "Normal")
        case .warning: return L("有轻微阻止", "Minor Blocker")
        case .critical: return L("有明确阻止休眠", "Sleep Blocked")
        }
    }

    var summary: String {
        switch self {
        case .normal:
            return L("当前没有发现明确阻止自动休眠的项目。",
                     "No items found that are blocking automatic sleep.")
        case .warning:
            return L("发现短暂或常见的阻止项，建议观察是否会长期持续。",
                     "Transient or common blockers found. Monitor if they persist.")
        case .critical:
            return L("发现明确或长时间阻止休眠的项目，建议优先处理。",
                     "Persistent or explicit sleep blockers found. Address them promptly.")
        }
    }

    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

struct AssertionStatus: Codable, Equatable {
    var preventUserIdleSystemSleep = false
    var preventSystemSleep = false
    var preventUserIdleDisplaySleep = false
    var internalPreventSleep = false
    var hasKernelAssertions = false
    var values: [String: Bool] = [:]

    mutating func set(name: String, active: Bool) {
        values[name] = active
        switch SleepAssertionType(rawPMSetValue: name) {
        case .preventUserIdleSystemSleep:
            preventUserIdleSystemSleep = active
        case .preventSystemSleep:
            preventSystemSleep = active
        case .preventUserIdleDisplaySleep:
            preventUserIdleDisplaySleep = active
        case .internalPreventSleep:
            internalPreventSleep = active
        default:
            break
        }
    }
}

struct ProcessAssertion: Codable, Identifiable, Equatable {
    var id: String { "\(pid)-\(assertionType)-\(reason)-\(rawLine)" }
    let pid: Int
    let processName: String
    let duration: String
    let durationSeconds: Int?
    let assertionType: String
    let reason: String
    var timeout: String?
    let rawLine: String
}

struct KernelAssertion: Codable, Identifiable, Equatable {
    var id: String { rawLine }
    let assertionCode: String
    let owner: String
    let description: String
    let rawLine: String
}

struct ParsedAssertions: Codable, Equatable {
    var capturedAt: Date
    var systemStatus: AssertionStatus
    var processAssertions: [ProcessAssertion]
    var kernelAssertions: [KernelAssertion]
    var rawOutput: String
}

struct RiskExplanation: Codable, Equatable {
    let risk: RiskLevel
    let explanation: String
    let recommendation: String
}

struct AnalyzedProcessAssertion: Identifiable, Equatable {
    var id: String { assertion.id }
    let assertion: ProcessAssertion
    let analysis: RiskExplanation
    var trend: AssertionTrend?
}

struct AnalyzedKernelAssertion: Identifiable, Equatable {
    var id: String { assertion.id }
    let assertion: KernelAssertion
    let analysis: RiskExplanation
    var trend: AssertionTrend?
}

struct SleepDiagnosis: Equatable {
    let parsed: ParsedAssertions
    let overallStatus: OverallSleepStatus
    let processItems: [AnalyzedProcessAssertion]
    let kernelItems: [AnalyzedKernelAssertion]
    let ignoredProcessItems: [AnalyzedProcessAssertion]
    let ignoredKernelItems: [AnalyzedKernelAssertion]
    let recommendations: [String]
    let criticalCount: Int
    let warningCount: Int
    let kernelAssertionCount: Int
}

struct HistoryRecord: Codable, Identifiable, Equatable {
    var id: Date { timestamp }
    let timestamp: Date
    let status: OverallSleepStatus
    let criticalCount: Int
    let warningCount: Int
    let kernelAssertionCount: Int
    let summary: String
    var assertionSnapshots: [AssertionSnapshot]? = nil
}

enum AssertionSnapshotKind: String, Codable, Equatable {
    case process
    case kernel
}

struct AssertionSnapshot: Codable, Identifiable, Equatable {
    var id: String { signature }
    let signature: String
    let kind: AssertionSnapshotKind
    let name: String
    let detail: String
}

struct AssertionTrend: Equatable {
    let consecutiveCount: Int
    let firstSeenAt: Date
    let lastSeenAt: Date
    let observedDurationSeconds: Int

    var summary: String {
        if consecutiveCount <= 1 {
            return L("本次首次发现", "First seen this session")
        }
        return L(
            "已连续出现 \(consecutiveCount) 次，约 \(Self.formatDuration(observedDurationSeconds))",
            "Seen \(consecutiveCount) times, ~\(Self.formatDuration(observedDurationSeconds))"
        )
    }

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return L("\(max(seconds, 0)) 秒", "\(max(seconds, 0))s")
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return L("\(minutes) 分钟", "\(minutes)m")
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return L("\(hours) 小时", "\(hours)h")
        }
        return L("\(hours) 小时 \(remainingMinutes) 分钟", "\(hours)h \(remainingMinutes)m")
    }
}

enum IgnoredAssertionKind: String, Codable, Equatable {
    case process
    case kernel

    var title: String {
        switch self {
        case .process:
            return L("进程", "Process")
        case .kernel:
            return L("USB / 内核", "USB / Kernel")
        }
    }
}

struct IgnoredAssertionRule: Codable, Identifiable, Equatable {
    var id: String { signature }
    let signature: String
    let kind: IgnoredAssertionKind
    let name: String
    let detail: String
    let createdAt: Date

    var localizedDetail: String {
        guard kind == .process else { return detail }
        let separator = " · "
        guard let separatorRange = detail.range(of: separator) else { return detail }
        let originalDetail = String(detail[separatorRange.upperBound...])
        guard let assertionType = processAssertionTypeFromSignature else { return detail }
        return "\(assertionType.displayName)\(separator)\(originalDetail)"
    }

    private var processAssertionTypeFromSignature: SleepAssertionType? {
        let parts = signature.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return nil }
        let typeKey = String(parts[2])
        return SleepAssertionType.allCases.first { $0.rawValue.normalizedIgnoredRuleKey == typeKey }
    }
}

private extension String {
    var normalizedIgnoredRuleKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

enum RefreshInterval: String, CaseIterable, Identifiable {
    case ten = "10"
    case thirty = "30"
    case sixty = "60"
    case manual = "manual"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ten: return L("10 秒", "10 s")
        case .thirty: return L("30 秒", "30 s")
        case .sixty: return L("60 秒", "60 s")
        case .manual: return L("手动", "Manual")
        }
    }

    var seconds: UInt64? {
        switch self {
        case .ten: return 10
        case .thirty: return 30
        case .sixty: return 60
        case .manual: return nil
        }
    }
}

enum SleepLogEventType: String, Codable {
    case enteringSleep = "Entering Sleep"
    case wakeFrom = "Wake from"
    case wakeReason = "Wake reason"
    case darkWake = "DarkWake"

    var displayName: String {
        switch self {
        case .enteringSleep:
            return L("进入睡眠", "Entering Sleep")
        case .wakeFrom:
            return L("从睡眠唤醒", "Wake from Sleep")
        case .wakeReason:
            return L("唤醒原因", "Wake Reason")
        case .darkWake:
            return L("暗唤醒", "DarkWake")
        }
    }
}

struct SleepLogEvent: Codable, Identifiable, Equatable {
    var id: String { rawLine }
    let timestamp: Date?
    let type: SleepLogEventType
    let detail: String
    let rawLine: String
}

struct SleepLogSummary: Equatable {
    let events: [SleepLogEvent]
    let sleptLastNight: Bool
    let lastSleep: SleepLogEvent?
    let lastWake: SleepLogEvent?
    let wakeReasons: [SleepLogEvent]
    let darkWakes: [SleepLogEvent]
    let suspiciousWakeReasons: [WakeSuspicion]

    var wakeCount: Int { events.filter { $0.type == .wakeFrom }.count }
    var darkWakeCount: Int { darkWakes.count }
    var recentWakeReason: SleepLogEvent? { wakeReasons.last }
    var hasSuspiciousWake: Bool { suspiciousWakeReasons.isEmpty == false }
}

enum WakeSuspicion: String, Codable, CaseIterable, Hashable {
    case externalDevice
    case bluetooth
    case network

    var title: String {
        switch self {
        case .externalDevice:
            return L("外设", "External Device")
        case .bluetooth:
            return L("蓝牙", "Bluetooth")
        case .network:
            return L("网络", "Network")
        }
    }

    var explanation: String {
        switch self {
        case .externalDevice:
            return L("疑似外设或 USB 相关唤醒", "Possible external device or USB wake")
        case .bluetooth:
            return L("疑似蓝牙设备活动唤醒", "Possible Bluetooth device activity wake")
        case .network:
            return L("疑似网络活动或后台维护唤醒", "Possible network activity or maintenance wake")
        }
    }
}

struct AppVersionInfo: Equatable {
    let version: String
    let build: String
    let bundleIdentifier: String

    var displayText: String {
        L("版本 \(version)（构建 \(build)）", "v\(version) (build \(build))")
    }

    static func current(bundle: Bundle = .main) -> AppVersionInfo {
        let info = bundle.infoDictionary ?? [:]
        let unknown = L("未知", "Unknown")
        let version = info["CFBundleShortVersionString"] as? String ?? unknown
        let build = info["CFBundleVersion"] as? String ?? unknown
        let bundleIdentifier = bundle.bundleIdentifier ?? unknown
        return AppVersionInfo(version: version, build: build, bundleIdentifier: bundleIdentifier)
    }
}
