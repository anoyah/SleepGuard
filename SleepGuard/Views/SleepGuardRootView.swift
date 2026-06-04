import AppKit
import SwiftUI

struct SleepGuardRootView: View {
    @ObservedObject var viewModel: SleepGuardViewModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(viewModel: viewModel)
            TabView {
                CurrentStatusView(viewModel: viewModel)
                    .tabItem { Label("当前状态", systemImage: "gauge.with.dots.needle.67percent") }

                HistoryView(records: viewModel.history)
                    .tabItem { Label("历史记录", systemImage: "clock.arrow.circlepath") }

                SleepLogView(viewModel: viewModel)
                    .tabItem { Label("睡眠日志", systemImage: "bed.double") }

                SettingsView(viewModel: viewModel)
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }
            .padding(.top, 4)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct HeaderView: View {
    @ObservedObject var viewModel: SleepGuardViewModel

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill((viewModel.diagnosis?.overallStatus ?? .normal).color.opacity(0.18))
                    .frame(width: 32, height: 32)
                PulsingStatusDot(
                    color: (viewModel.diagnosis?.overallStatus ?? .normal).color,
                    isAnimating: viewModel.isRefreshing
                )
            }
            .animation(.easeInOut(duration: 0.2), value: viewModel.diagnosis?.overallStatus)

            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.diagnosis?.overallStatus.title ?? "正在检测")
                    .font(.headline.weight(.semibold))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.diagnosis?.overallStatus)
                if let lastRefresh = viewModel.lastRefresh {
                    Text("上次刷新：\(lastRefresh.formatted(date: .omitted, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await viewModel.refreshAll() }
            } label: {
                RotatingRefreshIcon(isAnimating: viewModel.isRefreshing)
            }
            .buttonStyle(.borderless)
            .help("刷新")
            .disabled(viewModel.isRefreshing)

            Button {
                viewModel.copyReport()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制诊断报告")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("退出 SleepGuard")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRefreshing)
        Divider()
    }
}

private struct CurrentStatusView: View {
    @ObservedObject var viewModel: SleepGuardViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let error = viewModel.lastError {
                    InfoCard(title: "错误", systemImage: "exclamationmark.triangle") {
                        Text(error).foregroundStyle(.red)
                    }
                    .transition(.opacity)
                }

                if let diagnosis = viewModel.diagnosis {
                    VStack(alignment: .leading, spacing: 10) {
                        SummaryCard(diagnosis: diagnosis)
                        AssertionFlagsView(status: diagnosis.parsed.systemStatus)
                        ProcessAssertionsView(items: diagnosis.processItems) { item in
                            viewModel.ignoreProcess(item)
                        }
                        KernelAssertionsView(items: diagnosis.kernelItems) { item in
                            viewModel.ignoreKernel(item)
                        }
                        IgnoredAssertionsView(
                            processItems: diagnosis.ignoredProcessItems,
                            kernelItems: diagnosis.ignoredKernelItems
                        ) { signature in
                            viewModel.removeIgnoredRule(signature: signature)
                        }
                        RecommendationsView(recommendations: diagnosis.recommendations)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if viewModel.isRefreshing {
                    ProgressView("正在读取 pmset 输出...")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    EmptyText("暂无检测结果，请点击“刷新”重试。")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }
            }
            .padding(12)
            .animation(.easeInOut(duration: 0.24), value: viewModel.diagnosis != nil)
            .animation(.easeInOut(duration: 0.18), value: viewModel.lastError)
        }
    }
}

private struct SummaryCard: View {
    let diagnosis: SleepDiagnosis

    var body: some View {
        InfoCard(title: "当前状态", systemImage: "moon.zzz") {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(diagnosis.overallStatus.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(diagnosis.overallStatus.color)
                    Text(diagnosis.overallStatus.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    CountBadge(title: "严重", value: diagnosis.criticalCount, color: .red)
                    CountBadge(title: "注意", value: diagnosis.warningCount, color: .yellow)
                    CountBadge(title: "USB", value: diagnosis.kernelAssertionCount, color: .orange)
                }
            }
        }
    }
}

