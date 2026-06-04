import AppKit
import SwiftUI

struct SleepGuardRootView: View {
    @ObservedObject var viewModel: SleepGuardViewModel
    @State private var selectedTab = 0
    @State private var scrollToTopToken = 0

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(viewModel: viewModel)
            TabView(selection: $selectedTab) {
                CurrentStatusView(viewModel: viewModel, scrollToTopToken: scrollToTopToken)
                    .tabItem { Label(L("当前状态", "Status"), systemImage: "gauge.with.dots.needle.67percent") }
                    .tag(0)

                HistoryView(records: viewModel.history)
                    .tabItem { Label(L("历史记录", "History"), systemImage: "clock.arrow.circlepath") }
                    .tag(1)

                SleepLogView(viewModel: viewModel)
                    .tabItem { Label(L("睡眠日志", "Sleep Log"), systemImage: "bed.double") }
                    .tag(2)
            }
            .padding(.top, 4)
            .id(viewModel.localizationRevision)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectedTab = 0
            scrollToTopToken += 1
        }
    }
}

// MARK: - Header

private struct HeaderView: View {
    @ObservedObject var viewModel: SleepGuardViewModel
    @State private var showSettings = false
    @State private var showCopied = false

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
                Text(viewModel.diagnosis?.overallStatus.title ?? L("正在检测", "Detecting"))
                    .font(.headline.weight(.semibold))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.diagnosis?.overallStatus)
                if let lastRefresh = viewModel.lastRefresh {
                    TimelineView(.periodic(from: Date(), by: 30)) { _ in
                        Text(relativeTimeString(from: lastRefresh))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button {
                Task { await viewModel.refreshAll() }
            } label: {
                RotatingRefreshIcon(isAnimating: viewModel.isRefreshing)
            }
            .buttonStyle(.borderless)
            .help(L("刷新", "Refresh"))
            .disabled(viewModel.isRefreshing)

            Button {
                viewModel.copyReport()
                withAnimation(.easeInOut(duration: 0.15)) { showCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeInOut(duration: 0.15)) { showCopied = false }
                }
            } label: {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help(L("复制诊断报告", "Copy Diagnostic Report"))
            .foregroundStyle(showCopied ? .green : .primary)

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help(L("设置", "Settings"))
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                SettingsView(viewModel: viewModel)
                    .frame(width: 340)
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(L("退出 SleepGuard", "Quit SleepGuard"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isRefreshing)
        Divider()
    }

    private func relativeTimeString(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 10 { return L("刚刚刷新", "Just refreshed") }
        if seconds < 60 { return L("\(seconds) 秒前", "\(seconds)s ago") }
        let minutes = seconds / 60
        if minutes < 60 {
            return minutes == 1 ? L("1 分钟前", "1m ago") : L("\(minutes) 分钟前", "\(minutes)m ago")
        }
        let hours = minutes / 60
        return hours == 1 ? L("1 小时前", "1h ago") : L("\(hours) 小时前", "\(hours)h ago")
    }
}

// MARK: - Current Status

private struct CurrentStatusView: View {
    @ObservedObject var viewModel: SleepGuardViewModel
    let scrollToTopToken: Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Color.clear.frame(height: 0).id("top")
                    if let error = viewModel.lastError {
                        InfoCard(title: L("错误", "Error"), systemImage: "exclamationmark.triangle") {
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
                        ProgressView(L("正在读取 pmset 输出...", "Reading pmset output..."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        EmptyText(L("暂无检测结果，请点击\"刷新\"重试。", "No results. Click Refresh to retry."))
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding(12)
                .animation(.easeInOut(duration: 0.24), value: viewModel.diagnosis != nil)
                .animation(.easeInOut(duration: 0.18), value: viewModel.lastError)
            }
            .onChange(of: scrollToTopToken) { _ in
                proxy.scrollTo("top", anchor: .top)
            }
        }
    }
}

// MARK: - Summary Card

private struct SummaryCard: View {
    let diagnosis: SleepDiagnosis

    private var allClear: Bool {
        diagnosis.criticalCount == 0 && diagnosis.warningCount == 0 && diagnosis.kernelAssertionCount == 0
    }

    var body: some View {
        InfoCard(title: L("当前状态", "Current Status"), systemImage: "moon.zzz") {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(diagnosis.overallStatus.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(diagnosis.overallStatus.color)
                    Text(diagnosis.overallStatus.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if allClear {
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text(L("无阻断项", "No blockers"))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    VStack(alignment: .trailing, spacing: 5) {
                        CountBadge(title: L("严重", "Critical"), value: diagnosis.criticalCount, color: .red)
                        CountBadge(title: L("注意", "Warning"), value: diagnosis.warningCount, color: .yellow)
                        CountBadge(title: "USB", value: diagnosis.kernelAssertionCount, color: .orange)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: allClear)
        }
    }
}

// MARK: - Assertion Flags

private struct AssertionFlagsView: View {
    let status: AssertionStatus
    @State private var isExpanded = false

    private var anyActive: Bool {
        status.preventUserIdleSystemSleep || status.preventSystemSleep ||
        status.preventUserIdleDisplaySleep || status.internalPreventSleep ||
        status.hasKernelAssertions
    }

    var body: some View {
        InfoCard(title: L("系统断言状态", "System Assertion State"), systemImage: "list.bullet.rectangle") {
            if anyActive || isExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    FlagRow(title: SleepAssertionType.preventUserIdleSystemSleep.displayName, active: status.preventUserIdleSystemSleep)
                    FlagRow(title: SleepAssertionType.preventSystemSleep.displayName, active: status.preventSystemSleep)
                    FlagRow(title: SleepAssertionType.preventUserIdleDisplaySleep.displayName, active: status.preventUserIdleDisplaySleep)
                    FlagRow(title: SleepAssertionType.internalPreventSleep.displayName, active: status.internalPreventSleep)
                    FlagRow(title: L("内核断言", "Kernel Assertions"), active: status.hasKernelAssertions)
                    if !anyActive {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { isExpanded = false }
                        } label: {
                            Label(L("收起", "Collapse"), systemImage: "chevron.up")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .padding(.top, 2)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    Text(L("所有断言状态正常", "All assertion states are normal"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { isExpanded = true }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(L("展开详情", "Show details"))
                }
            }
        }
    }
}

private struct FlagRow: View {
    let title: String
    let active: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: active ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(active ? .orange : .green)
                .font(.caption)
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(active ? .primary : .secondary)
        }
    }
}

// MARK: - Process Assertions

private struct ProcessAssertionsView: View {
    let items: [AnalyzedProcessAssertion]
    let onIgnore: (AnalyzedProcessAssertion) -> Void
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        InfoCard(title: L("阻止休眠的进程", "Sleep-Blocking Processes"), systemImage: "app.badge") {
            if items.isEmpty {
                EmptyText(L("未发现进程持有休眠阻止项", "No processes holding sleep assertions"))
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        ProcessRow(
                            item: item,
                            isExpanded: expandedIDs.contains(item.id),
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    if expandedIDs.contains(item.id) {
                                        expandedIDs.remove(item.id)
                                    } else {
                                        expandedIDs.insert(item.id)
                                    }
                                }
                            },
                            onIgnore: onIgnore
                        )
                        if item.id != items.last?.id { Divider() }
                    }
                }
            }
        }
        .onChange(of: items) { newItems in
            let currentIDs = Set(newItems.map(\.id))
            expandedIDs = expandedIDs.intersection(currentIDs)
        }
    }
}

