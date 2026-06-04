import Foundation

struct AssertionTrendAnalyzer {
    func attachTrends(to diagnosis: SleepDiagnosis, history: [HistoryRecord], now: Date) -> SleepDiagnosis {
        let snapshots = Self.makeSnapshots(from: diagnosis)
        let trends = makeTrends(for: snapshots, history: history, now: now)

        let processItems = diagnosis.processItems.map { item in
            var item = item
            item.trend = trends[Self.signature(for: item.assertion)]
            return item
        }

        let kernelItems = diagnosis.kernelItems.map { item in
            var item = item
            item.trend = trends[Self.signature(for: item.assertion)]
            return item
        }

        return SleepDiagnosis(
            parsed: diagnosis.parsed,
            overallStatus: diagnosis.overallStatus,
            processItems: processItems,
            kernelItems: kernelItems,
            ignoredProcessItems: diagnosis.ignoredProcessItems,
            ignoredKernelItems: diagnosis.ignoredKernelItems,
            recommendations: diagnosis.recommendations,
            criticalCount: diagnosis.criticalCount,
            warningCount: diagnosis.warningCount,
            kernelAssertionCount: diagnosis.kernelAssertionCount
        )
    }

    static func makeSnapshots(from diagnosis: SleepDiagnosis) -> [AssertionSnapshot] {
        let processSnapshots = diagnosis.processItems.map { item in
            AssertionSnapshot(
                signature: signature(for: item.assertion),
                kind: .process,
                name: item.assertion.processName,
                detail: "\(item.assertion.assertionType) · \(item.assertion.reason)"
            )
        }

        let kernelSnapshots = diagnosis.kernelItems.map { item in
            AssertionSnapshot(
                signature: signature(for: item.assertion),
                kind: .kernel,
                name: item.assertion.owner,
                detail: "\(item.assertion.assertionCode) · \(item.assertion.description)"
            )
        }

        return processSnapshots + kernelSnapshots
    }

    static func signature(for assertion: ProcessAssertion) -> String {
        [
            "process",
            assertion.processName.normalizedTrendKey,
            assertion.assertionType.normalizedTrendKey,
            assertion.reason.normalizedTrendKey
        ].joined(separator: "|")
    }

    static func signature(for assertion: KernelAssertion) -> String {
        [
            "kernel",
            assertion.owner.normalizedTrendKey,
            assertion.assertionCode.normalizedTrendKey
        ].joined(separator: "|")
    }

    private func makeTrends(for snapshots: [AssertionSnapshot], history: [HistoryRecord], now: Date) -> [String: AssertionTrend] {
        var trends: [String: AssertionTrend] = [:]
        let signatures = Set(snapshots.map(\.signature))

        for signature in signatures {
            var count = 1
            var firstSeenAt = now

            for record in history.reversed() {
                guard record.assertionSnapshots?.contains(where: { $0.signature == signature }) == true else {
                    break
                }
                count += 1
                firstSeenAt = record.timestamp
            }

            trends[signature] = AssertionTrend(
                consecutiveCount: count,
                firstSeenAt: firstSeenAt,
                lastSeenAt: now,
                observedDurationSeconds: max(0, Int(now.timeIntervalSince(firstSeenAt)))
            )
        }

        return trends
    }
}

private extension String {
    var normalizedTrendKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