private struct AssertionFlagsView: View {
    let status: AssertionStatus

    var body: some View {
        InfoCard(title: "系统断言状态", systemImage: "list.bullet.rectangle") {
            VStack(alignment: .leading, spacing: 7) {
                FlagRow(title: SleepAssertionType.preventUserIdleSystemSleep.displayName, active: status.preventUserIdleSystemSleep)
                FlagRow(title: SleepAssertionType.preventSystemSleep.displayName, active: status.preventSystemSleep)
                FlagRow(title: SleepAssertionType.preventUserIdleDisplaySleep.displayName, active: status.preventUserIdleDisplaySleep)
                FlagRow(title: SleepAssertionType.internalPreventSleep.displayName, active: status.internalPreventSleep)
                FlagRow(title: "内核断言", active: status.hasKernelAssertions)
            }
        }
    }
}

private struct FlagRow: View {
    let title: String
    let active: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: active ? "circle.fill" : "circle")
                .foregroundStyle(active ? .orange : .secondary)
                .font(.caption2)
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}

private struct ProcessAssertionsView: View {
    let items: [AnalyzedProcessAssertion]
    let onIgnore: (AnalyzedProcessAssertion) -> Void

    var body: some View {
        InfoCard(title: "阻止休眠的进程", systemImage: "app.badge") {
            if items.isEmpty {
                EmptyText("未发现进程持有休眠阻止项")
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        ProcessRow(item: item, onIgnore: onIgnore)
                        if item.id != items.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

private struct ProcessRow: View {
    let item: AnalyzedProcessAssertion
    let onIgnore: (AnalyzedProcessAssertion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.assertion.processName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("进程 ID \(item.assertion.pid)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                RiskBadge(level: item.analysis.risk)
                Button {
                    onIgnore(item)
                } label: {
                    Image(systemName: "eye.slash")
                }
                .buttonStyle(.borderless)
                .help("忽略该进程阻止项")
            }
            Text("\(SleepAssertionType(rawPMSetValue: item.assertion.assertionType).displayName) · \(item.assertion.duration)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let trend = item.trend {
                Label(trend.summary, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(item.assertion.reason)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
            Text(item.analysis.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct KernelAssertionsView: View {
    let items: [AnalyzedKernelAssertion]
    let onIgnore: (AnalyzedKernelAssertion) -> Void

    var body: some View {
        InfoCard(title: "USB 与内核断言", systemImage: "cable.connector") {
            if items.isEmpty {
                EmptyText("未发现 USB 内核断言")
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.assertion.owner)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                Spacer()
                                RiskBadge(level: item.analysis.risk)
                                Button {
                                    onIgnore(item)
                                } label: {
                                    Image(systemName: "eye.slash")
                                }
                                .buttonStyle(.borderless)
                                .help("忽略该 USB / 内核断言")
                            }
                            Text(item.assertion.assertionCode)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let trend = item.trend {
                                Label(trend.summary, systemImage: "chart.line.uptrend.xyaxis")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Text(item.analysis.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        if item.id != items.last?.id { Divider() }
                    }
                }
            }
        }
    }
}

private struct IgnoredAssertionsView: View {
    let processItems: [AnalyzedProcessAssertion]
    let kernelItems: [AnalyzedKernelAssertion]
    let onRemove: (String) -> Void

    var body: some View {
        if processItems.isEmpty == false || kernelItems.isEmpty == false {
            InfoCard(title: "已忽略项", systemImage: "eye.slash") {
                VStack(spacing: 8) {
                    ForEach(processItems) { item in
                        IgnoredItemRow(
                            title: item.assertion.processName,
                            subtitle: "\(SleepAssertionType(rawPMSetValue: item.assertion.assertionType).displayName) · \(item.assertion.reason)",
                            trend: item.trend,
                            signature: AssertionTrendAnalyzer.signature(for: item.assertion),
                            onRemove: onRemove
                        )
                        if item.id != processItems.last?.id || kernelItems.isEmpty == false { Divider() }
                    }
                    ForEach(kernelItems) { item in
                        IgnoredItemRow(
                            title: item.assertion.owner,
                            subtitle: "\(item.assertion.assertionCode) · \(item.assertion.description)",
                            trend: item.trend,
                            signature: AssertionTrendAnalyzer.signature(for: item.assertion),
                            onRemove: onRemove
                        )
                        if item.id != kernelItems.last?.id { Divider() }
                    }
                }
                Text("已忽略项未参与整体判断。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct IgnoredItemRow: View {
    let title: String
    let subtitle: String
    let trend: AssertionTrend?
    let signature: String
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    onRemove(signature)
                } label: {
                    Image(systemName: "eye")
                }
                .buttonStyle(.borderless)
                .help("取消忽略")
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let trend {
                Label(trend.summary, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecommendationsView: View {
    let recommendations: [String]

    var body: some View {
        InfoCard(title: "推荐处理建议", systemImage: "lightbulb") {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(recommendations, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .padding(.top, 3)
                        Text(item)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct HistoryView: View {
    let records: [HistoryRecord]

    var body: some View {
        List(records) { record in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(record.status.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(record.status.color)
                    Spacer()
                    Text(record.timestamp.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("严重 \(record.criticalCount) · 注意 \(record.warningCount) · USB \(record.kernelAssertionCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let assertionSnapshots = record.assertionSnapshots, assertionSnapshots.isEmpty == false {
                    Text("记录 \(assertionSnapshots.count) 个阻止项快照")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(record.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
        }
        .listStyle(.inset)
    }
}

private struct SleepLogView: View {
    @ObservedObject var viewModel: SleepGuardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if viewModel.isSleepLogRefreshing {
                    BreathingLabel("正在读取睡眠日志", systemImage: "hourglass", isAnimating: true)
                } else if let sleepLog = viewModel.sleepLog {
                    Label(
                        sleepLog.sleptLastNight ? "昨晚发现睡眠记录" : "昨晚未发现睡眠记录",
                        systemImage: sleepLog.sleptLastNight ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(sleepLog.sleptLastNight ? .green : .orange)
                } else {
                    Label("尚未读取睡眠日志", systemImage: "bed.double")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await viewModel.refreshSleepLog() }
                } label: {
                    RotatingRefreshIcon(isAnimating: viewModel.isSleepLogRefreshing)
                }
                .buttonStyle(.borderless)
                .help("刷新日志")
                .disabled(viewModel.isSleepLogRefreshing)
            }
            .padding([.top, .horizontal], 12)

            if let error = viewModel.sleepLogError {
                InfoCard(title: "睡眠日志读取失败", systemImage: "exclamationmark.triangle") {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("可以稍后重试；当前状态检测不依赖睡眠日志。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            } else if let sleepLog = viewModel.sleepLog {
                VStack(spacing: 10) {
                    SleepQualitySummaryCard(summary: sleepLog)
                        .padding(.horizontal, 12)

                    List(sleepLog.events.reversed()) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.type.displayName)
                                .font(.subheadline.weight(.semibold))
                            if let timestamp = event.timestamp {
                                Text(timestamp.formatted(date: .abbreviated, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.inset)
                }
            } else if viewModel.isSleepLogRefreshing {
                ProgressView("正在读取睡眠日志...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "bed.double")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("点击“刷新日志”读取最近 100 条睡眠/唤醒记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSleepLogRefreshing)
        .task {
            if viewModel.sleepLog == nil && viewModel.sleepLogError == nil {
                await viewModel.refreshSleepLog()
            }
        }
    }
}

private struct SleepQualitySummaryCard: View {
    let summary: SleepLogSummary

    var body: some View {
        InfoCard(title: "睡眠质量摘要", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 8) {
                SummaryMetricRow(
                    title: "昨晚是否睡眠",
                    value: summary.sleptLastNight ? "是" : "未发现",
                    color: summary.sleptLastNight ? .green : .orange
                )
                SummaryMetricRow(title: "唤醒次数", value: "\(summary.wakeCount) 次", color: summary.wakeCount == 0 ? .secondary : .orange)
                SummaryMetricRow(title: "DarkWake 次数", value: "\(summary.darkWakeCount) 次", color: summary.darkWakeCount == 0 ? .secondary : .orange)
                SummaryMetricRow(
                    title: "最近唤醒原因",
                    value: summary.recentWakeReason?.detail ?? "未发现",
                    color: summary.recentWakeReason == nil ? .secondary : .primary
                )
                SummaryMetricRow(
                    title: "疑似唤醒来源",
                    value: suspiciousWakeText,
                    color: summary.hasSuspiciousWake ? .orange : .secondary
                )
            }
        }
    }

    private var suspiciousWakeText: String {
        guard summary.suspiciousWakeReasons.isEmpty == false else {
            return "未发现明显外设/蓝牙/网络迹象"
        }
        return summary.suspiciousWakeReasons.map(\.explanation).joined(separator: "、")
    }
}

private struct SummaryMetricRow: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct PulsingStatusDot: View {
    let color: Color
    let isAnimating: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(isAnimating ? 0.35 : 0), lineWidth: 2)
                .frame(width: 20, height: 20)
                .scaleEffect(pulse && isAnimating ? 1.16 : 0.72)
                .opacity(pulse && isAnimating ? 0.15 : 0.45)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
        .onAppear {
            updatePulse()
        }
        .onChange(of: isAnimating) { _ in
            updatePulse()
        }
        .animation(.easeInOut(duration: 0.2), value: color)
    }

    private func updatePulse() {
        if isAnimating {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.18)) {
                pulse = false
            }
        }
    }
}

private struct RotatingRefreshIcon: View {
    let isAnimating: Bool
    @State private var turns = false

    var body: some View {
        Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(turns && isAnimating ? 360 : 0))
            .frame(width: 18, height: 18)
            .onAppear {
                updateRotation()
            }
            .onChange(of: isAnimating) { _ in
                updateRotation()
            }
    }

    private func updateRotation() {
        if isAnimating {
            turns = false
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                turns = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.16)) {
                turns = false
            }
        }
    }
}

private struct BreathingLabel: View {
    let title: String
    let systemImage: String
    let isAnimating: Bool
    @State private var breath = false

    init(_ title: String, systemImage: String, isAnimating: Bool) {
        self.title = title
        self.systemImage = systemImage
        self.isAnimating = isAnimating
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .opacity(breath && isAnimating ? 0.55 : 1)
            .onAppear {
                updateBreath()
            }
            .onChange(of: isAnimating) { _ in
                updateBreath()
            }
    }

    private func updateBreath() {
        if isAnimating {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                breath = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.16)) {
                breath = false
            }
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: SleepGuardViewModel
    private let versionInfo = AppVersionInfo.current()

    var body: some View {
        Form {
            Toggle(
                "登录时自动启动",
                isOn: Binding(
                    get: { viewModel.isLaunchAtLoginEnabled },
                    set: { viewModel.setLaunchAtLoginEnabled($0) }
                )
            )
            if let error = viewModel.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Picker("自动刷新", selection: $viewModel.settings.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }
            .onChange(of: viewModel.settings.refreshInterval) { _ in
                viewModel.restartAutoRefresh()
            }

            Section("已忽略规则") {
                if viewModel.settings.ignoredRules.isEmpty {
                    Text("暂无忽略规则")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.settings.ignoredRules) { rule in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(rule.kind.title) · \(rule.detail)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Button {
                                viewModel.removeIgnoredRule(rule)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("删除忽略规则")
                        }
                    }
                }
            }

            Section("版本信息") {
                HStack {
                    Text("应用版本")
                    Spacer()
                    Text(versionInfo.displayText)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Bundle ID")
                    Spacer()
                    Text(versionInfo.bundleIdentifier)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Text("SleepGuard 只读取 pmset 输出，不会终止进程或修改系统设置。危险操作只会以建议形式展示。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(12)
    }
}

private struct InfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        Text(level.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(level.color.opacity(0.18))
            .foregroundStyle(level.color)
            .clipShape(Capsule())
    }
}

private struct CountBadge: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(value > 0 ? color : .secondary.opacity(0.35))
                .frame(width: 6, height: 6)
            Text("\(title) \(value)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.04))
        .clipShape(Capsule())
    }
}

private struct EmptyText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
