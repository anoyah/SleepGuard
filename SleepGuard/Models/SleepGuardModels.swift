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
            return "防止系统空闲睡眠"
        case .preventSystemSleep:
            return "防止系统睡眠"
        case .preventUserIdleDisplaySleep:
            return "防止显示器空闲睡眠"
        case .internalPreventSleep:
            return "内部防睡眠"
        case .userIsActive:
            return "用户处于活动状态"
        case .backgroundTask:
            return "后台任务"
        case .applePushServiceTask:
            return "Apple 推送服务任务"
        case .externalMedia:
            return "外部媒体"
        case .networkClientActive:
            return "网络客户端活动"
        case .other:
            return "其他断言"
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
        case .normal: return "正常"
        case .warning: return "注意"
        case .critical: return "严重"
        case .usbWarning: return "USB 注意"
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
        case .normal: return "正常"
        case .warning: return "有轻微阻止"
        case .critical: return "有明确阻止休眠"
        }
    }

    var summary: String {
        switch self {
        case .normal:
            return "当前没有发现明确阻止自动休眠的项目。"
        case .warning:
            return "发现短暂或常见的阻止项，建议观察是否会长期持续。"
        case .critical:
            return "发现明确或长时间阻止休眠的项目，建议优先处理。"
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
            return "本次首次发现"
        }
        return "已连续出现 \(consecutiveCount) 次，约 \(Self.formatDuration(observedDurationSeconds))"
    }

    private static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(max(seconds, 0)) 秒"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) 分钟"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours) 小时"
        }
        return "\(hours) 小时 \(remainingMinutes) 分钟"
    }
}

enum IgnoredAssertionKind: String, Codable, Equatable {
    case process
    case kernel

    var title: String {
        switch self {
        case .process:
            return "进程"
        case .kernel:
            return "USB / 内核"
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
}

enum RefreshInterval: String, CaseIterable, Identifiable {
    case ten = "10"
    case thirty = "30"
    case sixty = "60"
    case manual = "manual"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ten: return "10 秒"
        case .thirty: return "30 秒"
        case .sixty: return "60 秒"
        case .manual: return "手动"
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
            return "进入睡眠"
        case .wakeFrom:
            return "从睡眠唤醒"
        case .wakeReason:
            return "唤醒原因"
        case .darkWake:
            return "暗唤醒"
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
            return "外设"
        case .bluetooth:
            return "蓝牙"
        case .network:
            return "网络"
        }
    }

    var explanation: String {
        switch self {
        case .externalDevice:
            return "疑似外设或 USB 相关唤醒"
        case .bluetooth:
            return "疑似蓝牙设备活动唤醒"
        case .network:
            return "疑似网络活动或后台维护唤醒"
        }
    }
}

struct AppVersionInfo: Equatable {
    let version: String
    let build: String
    let bundleIdentifier: String

    var displayText: String {
        "版本 \(version)（构建 \(build)）"
    }

    static func current(bundle: Bundle = .main) -> AppVersionInfo {
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "未知"
        let build = info["CFBundleVersion"] as? String ?? "未知"
        let bundleIdentifier = bundle.bundleIdentifier ?? "未知"
        return AppVersionInfo(version: version, build: build, bundleIdentifier: bundleIdentifier)
    }
}
