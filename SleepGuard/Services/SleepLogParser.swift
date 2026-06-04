import Foundation

struct SleepLogParser {
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()

    func parse(_ output: String, now: Date = Date()) -> SleepLogSummary {
        let events = output
            .components(separatedBy: .newlines)
            .compactMap(parseLine)
            .suffix(100)

        let eventArray = Array(events)
        let lastNightInterval = Self.lastNightInterval(now: now)
        let sleptLastNight = eventArray.contains { event in
            guard event.type == .enteringSleep, let timestamp = event.timestamp else { return false }
            return lastNightInterval.contains(timestamp)
        }

        return SleepLogSummary(
            events: eventArray,
            sleptLastNight: sleptLastNight,
            lastSleep: eventArray.last(where: { $0.type == .enteringSleep }),
            lastWake: eventArray.last(where: { $0.type == .wakeFrom }),
            wakeReasons: eventArray.filter { $0.type == .wakeReason },
            darkWakes: eventArray.filter { $0.type == .darkWake },
            suspiciousWakeReasons: Self.suspiciousWakeReasons(from: eventArray)
        )
    }

    private func parseLine(_ rawLine: String) -> SleepLogEvent? {
        let targets: [(String, SleepLogEventType)] = [
            ("Entering Sleep", .enteringSleep),
            ("Wake reason", .wakeReason),
            ("DarkWake", .darkWake),
            ("Wake from", .wakeFrom)
        ]

        guard let target = targets.first(where: { rawLine.contains($0.0) }) else { return nil }
        let timestamp = parseTimestamp(from: rawLine)
        let detail: String
        if let range = rawLine.range(of: target.0) {
            detail = String(rawLine[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            detail = rawLine.trimmingCharacters(in: .whitespaces)
        }
        return SleepLogEvent(timestamp: timestamp, type: target.1, detail: detail, rawLine: rawLine)
    }

    private func parseTimestamp(from line: String) -> Date? {
        guard line.count >= 25 else { return nil }
        let prefix = String(line.prefix(25))
        return formatter.date(from: prefix)
    }

    private static func lastNightInterval(now: Date) -> DateInterval {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterdayStart) ?? yesterdayStart
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: todayStart) ?? todayStart
        return DateInterval(start: evening, end: morning)
    }

    private static func suspiciousWakeReasons(from events: [SleepLogEvent]) -> [WakeSuspicion] {
        let relevantText = events
            .filter { $0.type == .wakeReason || $0.type == .wakeFrom || $0.type == .darkWake }
            .map(\.rawLine)
            .joined(separator: "\n")
            .lowercased()

        var reasons: [WakeSuspicion] = []
        if containsAny(["bluetooth", "btstack", "bt.", "bthid"], in: relevantText) {
            reasons.append(.bluetooth)
        }
        if containsAny(["usb", "xhc", "ehc", "hid", "keyboard", "mouse", "trackpad", "external", "acattach"], in: relevantText) {
            reasons.append(.externalDevice)
        }
        if containsAny(["network", "tcpkeepalive", "wlan", "wifi", "airport", "en0", "arp", "bonjour", "maintenance"], in: relevantText) {
            reasons.append(.network)
        }
        return reasons
    }

    private static func containsAny(_ keywords: [String], in text: String) -> Bool {
        keywords.contains { text.contains($0) }
    }
}
