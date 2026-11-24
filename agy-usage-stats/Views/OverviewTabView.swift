//
//  OverviewTabView.swift
//  agy-usage-stats
//
//  Created by Antigravity on 10/17/26.
//

import SwiftUI

public struct OverviewTabView: View {
    @Environment(\.colorScheme) var colorScheme
    let viewModel: AgyStatsViewModel

    public enum CostTimeframe: String, CaseIterable, Identifiable {
        case today = "Today"
        case week = "Last 7 Days"
        case month = "Last 30 Days"
        case all = "All Costs"

        public var id: String { rawValue }

        var compactLabel: String {
            switch self {
            case .today: return "Today"
            case .week: return "7d"
            case .month: return "30d"
            case .all: return "All"
            }
        }
    }

    private enum ResolvedTabSelection {
        case subscription(SubscriptionAccountSummary)
        case gcp(project: String)
        case all
    }

    @State private var selectedTimeframe: CostTimeframe = .today
    @AppStorage("agy_selectedAccountTabId") private var selectedAccountTabId: String = "auto"
    @State private var selectedBucketId: String? = nil
    @State private var hoveredBucketId: String? = nil

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let snapshotRelativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var theme: ThemeColors { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme) }

    public init(viewModel: AgyStatsViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Static Computation Helpers (Tested & Shared)

    public static func filterBuckets(for timeframe: CostTimeframe, in allBuckets: [UsageTimeBucket]) -> [UsageTimeBucket] {
        switch timeframe {
        case .today:
            if let last = allBuckets.last {
                return [last]
            }
            return []
        case .week:
            return Array(allBuckets.suffix(7))
        case .month:
            return Array(allBuckets.suffix(30))
        case .all:
            return allBuckets
        }
    }

    public static func pinnedBucket(for selectedId: String?, in buckets: [UsageTimeBucket]) -> UsageTimeBucket? {
        guard let id = selectedId else { return nil }
        return buckets.first(where: { $0.id == id })
    }

    public static func bucketCost(_ bucket: UsageTimeBucket, account: AccountFilter) -> Double {
        switch account {
        case .all: return bucket.totalCost
        case .subscription: return bucket.quotaCost
        case .gcp: return bucket.gcpCost
        }
    }

    public static func bucketTokens(_ bucket: UsageTimeBucket, account: AccountFilter) -> Int {
        switch account {
        case .all: return bucket.inputTokens + bucket.outputTokens
        case .subscription: return bucket.quotaInputTokens + bucket.quotaOutputTokens
        case .gcp: return bucket.gcpInputTokens + bucket.gcpOutputTokens
        }
    }

    public static func bucketQueries(_ bucket: UsageTimeBucket, account: AccountFilter) -> Int {
        switch account {
        case .all: return bucket.queryCount
        case .subscription: return bucket.quotaQueryCount
        case .gcp: return bucket.gcpQueryCount
        }
    }

    public static func bucketModelBreakdown(_ bucket: UsageTimeBucket, account: AccountFilter) -> [String: Double] {
        switch account {
        case .all: return bucket.consolidatedModelBreakdown
        case .subscription: return bucket.consolidatedQuotaModelBreakdown
        case .gcp: return bucket.consolidatedGcpModelBreakdown
        }
    }

    public static func peakBucket(in buckets: [UsageTimeBucket], account: AccountFilter) -> UsageTimeBucket? {
        computePeakBucket(in: buckets, account: account)
    }

    public static func computePeakBucket(in buckets: [UsageTimeBucket], account: AccountFilter) -> UsageTimeBucket? {
        let nonZero = buckets.filter { b in
            switch account {
            case .all: return b.totalCost > 0
            case .subscription: return b.quotaCost > 0
            case .gcp: return b.gcpCost > 0
            }
        }
        return nonZero.max { a, b in
            bucketCost(a, account: account) < bucketCost(b, account: account)
        }
    }

    static func computeTickIndices(totalCount: Int) -> [Int] {
        guard totalCount > 1 else { return totalCount == 1 ? [0] : [] }
        if totalCount <= 7 {
            return Array(0..<totalCount)
        }
        let step = max(5, min(8, totalCount / 4))
        var indices: [Int] = []
        var current = 0
        while current < totalCount - 3 {
            indices.append(current)
            current += step
        }
        if indices.last != totalCount - 1 {
            indices.append(totalCount - 1)
        }
        return indices
    }

    public static func formattedActiveAccountSpendParts(
        summaries: [SubscriptionAccountSummary],
        spendForSummary: (SubscriptionAccountSummary) -> Double
    ) -> [String] {
        summaries.compactMap { summary in
            let spend = spendForSummary(summary)
            guard spend > 0.005 else { return nil }
            return String(format: "\(summary.email): $%.2f", spend)
        }
    }

    public static func resolveSelectedTabId(
        storedId: String,
        primaryTabs: [AccountTabItem],
        overflowSubscriptions: [SubscriptionAccountSummary]
    ) -> String {
        if storedId != "auto" {
            if primaryTabs.contains(where: { $0.id == storedId }) {
                return storedId
            }
            if storedId.hasPrefix("sub:") {
                let emailKey = String(storedId.dropFirst(4)).lowercased()
                if overflowSubscriptions.contains(where: { $0.id == emailKey }) {
                    return "sub:\(emailKey)"
                }
            }
        }

        if let activeSub = primaryTabs.first(where: {
            if case .subscription(_, _, _, let isActive) = $0 { return isActive }
            return false
        }) {
            return activeSub.id
        }
        if let firstSub = primaryTabs.first(where: {
            if case .subscription = $0 { return true }
            return false
        }) {
            return firstSub.id
        }
        return AccountTabItem.all.id
    }

    public static func accountCost(in bucket: UsageTimeBucket, emailKey: String) -> Double {
        let lower = emailKey.lowercased()
        return bucket.accountCostBreakdown.reduce(0.0) { partial, item in
            item.key.lowercased() == lower ? partial + item.value : partial
        }
    }

    public static func accountQueries(in bucket: UsageTimeBucket, emailKey: String) -> Int {
        let lower = emailKey.lowercased()
        return bucket.accountQueryBreakdown.reduce(0) { partial, item in
            item.key.lowercased() == lower ? partial + item.value : partial
        }
    }

    public static func accountTokens(in bucket: UsageTimeBucket, emailKey: String) -> Int {
        let lower = emailKey.lowercased()
        let direct = bucket.accountTokenBreakdown.reduce(0) { partial, item in
            item.key.lowercased() == lower ? partial + item.value : partial
        }
        if direct > 0 { return direct }
        let cost = accountCost(in: bucket, emailKey: lower)
        if cost > 0 && bucket.quotaCost > 0 {
            let quotaTokens = bucket.quotaInputTokens + bucket.quotaOutputTokens
            return Int(Double(quotaTokens) * (cost / bucket.quotaCost))
        }
        return 0
    }

    public static func accountModelBreakdown(in bucket: UsageTimeBucket, emailKey: String) -> [String: Double] {
        let lower = emailKey.lowercased()
        var result: [String: Double] = [:]
        for (acc, models) in bucket.accountModelBreakdown where acc.lowercased() == lower {
            for (rawModel, cost) in models where cost > 0 {
                let canonical = canonicalModelDisplayName(from: rawModel)
                result[canonical, default: 0.0] += cost
            }
        }
        if !result.isEmpty {
            return result
        }
        let cost = accountCost(in: bucket, emailKey: lower)
        if cost > 0 && bucket.quotaCost > 0 {
            let ratio = cost / bucket.quotaCost
            for (model, modelCost) in bucket.consolidatedQuotaModelBreakdown {
                result[model, default: 0.0] += modelCost * ratio
            }
        }
        return result
    }

    public static func accountSummaryMetrics(
        emailKey: String,
        timeframe: CostTimeframe,
        allBuckets: [UsageTimeBucket],
        pinnedBucket: UsageTimeBucket? = nil,
        summaryTotalCost: Double? = nil,
        summaryTotalQueries: Int? = nil
    ) -> (cost: Double, tokens: Int, queries: Int, modelBreakdown: [String: Double]) {
        let filtered = filterBuckets(for: timeframe, in: allBuckets)
        let sourceBuckets = pinnedBucket.map { [$0] } ?? filtered

        var cost = sourceBuckets.reduce(0.0) { $0 + accountCost(in: $1, emailKey: emailKey) }
        let tokens = sourceBuckets.reduce(0) { $0 + accountTokens(in: $1, emailKey: emailKey) }
        var queries = sourceBuckets.reduce(0) { $0 + accountQueries(in: $1, emailKey: emailKey) }

        if pinnedBucket == nil && timeframe == .all {
            if let summaryTotalCost { cost = max(cost, summaryTotalCost) }
            if let summaryTotalQueries { queries = max(queries, summaryTotalQueries) }
        }

        var breakdown: [String: Double] = [:]
        for bucket in sourceBuckets {
            for (model, modelCost) in accountModelBreakdown(in: bucket, emailKey: emailKey) {
                breakdown[model, default: 0.0] += modelCost
            }
        }
        return (cost, tokens, queries, breakdown)
    }

    // MARK: - Single-Pass Per-Render Snapshot (Eliminates Repeated O(N) & O(N^2) View Recomputations)

    private struct RenderSnapshot {
        let summaries: [SubscriptionAccountSummary]
        let primaryTabs: [AccountTabItem]
        let overflowSubscriptions: [SubscriptionAccountSummary]
        let activeTabId: String
        let selection: ResolvedTabSelection
        let accountFilter: AccountFilter
        let activeBuckets: [UsageTimeBucket]
        let pinnedBucket: UsageTimeBucket?
        let hoveredBucket: UsageTimeBucket?
        let inspectedBucket: UsageTimeBucket?
        let bucketCostsById: [String: Double]
        let peakBucket: UsageTimeBucket?
        let maxBucketCost: Double
        let totalCost: Double
        let totalTokens: Int
        let totalQueries: Int
        let modelRows: [ModelRowData]
        let timeframeSubscriptionSpend: Double
        let timeframeGcpSpend: Double
    }

    private func buildRenderSnapshot() -> RenderSnapshot {
        let summaries = viewModel.subscriptionAccountSummaries
        let tabs = viewModel.primaryAccountTabs
        let overflow = viewModel.overflowUnusedSubscriptions
        let activeId = Self.resolveSelectedTabId(
            storedId: selectedAccountTabId,
            primaryTabs: tabs,
            overflowSubscriptions: overflow
        )

        let selection: ResolvedTabSelection
        let accountFilter: AccountFilter
        if activeId == "gcp" {
            selection = .gcp(project: viewModel.stats.gcpProject ?? "clawdbot-485304")
            accountFilter = .gcp
        } else if activeId.hasPrefix("sub:") {
            let emailKey = String(activeId.dropFirst(4)).lowercased()
            if let summary = summaries.first(where: { $0.id == emailKey }) {
                selection = .subscription(summary)
                accountFilter = .subscription
            } else {
                selection = .all
                accountFilter = .all
            }
        } else {
            selection = .all
            accountFilter = .all
        }

        let buckets = Self.filterBuckets(for: selectedTimeframe, in: viewModel.stats.dailyUsage)
        let pinned = Self.pinnedBucket(for: selectedBucketId, in: buckets)
        let hovered: UsageTimeBucket? = hoveredBucketId.flatMap { hid in buckets.first(where: { $0.id == hid }) }
        let inspected = hovered ?? pinned

        var bucketCostsById: [String: Double] = [:]
        bucketCostsById.reserveCapacity(buckets.count)
        var peak: UsageTimeBucket? = nil
        var peakCost: Double = 0.0
        for b in buckets {
            let c: Double
            if case .subscription(let summary) = selection {
                c = Self.accountCost(in: b, emailKey: summary.id)
            } else {
                c = Self.bucketCost(b, account: accountFilter)
            }
            bucketCostsById[b.id] = c
            if c > peakCost {
                peakCost = c
                peak = b
            }
        }
        let maxCost = max(0.0001, peakCost)

        let cost: Double
        let tokens: Int
        let queries: Int
        let breakdown: [String: Double]

        switch selection {
        case .subscription(let summary):
            let metrics = Self.accountSummaryMetrics(
                emailKey: summary.id,
                timeframe: selectedTimeframe,
                allBuckets: viewModel.stats.dailyUsage,
                pinnedBucket: pinned,
                summaryTotalCost: summary.totalCost,
                summaryTotalQueries: summary.totalQueries
            )
            if pinned == nil && selectedTimeframe == .today && buckets.isEmpty {
                cost = max(metrics.cost, summary.todayCost)
                queries = max(metrics.queries, summary.todayQueries)
            } else {
                cost = metrics.cost
                queries = metrics.queries
            }
            tokens = metrics.tokens
            breakdown = metrics.modelBreakdown

        case .gcp:
            if let pinned {
                cost = pinned.gcpCost
                tokens = Self.bucketTokens(pinned, account: .gcp)
                queries = Self.bucketQueries(pinned, account: .gcp)
                breakdown = Self.bucketModelBreakdown(pinned, account: .gcp)
            } else {
                let aggGcp = buckets.aggregatedGcpCost
                if selectedTimeframe == .all && viewModel.stats.gcpTotalCost > aggGcp {
                    cost = viewModel.stats.gcpTotalCost
                } else if selectedTimeframe == .today && buckets.isEmpty {
                    cost = viewModel.stats.gcpTodayCost
                } else {
                    cost = aggGcp
                }
                tokens = buckets.aggregatedGcpTokens
                queries = buckets.aggregatedGcpQueryCount
                breakdown = buckets.aggregatedGcpModelBreakdown
            }

        case .all:
            if let pinned {
                cost = pinned.totalCost
                tokens = Self.bucketTokens(pinned, account: .all)
                queries = Self.bucketQueries(pinned, account: .all)
                breakdown = Self.bucketModelBreakdown(pinned, account: .all)
            } else {
                let aggTotal = buckets.aggregatedTotalCost
                if selectedTimeframe == .all && viewModel.stats.totalCostEstimate > aggTotal {
                    cost = viewModel.stats.totalCostEstimate
                } else {
                    cost = aggTotal
                }
                let aggTokens = buckets.aggregatedInputTokens + buckets.aggregatedOutputTokens
                if selectedTimeframe == .all && aggTokens == 0 && viewModel.stats.totalQueries > 0 {
                    tokens = viewModel.stats.totalQueries * 85_000
                } else {
                    tokens = aggTokens
                }
                let aggQueries = buckets.aggregatedQueryCount
                queries = (selectedTimeframe == .all) ? max(viewModel.stats.totalQueries, aggQueries) : aggQueries
                breakdown = buckets.aggregatedModelBreakdown
            }
        }

        let safeTotalCost = max(0.0001, cost)
        let safeTotalTokens = max(1, tokens)
        let rows: [ModelRowData] = breakdown
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { item in
                let pct = (item.value / safeTotalCost) * 100.0
                let estimatedTokens = Int(Double(safeTotalTokens) * (pct / 100.0))
                return ModelRowData(
                    id: item.key,
                    name: item.key,
                    cost: item.value,
                    percentage: pct,
                    tokens: estimatedTokens
                )
            }

        let subSpend: Double
        let gcpSpend: Double
        if let pinned {
            subSpend = pinned.quotaCost
            gcpSpend = pinned.gcpCost
        } else {
            let aggQuota = buckets.aggregatedQuotaCost
            subSpend = (selectedTimeframe == .all && viewModel.stats.quotaTotalCost > aggQuota)
                ? viewModel.stats.quotaTotalCost
                : aggQuota
            let aggGcp = buckets.aggregatedGcpCost
            if selectedTimeframe == .all && viewModel.stats.gcpTotalCost > aggGcp {
                gcpSpend = viewModel.stats.gcpTotalCost
            } else if selectedTimeframe == .today && buckets.isEmpty {
                gcpSpend = viewModel.stats.gcpTodayCost
            } else {
                gcpSpend = aggGcp
            }
        }

        return RenderSnapshot(
            summaries: summaries,
            primaryTabs: tabs,
            overflowSubscriptions: overflow,
            activeTabId: activeId,
            selection: selection,
            accountFilter: accountFilter,
            activeBuckets: buckets,
            pinnedBucket: pinned,
            hoveredBucket: hovered,
            inspectedBucket: inspected,
            bucketCostsById: bucketCostsById,
            peakBucket: peak,
            maxBucketCost: maxCost,
            totalCost: cost,
            totalTokens: tokens,
            totalQueries: queries,
            modelRows: rows,
            timeframeSubscriptionSpend: subSpend,
            timeframeGcpSpend: gcpSpend
        )
    }

    public var pinnedBucket: UsageTimeBucket? {
        let buckets = Self.filterBuckets(for: selectedTimeframe, in: viewModel.stats.dailyUsage)
        return Self.pinnedBucket(for: selectedBucketId, in: buckets)
    }

    private func effectiveBucketTokens(_ bucket: UsageTimeBucket, snapshot: RenderSnapshot) -> Int {
        if case .subscription(let summary) = snapshot.selection {
            return Self.accountTokens(in: bucket, emailKey: summary.id)
        }
        return Self.bucketTokens(bucket, account: snapshot.accountFilter)
    }

    private func effectiveBucketQueries(_ bucket: UsageTimeBucket, snapshot: RenderSnapshot) -> Int {
        if case .subscription(let summary) = snapshot.selection {
            return Self.accountQueries(in: bucket, emailKey: summary.id)
        }
        return Self.bucketQueries(bucket, account: snapshot.accountFilter)
    }

    private struct ModelRowData: Identifiable {
        let id: String
        let name: String
        let cost: Double
        let percentage: Double
        let tokens: Int
    }

    // MARK: - Main Body

    public var body: some View {
        let snapshot = buildRenderSnapshot()

        VStack(spacing: 0) {
            accountTabStrip(snapshot: snapshot)

            Rectangle()
                .fill(theme.divider)
                .frame(height: 1)

            ScrollView {
                VStack(spacing: 10) {
                    switch snapshot.selection {
                    case .subscription(let summary):
                        subscriptionTabBody(summary: summary, snapshot: snapshot)
                    case .gcp(let project):
                        gcpTabBody(project: project, snapshot: snapshot)
                    case .all:
                        allTabBody(snapshot: snapshot)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(theme.surfacePrimary)
        }
        .background(theme.surfacePrimary)
        .onChange(of: selectedTimeframe) { _, _ in
            selectedBucketId = nil
            hoveredBucketId = nil
        }
        .onChange(of: selectedAccountTabId) { _, _ in
            selectedBucketId = nil
            hoveredBucketId = nil
        }
    }

    // MARK: - Option B Sticky Account-First Top Tabs

    private func accountTabStrip(snapshot: RenderSnapshot) -> some View {
        let tabs = snapshot.primaryTabs
        let overflow = snapshot.overflowSubscriptions
        let activeId = snapshot.activeTabId

        return HStack(spacing: 5) {
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    let isSelected = (activeId == tab.id)
                    Button {
                        selectAccountTab(tab.id)
                    } label: {
                        HStack(spacing: 4) {
                            if case .subscription(_, _, _, let isActive) = tab, isActive {
                                Circle()
                                    .fill(theme.costGreen)
                                    .frame(width: 5, height: 5)
                            }
                            Text(tabLabel(for: tab))
                                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isSelected ? theme.cardFillHovered : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? theme.cardStroke : Color.clear, lineWidth: 0.75)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if case .subscription(let email, _, _, let isActive) = tab, !isActive {
                            Button {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                                    viewModel.setAccountHidden(true, for: email)
                                    if selectedAccountTabId == tab.id {
                                        selectedAccountTabId = "auto"
                                    }
                                }
                            } label: {
                                Label("Hide from top bar", systemImage: "eye.slash")
                            }
                        } else if case .all = tab, tabs.count > 1 {
                            Button {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                                    viewModel.showAllAccountTab = false
                                    if selectedAccountTabId == "all" {
                                        selectedAccountTabId = "auto"
                                    }
                                }
                            } label: {
                                Label("Hide 'All' tab", systemImage: "eye.slash")
                            }
                        }
                    }
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.surfaceSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.cardStroke.opacity(0.65), lineWidth: 0.75)
            )

            if !overflow.isEmpty {
                overflowChip(overflow: overflow, activeId: activeId)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surfacePrimary)
    }

    @ViewBuilder
    private func overflowChip(overflow: [SubscriptionAccountSummary], activeId: String) -> some View {
        let isOverflowSelected = overflow.contains { "sub:\($0.id)" == activeId }

        if overflow.count == 1, let single = overflow.first {
            Button {
                selectAccountTab("sub:\(single.id)")
            } label: {
                Text("+1")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isOverflowSelected ? theme.geminiAccent : theme.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isOverflowSelected ? theme.geminiAccent.opacity(0.16) : theme.surfaceSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isOverflowSelected ? theme.geminiAccent.opacity(0.45) : theme.cardStroke.opacity(0.65), lineWidth: 0.75)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .help("\(single.email) (Unused — right-click to hide)")
            .contextMenu {
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                        viewModel.setAccountHidden(true, for: single.email)
                        if selectedAccountTabId == "sub:\(single.id)" {
                            selectedAccountTabId = "auto"
                        }
                    }
                } label: {
                    Label("Hide \(single.email)", systemImage: "eye.slash")
                }
            }
        } else {
            Menu {
                ForEach(overflow) { sub in
                    Button {
                        selectAccountTab("sub:\(sub.id)")
                    } label: {
                        HStack {
                            Text(sub.email)
                            if let tier = AgyStatsViewModel.shortTierName(for: sub.plan) {
                                Text("(\(tier))")
                            }
                        }
                    }
                }
            } label: {
                Text("+\(overflow.count)")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isOverflowSelected ? theme.geminiAccent : theme.textSecondary)
                    .padding(.horizontal, 9)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isOverflowSelected ? theme.geminiAccent.opacity(0.16) : theme.surfaceSecondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(isOverflowSelected ? theme.geminiAccent.opacity(0.45) : theme.cardStroke.opacity(0.65), lineWidth: 0.75)
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func tabLabel(for tab: AccountTabItem) -> String {
        switch tab {
        case .subscription(_, let label, _, _):
            return label
        case .gcp:
            return "GCP"
        case .all:
            return "All"
        }
    }

    private func selectAccountTab(_ tabId: String) {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
            selectedAccountTabId = tabId
            selectedBucketId = nil
            hoveredBucketId = nil
        }
    }

    // MARK: - Case 1: Subscription Account View

    @ViewBuilder
    private func subscriptionTabBody(summary: SubscriptionAccountSummary, snapshot: RenderSnapshot) -> some View {
        subscriptionIdentityAndQuotaPanel(summary: summary)

        if !summary.isActive && !summary.hasAnyHistoricalUsage {
            unusedOverflowActionsPanel(summary: summary)
        } else {
            spendSummaryPanel(accentColor: theme.costGreen, snapshot: snapshot) {
                if let pinned = snapshot.pinnedBucket {
                    return "\(pinned.label) · Pinned day"
                }
                if selectedTimeframe == .today {
                    return summary.weeklyCost > 0.005
                        ? String(format: "Today · 7d $%.2f", summary.weeklyCost)
                        : "Today"
                }
                return "\(selectedTimeframe.rawValue) · \(snapshot.activeBuckets.count)d"
            }

            modelsPanel(title: "SPEND BY MODEL", snapshot: snapshot)
        }
    }

    private func subscriptionIdentityAndQuotaPanel(summary: SubscriptionAccountSummary) -> some View {
        let quota: AgyQuotaInfo? = {
            if summary.isActive {
                return viewModel.stats.quotaInfo ?? summary.quotaInfo
            }
            return summary.quotaInfo
        }()

        let tierLabel: String? = {
            if let short = AgyStatsViewModel.shortTierName(for: summary.plan) {
                return short.uppercased()
            }
            if let raw = summary.plan?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
                return raw.uppercased()
            }
            return nil
        }()

        let hasUnstartedWeeklyTimer: Bool = {
            guard summary.isActive, let quota else { return false }
            return quota.groups.contains { group in
                group.buckets.contains { !$0.disabled && $0.isWeeklyBucket && $0.isWindowTimerIdle() }
            }
        }()

        return VStack(spacing: 0) {
            // Identity Header Row
            HStack(spacing: 6) {
                Circle()
                    .fill(summary.isActive ? theme.costGreen : theme.textTertiary.opacity(0.55))
                    .frame(width: 6, height: 6)

                Text(summary.email)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 4)

                HStack(spacing: 5) {
                    if let tierLabel {
                        let tierColor = tierLabel == "ULTRA" ? theme.geminiAccent : (tierLabel == "PRO" ? theme.costGreen : theme.textSecondary)
                        pillBadge(tierLabel, foreground: tierColor, background: tierColor.opacity(0.14))
                    }

                    if !summary.isActive {
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                                viewModel.setAccountHidden(true, for: summary.email)
                                selectedAccountTabId = "auto"
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "eye.slash")
                                    .font(.system(size: 8.5, weight: .semibold))
                                Text("Hide")
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(theme.surfaceSecondary))
                            .overlay(Capsule().stroke(theme.cardStroke, lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Hide this account from the top bar (can be re-enabled in Settings)")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Rectangle().fill(theme.divider).frame(height: 1)

            // Full-Width Stacked Quota Sections
            if let quota, !quota.groups.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(quota.groups.enumerated()), id: \.element.id) { index, group in
                        if index > 0 {
                            Rectangle().fill(theme.divider).frame(height: 1)
                        }
                        quotaGroupSection(group: group)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
            } else {
                HStack {
                    Text("No cached quota snapshot yet — run a turn in agy on this account")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }

            if hasUnstartedWeeklyTimer {
                Rectangle().fill(theme.divider).frame(height: 1)

                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.claudeAccent)
                    Text("Weekly reset timer hasn't started — send \"hi\" in agy to start the clock")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }

            // Optional 1-line AI Credits / Pool footer
            if (summary.googleOneAiCredits ?? 0) > 0 || summary.creditPool > 0 {
                Rectangle().fill(theme.divider).frame(height: 1)

                HStack(spacing: 8) {
                    if let aiCredits = summary.googleOneAiCredits, aiCredits > 0 {
                        let usedSuffix = summary.googleOneAiCreditsUsed > 0 ? " (\(summary.googleOneAiCreditsUsed) used)" : ""
                        Text("AI Credits: \(aiCredits) left\(usedSuffix)")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    if summary.creditPool > 0 {
                        Text(String(format: "Pool: $%.2f left", summary.creditRemaining))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.costGreen)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
            }
        }
        .themedCardStyle(theme: theme)
    }

    private func quotaGroupSection(group: AgyQuotaGroup) -> some View {
        let accent = compactGroupAccent(group.displayName)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)

                Text(readableGroupTitle(group.displayName))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            VStack(spacing: 7) {
                ForEach(group.sortedBuckets) { bucket in
                    quotaBucketRow(bucket: bucket)
                }
            }
        }
    }

    private func quotaBucketRow(bucket: AgyQuotaBucket) -> some View {
        let isIdle = bucket.isWindowTimerIdle()

        return HStack(spacing: 8) {
            Text(readableBucketLabel(bucket))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(bucket.disabled ? theme.textTertiary : theme.textSecondary)
                .frame(width: 46, alignment: .leading)
                .lineLimit(1)

            if bucket.disabled {
                Text(bucket.resetDescription ?? "Disabled")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.dangerRed.opacity(0.9))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let fraction = bucket.remainingFraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(theme.progressTrack)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(healthColor(for: fraction))
                            .frame(width: max(0, geo.size.width * CGFloat(min(1.0, max(0.0, fraction)))))
                    }
                }
                .frame(height: 6)

                Text(String(format: "%.0f%%", fraction * 100.0))
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(healthColor(for: fraction))
                    .frame(width: 36, alignment: .trailing)
                    .help(String(format: "%.2f%% remaining", fraction * 100.0))

                if isIdle {
                    HStack(spacing: 3) {
                        Image(systemName: "pause.circle")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Not started")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(theme.claudeAccent)
                    .frame(width: 78, alignment: .trailing)
                    .lineLimit(1)
                    .help("Reset clock hasn't started yet — send a quick message (e.g. \"hi\") in agy to start the countdown.")
                } else if let countdown = formatCompactCountdown(bucket: bucket) {
                    Text(countdown)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 78, alignment: .trailing)
                        .lineLimit(1)
                        .help(bucket.resetDescription ?? "Resets in \(countdown)")
                } else {
                    Text("—")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 78, alignment: .trailing)
                }
            } else {
                Text("Unlimited")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func unusedOverflowActionsPanel(summary: SubscriptionAccountSummary) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Spend Today")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text("$0.00 (0 queries)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Rectangle().fill(theme.divider).frame(height: 1)

            HStack {
                Text("Remove from tab overflow?")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                        viewModel.dismissAccount(summary.email)
                        selectedAccountTabId = "auto"
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .bold))
                        Text("Dismiss Account")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(theme.dangerRed)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.dangerRed.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.dangerRed.opacity(0.32), lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .themedCardStyle(theme: theme)
    }

    // MARK: - Case 2: GCP Tab View

    @ViewBuilder
    private func gcpTabBody(project: String, snapshot: RenderSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.blue)

                Text(project)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Spacer()

                let region = viewModel.stats.gcpLocation ?? "us"
                pillBadge("\(region) · 1.10×", foreground: Color.blue, background: Color.blue.opacity(0.14))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .help("Vertex AI '\(viewModel.stats.gcpLocation ?? "us")' regional billing applies a 1.10× multiplier to base SKU rates.")

            if viewModel.gcpCreditPool > 0 {
                Rectangle().fill(theme.divider).frame(height: 1)

                let poolTotal = viewModel.gcpCreditPool
                let remaining = viewModel.gcpCreditRemaining
                let used = viewModel.gcpCostSinceBaseline
                let remainingFraction = max(0.0, min(1.0, remaining / poolTotal))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Credit Pool Balance")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text(String(format: "$%.2f remaining", remaining))
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.costGreen)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.progressTrack)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue)
                                .frame(width: max(0, geo.size.width * CGFloat(remainingFraction)))
                        }
                    }
                    .frame(height: 5.5)

                    HStack {
                        Text(String(format: "$%.2f used", used))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                        Spacer()
                        let poolStr = poolTotal.truncatingRemainder(dividingBy: 1) == 0
                            ? String(format: "Pool $%.0f", poolTotal)
                            : String(format: "Pool $%.2f", poolTotal)
                        Text(poolStr)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }
        }
        .themedCardStyle(theme: theme)

        spendSummaryPanel(accentColor: Color.blue, snapshot: snapshot) {
            if let pinned = snapshot.pinnedBucket {
                return "\(pinned.label) · Pinned day"
            }
            if selectedTimeframe == .today {
                return viewModel.stats.gcpWeeklyCost > 0.005
                    ? String(format: "Today · 7d $%.2f", viewModel.stats.gcpWeeklyCost)
                    : "Today"
            }
            return "\(selectedTimeframe.rawValue) · \(snapshot.activeBuckets.count)d"
        }

        modelsPanel(title: "GCP MODELS", snapshot: snapshot)
    }

    // MARK: - Case 3: All Tab View

    @ViewBuilder
    private func allTabBody(snapshot: RenderSnapshot) -> some View {
        let subSpend = snapshot.timeframeSubscriptionSpend
        let gcpSpend = snapshot.timeframeGcpSpend
        let hasGcp = snapshot.primaryTabs.contains(where: { $0.id == "gcp" }) || gcpSpend > 0.005

        spendSummaryPanel(accentColor: theme.costGreen, snapshot: snapshot) {
            if let pinned = snapshot.pinnedBucket {
                return hasGcp
                    ? String(format: "%@ · $%.2f Sub · $%.2f GCP", pinned.shortLabel, subSpend, gcpSpend)
                    : "\(pinned.label) · Pinned day"
            }
            if hasGcp {
                return String(format: "$%.2f Sub · $%.2f GCP", subSpend, gcpSpend)
            }
            return String(format: "$%.2f Subscription", subSpend)
        }

        byAccountPanel(hasGcp: hasGcp, gcpSpend: gcpSpend, snapshot: snapshot)

        modelsPanel(title: "COMBINED SPEND BY MODEL", snapshot: snapshot)
    }

    private func byAccountPanel(hasGcp: Bool, gcpSpend: Double, snapshot: RenderSnapshot) -> some View {
        let summaries = snapshot.summaries
        let gcpProject = viewModel.stats.gcpProject ?? "clawdbot-485304"

        return VStack(spacing: 0) {
            HStack {
                Text("BY ACCOUNT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text("SPEND")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ForEach(summaries) { summary in
                Rectangle().fill(theme.divider).frame(height: 1)

                let spend = timeframeSpend(for: summary, snapshot: snapshot)
                let tierLabel = AgyStatsViewModel.shortTierName(for: summary.plan)?.uppercased()
                let dotColor: Color = summary.isActive
                    ? theme.costGreen
                    : (summary.hasAnyHistoricalUsage ? theme.claudeAccent : theme.textTertiary)

                AccountNavigationRow(theme: theme) {
                    selectAccountTab("sub:\(summary.id)")
                } content: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 6, height: 6)

                        Text(summary.email)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        if let tierLabel {
                            let tierColor = tierLabel == "ULTRA" ? theme.geminiAccent : (tierLabel == "PRO" ? theme.costGreen : theme.textSecondary)
                            pillBadge(tierLabel, foreground: tierColor, background: tierColor.opacity(0.14))
                        }

                        Spacer(minLength: 4)

                        Text(String(format: "$%.2f", spend))
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(summary.isActive ? theme.costGreen : theme.textPrimary)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }

            if hasGcp {
                Rectangle().fill(theme.divider).frame(height: 1)

                AccountNavigationRow(theme: theme) {
                    selectAccountTab("gcp")
                } content: {
                    HStack(spacing: 6) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.blue)

                        Text(gcpProject)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)

                        pillBadge("GCP", foreground: Color.blue, background: Color.blue.opacity(0.14))

                        Spacer(minLength: 4)

                        Text(String(format: "$%.2f", gcpSpend))
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.blue)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        }
        .themedCardStyle(theme: theme)
    }

    // MARK: - Shared Spend & Model Panels

    private func spendSummaryPanel(accentColor: Color, snapshot: RenderSnapshot, subline: () -> String) -> some View {
        VStack(spacing: 0) {
            // Compact Timeframe Switcher
            HStack(spacing: 2) {
                ForEach(CostTimeframe.allCases) { tf in
                    let isSelected = (selectedTimeframe == tf)
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                            selectedTimeframe = tf
                            selectedBucketId = nil
                            hoveredBucketId = nil
                        }
                    } label: {
                        Text(tf.compactLabel)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(isSelected ? theme.textPrimary : theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isSelected ? theme.cardFillHovered : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(isSelected ? theme.cardStroke : Color.clear, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.surfaceSecondary)
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Rectangle().fill(theme.divider).frame(height: 1)

            // Spend Total + Queries / Tokens
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "$%.2f", snapshot.totalCost))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)

                    HStack(spacing: 6) {
                        Text(subline())
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)

                        if snapshot.pinnedBucket != nil {
                            Button {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                    selectedBucketId = nil
                                }
                            } label: {
                                HStack(spacing: 2.5) {
                                    Text("All \(snapshot.activeBuckets.count)d")
                                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                }
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(accentColor.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(snapshot.totalQueries) \(snapshot.totalQueries == 1 ? "query" : "queries")")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)

                    Text("\(formatCompactTokens(snapshot.totalTokens)) tokens")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            if selectedTimeframe != .today && !snapshot.activeBuckets.isEmpty {
                Rectangle().fill(theme.divider).frame(height: 1)

                dailySpendBarGraph(snapshot: snapshot)
                    .padding(9)
            }
        }
        .themedCardStyle(theme: theme)
    }

    private func modelsPanel(title: String, snapshot: RenderSnapshot) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text("SHARE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .help("Consumer estimates use 1.0× base SKU rates; GCP direct calls include the 1.10× Vertex AI 'us' regional multiplier.")

            if snapshot.modelRows.isEmpty {
                Rectangle().fill(theme.divider).frame(height: 1)
                HStack {
                    let periodName = snapshot.pinnedBucket?.shortLabel.lowercased() ?? selectedTimeframe.rawValue.lowercased()
                    Text("No model queries recorded for \(periodName)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                ForEach(snapshot.modelRows) { row in
                    Rectangle().fill(theme.divider).frame(height: 1)
                    modelRowView(row)
                }
            }
        }
        .themedCardStyle(theme: theme)
    }

    private func modelRowView(_ row: ModelRowData) -> some View {
        let accent = modelAccentColor(row.name)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)

                Text(row.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(formatCompactTokens(row.tokens)) · \(String(format: "%.0f%%", row.percentage))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)

                Text(String(format: "$%.2f", row.cost))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.progressTrack)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: max(0, geo.size.width * CGFloat(min(1.0, max(0.0, row.percentage / 100.0)))))
                }
            }
            .frame(height: 3.5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Daily Spend Bar Graph Component

    private func dailySpendBarGraph(snapshot: RenderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            dailySpendHeaderRow(snapshot: snapshot)
            dailySpendBarCanvas(snapshot: snapshot)
            dailySpendXAxis(snapshot: snapshot)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.surfaceSecondary.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.cardStroke.opacity(0.6), lineWidth: 0.5)
        )
    }

    private func dailySpendHeaderRow(snapshot: RenderSnapshot) -> some View {
        let accentTint = (snapshot.accountFilter == .gcp) ? Color.blue : theme.costGreen
        return HStack(alignment: .center) {
            if let inspected = snapshot.inspectedBucket {
                HStack(spacing: 4.5) {
                    Text(Self.dayHeaderFormatter.string(from: inspected.date).uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)

                    Text("·")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.textTertiary)

                    Text(String(format: "$%.2f", snapshot.bucketCostsById[inspected.id] ?? 0.0))
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(accentTint)

                    Text("·")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.textTertiary)

                    Text("\(formatCompactTokens(effectiveBucketTokens(inspected, snapshot: snapshot))) · \(effectiveBucketQueries(inspected, snapshot: snapshot))q")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                Text("DAILY SPEND")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
            }

            Spacer()

            if snapshot.pinnedBucket != nil {
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        selectedBucketId = nil
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("Reset")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        Image(systemName: "xmark")
                            .font(.system(size: 6.5, weight: .bold))
                    }
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.surfaceSecondary))
                    .overlay(Capsule().stroke(theme.cardStroke, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            } else if let peak = snapshot.peakBucket {
                Text(String(format: "PEAK: $%.2f (%@)", snapshot.bucketCostsById[peak.id] ?? 0.0, Self.shortDateFormatter.string(from: peak.date)))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentTint)
            }
        }
    }

    private func dailySpendBarCanvas(snapshot: RenderSnapshot) -> some View {
        let peakId = snapshot.peakBucket?.id
        let maxCost = snapshot.maxBucketCost
        let accountFilter = snapshot.accountFilter

        return GeometryReader { geo in
            let canvasHeight = geo.size.height
            let spacing: CGFloat = selectedTimeframe == .week ? 6.0 : 2.5
            let maxBarWidth: CGFloat = selectedTimeframe == .week ? 34 : (selectedTimeframe == .month ? 12 : 8)
            let cornerRadius: CGFloat = selectedTimeframe == .week ? 3 : 2

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(snapshot.activeBuckets) { bucket in
                    let cost = snapshot.bucketCostsById[bucket.id] ?? 0.0
                    let isHovered = (hoveredBucketId == bucket.id)
                    let isPinned = (selectedBucketId == bucket.id)
                    let isInspected = isHovered || isPinned
                    let isPeak = (peakId == bucket.id)

                    let barHeight: CGFloat = {
                        if cost <= 0 { return 3.0 }
                        let ratio = CGFloat(cost / maxCost)
                        return max(6.0, canvasHeight * ratio)
                    }()

                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(barFillColor(isInspected: isInspected, isPeak: isPeak, cost: cost, accountFilter: accountFilter))
                            .frame(height: barHeight)
                            .overlay(
                                barOverlay(isInspected: isInspected, isPeak: isPeak, cost: cost, cornerRadius: cornerRadius)
                            )
                    }
                    .frame(maxWidth: maxBarWidth, maxHeight: .infinity)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { isOver in
                        if isOver {
                            hoveredBucketId = bucket.id
                        } else if hoveredBucketId == bucket.id {
                            hoveredBucketId = nil
                        }
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            if selectedBucketId == bucket.id {
                                selectedBucketId = nil
                            } else {
                                selectedBucketId = bucket.id
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 62)
    }

    private func barFillColor(isInspected: Bool, isPeak: Bool, cost: Double, accountFilter: AccountFilter) -> Color {
        let baseTint = (accountFilter == .gcp) ? Color.blue : theme.costGreen
        if isInspected {
            return baseTint
        } else if isPeak && cost > 0 {
            return baseTint
        } else if cost > 0 {
            return baseTint.opacity(0.48)
        } else {
            return theme.surfaceSecondary.opacity(0.8)
        }
    }

    @ViewBuilder
    private func barOverlay(isInspected: Bool, isPeak: Bool, cost: Double, cornerRadius: CGFloat) -> some View {
        if isInspected {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.9), lineWidth: 1.2)
        } else if isPeak && cost > 0 {
            VStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.75))
                    .frame(height: 1.5)
                Spacer()
            }
        }
    }

    private func dailySpendXAxis(snapshot: RenderSnapshot) -> some View {
        let buckets = snapshot.activeBuckets
        let inspectedId = snapshot.inspectedBucket?.id

        return Group {
            if selectedTimeframe == .week || buckets.count <= 7 {
                HStack(spacing: 6) {
                    ForEach(buckets) { bucket in
                        let isInspected = (inspectedId == bucket.id)
                        Text(Self.weekdayFormatter.string(from: bucket.date))
                            .font(.system(size: 7.5, weight: isInspected ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(isInspected ? theme.textPrimary : theme.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                let tickIndices = Self.computeTickIndices(totalCount: buckets.count)

                HStack {
                    ForEach(Array(tickIndices.enumerated()), id: \.offset) { i, idx in
                        let b = buckets[idx]
                        let isLast = (idx == buckets.count - 1)
                        let isToday = isLast && Calendar.current.isDateInToday(b.date)
                        let labelText = isToday ? "Today" : Self.shortDateFormatter.string(from: b.date)
                        let isInspected = (inspectedId == b.id)

                        Text(labelText)
                            .font(.system(size: 7.5, weight: isInspected ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(isInspected ? theme.textPrimary : theme.textTertiary)

                        if i < tickIndices.count - 1 {
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Helpers & Color Resolvers

    private func timeframeSpend(for summary: SubscriptionAccountSummary, snapshot: RenderSnapshot) -> Double {
        let metrics = Self.accountSummaryMetrics(
            emailKey: summary.id,
            timeframe: selectedTimeframe,
            allBuckets: viewModel.stats.dailyUsage,
            pinnedBucket: snapshot.pinnedBucket,
            summaryTotalCost: summary.totalCost,
            summaryTotalQueries: summary.totalQueries
        )
        if snapshot.pinnedBucket == nil && selectedTimeframe == .today && snapshot.activeBuckets.isEmpty {
            return max(metrics.cost, summary.todayCost)
        }
        return metrics.cost
    }

    private func pillBadge(_ text: String, foreground: Color, background: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(foreground)
            .padding(.horizontal, 5.5)
            .padding(.vertical, 2)
            .background(Capsule().fill(background))
            .overlay(Capsule().stroke(foreground.opacity(0.28), lineWidth: 0.6))
    }

    private func readableGroupTitle(_ displayName: String) -> String {
        let lower = displayName.lowercased()
        if lower.contains("neon") { return "Gemini 4 Neon" }
        if lower.contains("hydrogen") { return "Gemini 4 Hydrogen" }
        if lower.contains("carbon") { return "Gemini 4 Carbon" }
        if lower.contains("argon") { return "Gemini 4 Argon" }
        if lower.contains("gemini") { return "Gemini" }
        if lower.contains("claude") || lower.contains("gpt") || lower.contains("anthropic") || lower.contains("openai") || lower.contains("sonnet") || lower.contains("opus") {
            return "Claude & GPT"
        }
        return displayName
    }

    private func compactGroupAccent(_ displayName: String) -> Color {
        let lower = displayName.lowercased()
        if lower.contains("claude") || lower.contains("gpt") || lower.contains("anthropic") || lower.contains("openai") || lower.contains("sonnet") || lower.contains("opus") {
            return theme.claudeAccent
        }
        return theme.geminiAccent
    }

    private func readableBucketLabel(_ bucket: AgyQuotaBucket) -> String {
        if bucket.isFiveHourBucket {
            return "5-Hour"
        }
        if bucket.isWeeklyBucket {
            return "Weekly"
        }
        return bucket.displayName
    }

    private func healthColor(for fraction: Double) -> Color {
        if fraction > 0.50 {
            return theme.costGreen
        } else if fraction > 0.20 {
            return theme.claudeAccent
        }
        return theme.dangerRed
    }

    private func modelAccentColor(_ name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("neon") || lower.contains("argon") || lower.contains("carbon") || lower.contains("hydrogen") {
            return theme.geminiAccent
        } else if lower.contains("claude") || lower.contains("opus") || lower.contains("sonnet") {
            return theme.claudeAccent
        } else if lower.contains("flash") || lower.contains("gemini") {
            return theme.linkBlue
        }
        return theme.costGreen
    }

    private func formatCompactCountdown(bucket: AgyQuotaBucket) -> String? {
        if bucket.isWindowTimerIdle() {
            return nil
        }
        if let resetTimeStr = bucket.resetTime,
           let date = AgyQuotaInfo.parseResetTime(resetTimeStr) {
            let diff = date.timeIntervalSince(Date())
            if diff > 0 {
                let days = Int(diff) / 86400
                let hours = (Int(diff) % 86400) / 3600
                let minutes = (Int(diff) % 3600) / 60
                if days > 0 {
                    return "\(days)d \(hours)h"
                } else if hours > 0 {
                    return "\(hours)h \(minutes)m"
                } else {
                    return "\(minutes)m"
                }
            }
            return "Resetting…"
        }

        if let desc = bucket.resetDescription, !desc.isEmpty {
            return desc
                .replacingOccurrences(of: "Refreshes in ", with: "")
                .replacingOccurrences(of: "Resets in ", with: "")
        }
        return nil
    }

    private func formatCompactTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

private struct AccountNavigationRow<Content: View>: View {
    let theme: ThemeColors
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHovered ? theme.cardFillHovered : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
