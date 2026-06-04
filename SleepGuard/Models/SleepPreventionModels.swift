import Foundation

enum SleepPreventionDuration: String, CaseIterable, Identifiable, Equatable {
    case fifteenMinutes
    case thirtyMinutes
    case oneHour
    case indefinite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes:
            return L("15 分钟", "15 minutes")
        case .thirtyMinutes:
            return L("30 分钟", "30 minutes")
        case .oneHour:
            return L("1 小时", "1 hour")
        case .indefinite:
            return L("无限期", "Indefinite")
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .fifteenMinutes:
            return 15 * 60
        case .thirtyMinutes:
            return 30 * 60
        case .oneHour:
            return 60 * 60
        case .indefinite:
            return nil
        }
    }
}

struct SleepPreventionState: Equatable {
    var isActive: Bool
    var duration: SleepPreventionDuration?
    var startedAt: Date?
    var endsAt: Date?

    static let inactive = SleepPreventionState(isActive: false, duration: nil, startedAt: nil, endsAt: nil)

    var statusTitle: String {
        guard isActive else {
            return L("未开启防止睡眠", "Sleep prevention is off")
        }
        return L("正在防止睡眠", "Preventing sleep")
    }

    func detailText(now: Date = Date()) -> String {
        guard isActive else {
            return L("未开启", "Off")
        }
        if let remainingSeconds = remainingSeconds(now: now) {
            return L("剩余 \(Self.localizedDuration(seconds: remainingSeconds))",
                     "\(Self.localizedDuration(seconds: remainingSeconds)) remaining")
        }
        return L("无限期", "Indefinite")
    }

    func remainingSeconds(now: Date = Date()) -> Int? {
        guard let endsAt else { return nil }
        return max(0, Int(ceil(endsAt.timeIntervalSince(now))))
    }

    private static func localizedDuration(seconds: Int) -> String {
        let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
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