private struct ProcessRow: View {
    let item: AnalyzedProcessAssertion
    let isExpanded: Bool
    let onToggle: () -> Void
    let onIgnore: (AnalyzedProcessAssertion) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(item.analysis.risk.color)
                .frame(width: 3)
                .frame(minHeight: 32)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.assertion.processName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(L("PID \(item.assertion.pid)", "PID \(item.assertion.pid)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    RiskBadge(level: item.analysis.risk)
                    Button(action: onToggle) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    Button {
                        onIgnore(item)
                    } label: {
                        Image(systemName: "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help(L("忽略该进程阻止项", "Ignore this process assertion"))
                }

                Text("\(SleepAssertionType(rawPMSetValue: item.assertion.assertionType).displayName) · \(item.assertion.duration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                if isExpanded {
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Kernel Assertions

private struct KernelAssertionsView: View {
    let items: [AnalyzedKernelAssertion]
    let onIgnore: (AnalyzedKernelAssertion) -> Void
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        InfoCard(title: L("USB 与内核断言", "USB & Kernel Assertions"), systemImage: "cable.connector") {
            if items.isEmpty {
                EmptyText(L("未发现 USB 内核断言", "No USB kernel assertions found"))
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        KernelRow(
                            item: item,
                            isExpanded: expandedIDs.contains(item.id),
                            onToggle: {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    if expandedIDs.contains(item.id) {
                                        expandedIDs.remove(item.id)
                                    } else {
                                        expandedIDs.insert(item.id)
                                    }
                                }
                            },
                            onIgnore: onIgnore
                        )
                        if item.id != items.last?.id { Divider() }
                    }
                }
            }
        }
        .onChange(of: items) { newItems in
            let currentIDs = Set(newItems.map(\.id))
            expandedIDs = expandedIDs.intersection(currentIDs)
        }
    }
}

private struct KernelRow: View {
    let item: AnalyzedKernelAssertion
    let isExpanded: Bool
    let onToggle: () -> Void
    let onIgnore: (AnalyzedKernelAssertion) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(item.analysis.risk.color)
                .frame(width: 3)
                .frame(minHeight: 32)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.assertion.owner)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    RiskBadge(level: item.analysis.risk)
                    Button(action: onToggle) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    Button {
                        onIgnore(item)
                    } label: {
                        Image(systemName: "eye.slash")
                    }
                    .buttonStyle(.borderless)
                    .help(L("忽略该 USB / 内核断言", "Ignore this USB/kernel assertion"))
                }

                Text(item.assertion.assertionCode)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if isExpanded {
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ignored Assertions

private struct IgnoredAssertionsView: View {
    let processItems: [AnalyzedProcessAssertion]
    let kernelItems: [AnalyzedKernelAssertion]
    let onRemove: (String) -> Void

    var body: some View {
        if processItems.isEmpty == false || kernelItems.isEmpty == false {
            InfoCard(title: L("已忽略项", "Ignored Items"), systemImage: "eye.slash") {
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
                Text(L("已忽略项未参与整体判断。", "Ignored items are excluded from the overall assessment."))
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
                .help(L("取消忽略", "Un-ignore"))
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

// MARK: - Recommendations

private struct RecommendationsView: View {
    let recommendations: [String]

    var body: some View {
        InfoCard(title: L("推荐处理建议", "Recommendations"), systemImage: "lightbulb") {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(recommendations, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .padding(.top, 5)
                        Text(item)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

// MARK: - History

private struct HistoryView: View {
    let records: [HistoryRecord]

    var body: some View {
        if records.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(L("暂无历史记录", "No history yet"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(L("每次检测结果将自动记录在此。", "Each scan result will be recorded here automatically."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(records) { record in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(record.status.color)
                        .frame(width: 3)
                        .padding(.trailing, 10)

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
                        Text(L(
                            "严重 \(record.criticalCount) · 注意 \(record.warningCount) · USB \(record.kernelAssertionCount)",
                            "Critical \(record.criticalCount) · Warning \(record.warningCount) · USB \(record.kernelAssertionCount)"
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let assertionSnapshots = record.assertionSnapshots, assertionSnapshots.isEmpty == false {
                            Text(L(
                                "记录 \(assertionSnapshots.count) 个阻止项快照",
                                "\(assertionSnapshots.count) assertion snapshot(s) recorded"
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Text(record.status.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset)
        }
    }
}

// MARK: - Sleep Log

private struct SleepLogView: View {
    @ObservedObject var viewModel: SleepGuardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if viewModel.isSleepLogRefreshing {
                    BreathingLabel(L("正在读取睡眠日志", "Reading sleep log"), systemImage: "hourglass", isAnimating: true)
                } else if let sleepLog = viewModel.sleepLog {
                    Label(
                        sleepLog.sleptLastNight
                            ? L("昨晚发现睡眠记录", "Sleep detected last night")
                            : L("昨晚未发现睡眠记录", "No sleep detected last night"),
                        systemImage: sleepLog.sleptLastNight ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(sleepLog.sleptLastNight ? .green : .orange)
                } else {
                    Label(L("尚未读取睡眠日志", "Sleep log not loaded"), systemImage: "bed.double")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await viewModel.refreshSleepLog() }
                } label: {
                    RotatingRefreshIcon(isAnimating: viewModel.isSleepLogRefreshing)
                }
                .buttonStyle(.borderless)
                .help(L("刷新日志", "Refresh Log"))
                .disabled(viewModel.isSleepLogRefreshing)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let error = viewModel.sleepLogError {
                        InfoCard(title: L("睡眠日志读取失败", "Failed to Read Sleep Log"), systemImage: "exclamationmark.triangle") {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text(L(
                                "可以稍后重试；当前状态检测不依赖睡眠日志。",
                                "You can retry later. Status detection does not depend on the sleep log."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } else if let sleepLog = viewModel.sleepLog {
                        SleepQualitySummaryCard(summary: sleepLog)
                        SleepEventsCard(events: Array(sleepLog.events.reversed()))
                    } else if viewModel.isSleepLogRefreshing {
                        ProgressView(L("正在读取睡眠日志...", "Reading sleep log..."))
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "bed.double")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text(L(
                                "点击\"刷新日志\"读取最近 100 条睡眠/唤醒记录。",
                                "Click \"Refresh Log\" to load the last 100 sleep/wake events."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(12)
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
        InfoCard(title: L("睡眠质量摘要", "Sleep Quality Summary"), systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 8) {
                SummaryMetricRow(
                    title: L("昨晚是否睡眠", "Slept Last Night"),
                    value: summary.sleptLastNight ? L("是", "Yes") : L("未发现", "Not detected"),
                    color: summary.sleptLastNight ? .green : .orange
                )
                SummaryMetricRow(
                    title: L("唤醒次数", "Wake Count"),
                    value: L("\(summary.wakeCount) 次", "\(summary.wakeCount) time(s)"),
                    color: summary.wakeCount == 0 ? .secondary : .orange
                )
                SummaryMetricRow(
                    title: L("DarkWake 次数", "DarkWake Count"),
                    value: L("\(summary.darkWakeCount) 次", "\(summary.darkWakeCount) time(s)"),
                    color: summary.darkWakeCount == 0 ? .secondary : .orange
                )
                SummaryMetricRow(
                    title: L("最近唤醒原因", "Last Wake Reason"),
                    value: summary.recentWakeReason?.detail ?? L("未发现", "Not detected"),
                    color: summary.recentWakeReason == nil ? .secondary : .primary
                )
                SummaryMetricRow(
                    title: L("疑似唤醒来源", "Suspicious Wake"),
                    value: suspiciousWakeText,
                    color: summary.hasSuspiciousWake ? .orange : .secondary
                )
            }
        }
    }

    private var suspiciousWakeText: String {
        guard summary.suspiciousWakeReasons.isEmpty == false else {
            return L("未发现明显外设/蓝牙/网络迹象", "No suspicious device/bluetooth/network activity")
        }
        return summary.suspiciousWakeReasons.map(\.explanation).joined(separator: L("、", ", "))
    }
}

private struct SleepEventsCard: View {
    let events: [SleepLogEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L("睡眠 / 唤醒事件", "Sleep / Wake Events"), systemImage: "list.bullet.clock")
                .font(.subheadline.weight(.semibold))

            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(events) { event in
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
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if event.id != events.last?.id {
                        Divider()
                    }
                }
            }
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

// MARK: - Settings

private struct SettingsView: View {
    @ObservedObject var viewModel: SleepGuardViewModel
    private let versionInfo = AppVersionInfo.current()

    var body: some View {
        Form {
            Toggle(
                L("登录时自动启动", "Launch at Login"),
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

            Picker(L("语言", "Language"), selection: $viewModel.settings.appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }

            Picker(L("自动刷新", "Auto Refresh"), selection: $viewModel.settings.refreshInterval) {
                ForEach(RefreshInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }

            Section(L("已忽略规则", "Ignored Rules")) {
                if viewModel.settings.ignoredRules.isEmpty {
                    Text(L("暂无忽略规则", "No ignored rules"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.settings.ignoredRules) { rule in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(rule.kind.title) · \(rule.localizedDetail)")
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
                            .help(L("删除忽略规则", "Delete ignored rule"))
                        }
                    }
                }
            }

            Section(L("版本信息", "Version")) {
                HStack {
                    Text(L("应用版本", "App Version"))
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

            Text(L(
                "SleepGuard 只读取 pmset 输出，不会终止进程或修改系统设置。危险操作只会以建议形式展示。",
                "SleepGuard only reads pmset output. It never kills processes or modifies system settings. Risky actions are shown as suggestions only."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(12)
        .id(viewModel.localizationRevision)
    }
}

// MARK: - Reusable Components

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

// MARK: - Animation Helpers

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
        .onAppear { updatePulse() }
        .onChange(of: isAnimating) { _ in updatePulse() }
        .animation(.easeInOut(duration: 0.2), value: color)
    }

    private func updatePulse() {
        if isAnimating {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        } else {
            withAnimation(.easeOut(duration: 0.18)) { pulse = false }
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
            .onAppear { updateRotation() }
            .onChange(of: isAnimating) { _ in updateRotation() }
    }

    private func updateRotation() {
        if isAnimating {
            turns = false
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { turns = true }
        } else {
            withAnimation(.easeOut(duration: 0.16)) { turns = false }
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
            .onAppear { updateBreath() }
            .onChange(of: isAnimating) { _ in updateBreath() }
    }

    private func updateBreath() {
        if isAnimating {
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { breath = true }
        } else {
            withAnimation(.easeOut(duration: 0.16)) { breath = false }
        }
    }
}
