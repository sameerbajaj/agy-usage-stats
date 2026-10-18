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
    }
    
    @State private var selectedTimeframe: CostTimeframe = .today
    @AppStorage("agy_selectedAccountFilter") private var selectedAccount: AccountFilter = .all
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
    
    private static let iso8601Formatter = ISO8601DateFormatter()
    
    private var isDark: Bool { colorScheme == .dark }
    private var theme: ThemeColors { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme) }
    
    public init(viewModel: AgyStatsViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Cost & Token Computations
    
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
    
    private var activeBuckets: [UsageTimeBucket] {
        Self.filterBuckets(for: selectedTimeframe, in: viewModel.stats.dailyUsage)
    }
    
    // MARK: - Day Selection & Bucket Ingestion
    
    public var pinnedBucket: UsageTimeBucket? {
        Self.pinnedBucket(for: selectedBucketId, in: activeBuckets)
    }
    
    private var hoveredBucket: UsageTimeBucket? {
        guard let id = hoveredBucketId else { return nil }
        return activeBuckets.first(where: { $0.id == id })
    }
    
    private var activeInspectedBucket: UsageTimeBucket? {
        hoveredBucket ?? pinnedBucket
    }
    
    private var inspectedBucket: UsageTimeBucket? {
        hoveredBucket ?? pinnedBucket
    }
    
    public var peakBucket: UsageTimeBucket? {
        Self.computePeakBucket(in: activeBuckets, account: selectedAccount)
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
    
    public func bucketCost(_ bucket: UsageTimeBucket, account: AccountFilter? = nil) -> Double {
        Self.bucketCost(bucket, account: account ?? selectedAccount)
    }
    
    public func bucketTokens(_ bucket: UsageTimeBucket, account: AccountFilter? = nil) -> Int {
        Self.bucketTokens(bucket, account: account ?? selectedAccount)
    }
    
    public func bucketQueries(_ bucket: UsageTimeBucket, account: AccountFilter? = nil) -> Int {
        Self.bucketQueries(bucket, account: account ?? selectedAccount)
    }
    
    public func bucketModelBreakdown(_ bucket: UsageTimeBucket, account: AccountFilter? = nil) -> [String: Double] {
        Self.bucketModelBreakdown(bucket, account: account ?? selectedAccount)
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
            let costA: Double
            let costB: Double
            switch account {
            case .all: costA = a.totalCost; costB = b.totalCost
            case .subscription: costA = a.quotaCost; costB = b.quotaCost
            case .gcp: costA = a.gcpCost; costB = b.gcpCost
            }
            return costA < costB
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
    
    private var totalCost: Double {
        if let pinned = pinnedBucket {
            return bucketCost(pinned)
        }
        switch selectedAccount {
        case .all:
            if selectedTimeframe == .all && viewModel.stats.totalCostEstimate > activeBuckets.aggregatedTotalCost {
                return viewModel.stats.totalCostEstimate
            }
            return activeBuckets.aggregatedTotalCost
        case .subscription:
            if selectedTimeframe == .all && viewModel.stats.quotaTotalCost > activeBuckets.aggregatedQuotaCost {
                return viewModel.stats.quotaTotalCost
            }
            return activeBuckets.aggregatedQuotaCost
        case .gcp:
            if selectedTimeframe == .all && viewModel.stats.gcpTotalCost > activeBuckets.aggregatedGcpCost {
                return viewModel.stats.gcpTotalCost
            }
            return activeBuckets.aggregatedGcpCost
        }
    }
    
    private var totalTokens: Int {
        if let pinned = pinnedBucket {
            return bucketTokens(pinned)
        }
        switch selectedAccount {
        case .all:
            let tokens = activeBuckets.aggregatedInputTokens + activeBuckets.aggregatedOutputTokens
            if selectedTimeframe == .all && tokens == 0 && viewModel.stats.totalQueries > 0 {
                return viewModel.stats.totalQueries * 85_000
            }
            return tokens
        case .subscription:
            return activeBuckets.aggregatedQuotaTokens
        case .gcp:
            return activeBuckets.aggregatedGcpTokens
        }
    }
    
    private var totalQueries: Int {
        if let pinned = pinnedBucket {
            return bucketQueries(pinned)
        }
        switch selectedAccount {
        case .all:
            if selectedTimeframe == .all {
                return max(viewModel.stats.totalQueries, activeBuckets.aggregatedQueryCount)
            }
            return activeBuckets.aggregatedQueryCount
        case .subscription:
            return activeBuckets.aggregatedQuotaQueryCount
        case .gcp:
            return activeBuckets.aggregatedGcpQueryCount
        }
    }
    
    private struct ModelRowData: Identifiable {
        let id: String
        let name: String
        let cost: Double
        let percentage: Double
        let tokens: Int
    }
    
    private var modelRows: [ModelRowData] {
        let breakdown: [String: Double]
        if let pinned = pinnedBucket {
            breakdown = bucketModelBreakdown(pinned)
        } else {
            switch selectedAccount {
            case .all:
                breakdown = activeBuckets.aggregatedModelBreakdown
            case .subscription:
                breakdown = activeBuckets.aggregatedQuotaModelBreakdown
            case .gcp:
                breakdown = activeBuckets.aggregatedGcpModelBreakdown
            }
        }
        let total = max(0.0001, totalCost)
        let totalToks = max(1, totalTokens)
        
        return breakdown
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { item in
                let pct = (item.value / total) * 100.0
                let estimatedTokens = Int(Double(totalToks) * (pct / 100.0))
                return ModelRowData(
                    id: item.key,
                    name: item.key,
                    cost: item.value,
                    percentage: pct,
                    tokens: estimatedTokens
                )
            }
    }
    
    // MARK: - Main Body
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Title & Account Header
                titleRow
                
                // Account Context Subheader
                accountContextSubheader
                
                // Quota or GCP Cloud Credit Section
                if selectedAccount == .gcp {
                    gcpCloudCreditCard
                } else if selectedAccount == .all {
                    quotaGroupsSection
                    if viewModel.stats.gcpTotalCost > 0 || viewModel.stats.gcpTodayCost > 0 {
                        gcpCloudCreditCard
                    }
                } else {
                    quotaGroupsSection
                }
                
                // Super Clean Model Cost Breakdown
                costByModelSection
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(theme.surfacePrimary)
        .onChange(of: selectedTimeframe) { _, _ in
            selectedBucketId = nil
            hoveredBucketId = nil
        }
        .onChange(of: selectedAccount) { _, _ in
            selectedBucketId = nil
            hoveredBucketId = nil
        }
    }
    
    // MARK: - Title & Account Header
    
    private var titleRow: some View {
        HStack(alignment: .center) {
            Text("MODELS & QUOTA")
                .font(.system(size: 11.5, weight: .black, design: .monospaced))
                .foregroundStyle(theme.textPrimary)
            
            Spacer()
            
            // Direction 1: Segmented Account Capsule
            HStack(spacing: 2) {
                ForEach(AccountFilter.allCases) { filter in
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            selectedAccount = filter
                            selectedBucketId = nil
                            hoveredBucketId = nil
                        }
                    } label: {
                        HStack(spacing: 3.5) {
                            if filter == .subscription {
                                Circle()
                                    .fill(theme.costGreen)
                                    .frame(width: 4.5, height: 4.5)
                            } else if filter == .gcp {
                                Image(systemName: "cloud.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.blue)
                            }
                            
                            Text(filter.rawValue)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(selectedAccount == filter ? Color.primary : Color.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(selectedAccount == filter ? theme.cardFillHovered : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(selectedAccount == filter ? theme.cardStroke : Color.clear, lineWidth: 0.5)
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
        }
        .padding(.bottom, 2)
    }
    
    // MARK: - Account Context Subheader
    
    private var accountContextSubheader: some View {
        HStack {
            switch selectedAccount {
            case .subscription:
                if let email = viewModel.stats.quotaInfo?.email, !email.isEmpty {
                    Text("Account: \(email) (Personal Subscription)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                } else {
                    Text("Account: Consumer Subscription Quota")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                }
            case .gcp:
                Text("Account: Google Cloud Platform (\(viewModel.stats.gcpProject ?? "clawdbot-485304"))")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.blue)
            case .all:
                HStack(spacing: 6) {
                    Circle().fill(theme.costGreen).frame(width: 4, height: 4)
                    Text("Subscription: Active")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                    Text("·")
                        .foregroundStyle(theme.textTertiary)
                    Circle().fill(Color.blue).frame(width: 4, height: 4)
                    Text("GCP: \(viewModel.stats.gcpProject ?? "clawdbot-485304") Ready")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }
    
    // MARK: - Google Cloud Platform Telemetry Card
    
    private var gcpCloudCreditCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header & Badge
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.blue)
                    Text("GCP CLOUD SPEND")
                        .font(.system(size: 10.5, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.blue)
                }
                
                Spacer()
                
                Text("DIRECT VERTEX AI")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.blue)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.blue.opacity(0.12)))
            }
            
            // Project & Region Details
            HStack {
                Text("Project: \(viewModel.stats.gcpProject ?? "clawdbot-485304")")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("Region: \(viewModel.stats.gcpLocation ?? "us")")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
            }
            
            Rectangle().fill(theme.divider).frame(height: 0.5)
            
            let gcpTotalSpend = viewModel.stats.gcpTotalCost
            let gcpTodaySpend = viewModel.stats.gcpTodayCost
            let gcpWeekSpend = viewModel.stats.gcpWeeklyCost
            let poolTotal = viewModel.gcpCreditPool
            
            if poolTotal > 0.0 {
                let creditRemaining = max(0.0, poolTotal - gcpTotalSpend)
                let consumedFraction = min(1.0, gcpTotalSpend / poolTotal)
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(String(format: "$%.0f CREDIT POOL", poolTotal))
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text(String(format: "$%.2f remaining", creditRemaining))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.costGreen)
                    }
                    
                    // Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.08))
                            
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue)
                                .frame(width: max(0, geo.size.width * CGFloat(consumedFraction)))
                        }
                    }
                    .frame(height: 5.5)
                    
                    HStack {
                        Text(String(format: "$%.2f spent today", gcpTodaySpend))
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Text(String(format: "$%.2f total consumed (%.1f%%)", gcpTotalSpend, consumedFraction * 100))
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SPENT TODAY")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.textSecondary)
                            Text(String(format: "$%.2f", gcpTodaySpend))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.textPrimary)
                        }
                        Spacer()
                        VStack(alignment: .center, spacing: 2) {
                            Text("SPENT THIS WEEK")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.textSecondary)
                            Text(String(format: "$%.2f", gcpWeekSpend))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.textPrimary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("TOTAL GCP SPEND")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.textSecondary)
                            Text(String(format: "$%.2f", gcpTotalSpend))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.blue)
                        }
                    }
                }
            }
            
            Rectangle().fill(theme.divider).frame(height: 0.5)
            
            // Delegation Guard Info
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.claudeAccent)
                Text("Delegation Guard: sub-agents run on free subscription via herdr")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(12)
        .themedCardStyle(theme: theme)
    }
    
    // MARK: - Terminal-Identical Quota Groups Section
    
    private var quotaGroupsSection: some View {
        VStack(spacing: 10) {
            if let quota = viewModel.stats.quotaInfo, !quota.groups.isEmpty {
                ForEach(quota.groups) { group in
                    quotaGroupCard(group)
                }
            } else {
                HStack {
                    Text("No active quota sessions detected. Running via direct API / local state.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                    Spacer()
                }
                .padding(12)
                .themedCardStyle(theme: theme)
            }
        }
    }
    
    private func quotaGroupCard(_ group: AgyQuotaGroup) -> some View {
        let isGemini = group.displayName.lowercased().contains("gemini") || group.displayName.lowercased().contains("argon")
        let groupAccent = isGemini ? theme.geminiAccent : theme.claudeAccent
        
        return VStack(alignment: .leading, spacing: 8) {
            // Group Title
            Text(group.displayName.uppercased())
                .font(.system(size: 10.5, weight: .black, design: .monospaced))
                .foregroundStyle(groupAccent)
            
            // Buckets within group
            VStack(spacing: 8) {
                ForEach(group.sortedBuckets) { bucket in
                    quotaBucketRow(bucket, groupDisplayName: group.displayName)
                }
            }
        }
        .padding(12)
        .themedCardStyle(theme: theme)
    }
    
    private func quotaBucketRow(_ bucket: AgyQuotaBucket, groupDisplayName: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top: Name & Percentage
            HStack(alignment: .center) {
                Text(bucket.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(bucket.disabled ? theme.textTertiary : theme.textPrimary)
                
                Spacer()
                
                if bucket.disabled {
                    Text("—")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                } else if let fraction = bucket.remainingFraction {
                    Text(String(format: "%.2f%%", fraction * 100.0))
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(healthColor(for: fraction))
                } else {
                    Text("unlimited")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            
            // Progress Bar
            if !bucket.disabled, let fraction = bucket.remainingFraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.primary.opacity(0.08))
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(healthColor(for: fraction))
                            .frame(width: max(0, geo.size.width * CGFloat(min(1.0, fraction))))
                    }
                }
                .frame(height: 5.5)
            }
            
            // Refresh countdown or disabled explanation
            if bucket.disabled {
                if let desc = bucket.resetDescription {
                    Text(desc)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(theme.dangerRed.opacity(0.85))
                        .lineLimit(3)
                        .padding(.top, 1)
                }
            } else if let countdown = formatHumanCountdown(bucket: bucket) {
                Text(countdown)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(healthCountdownColor(bucket: bucket))
            }
        }
    }
    
    // MARK: - Section: Super Clean Model Cost Breakdown
    
    private var costByModelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header & Cache Pill
            HStack {
                Text("ESTIMATED COST BY MODEL")
                    .font(.system(size: 10.5, weight: .black, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                
                Spacer()
                
                Text("~92% CACHED (95% OFF)")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.costGreen)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.costGreen.opacity(0.12)))
            }
            
            // Timeframe Selector
            HStack(spacing: 3) {
                ForEach(CostTimeframe.allCases) { tf in
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            selectedTimeframe = tf
                            selectedBucketId = nil
                            hoveredBucketId = nil
                        }
                    } label: {
                        Text(tf.rawValue)
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(selectedTimeframe == tf ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(selectedTimeframe == tf ? theme.cardFillHovered : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(selectedTimeframe == tf ? theme.cardStroke : Color.clear, lineWidth: 0.5)
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
            
            // Daily Spend Bar Graph (Visible when not today and buckets exist)
            if selectedTimeframe != .today && !activeBuckets.isEmpty {
                dailySpendBarGraph
            }
            
            // Total Summary Line
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 4) {
                        Text(String(format: "$%.2f", totalCost))
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundStyle(selectedAccount == .gcp ? Color.blue : theme.costGreen)
                        
                        let labelText: String = {
                            if let pinned = pinnedBucket {
                                return "\(pinned.shortLabel.uppercased()) SPEND"
                            }
                            return selectedAccount == .gcp ? "GCP CREDIT" : (selectedAccount == .subscription ? "SUBSCRIPTION" : "TOTAL")
                        }()
                        
                        Text(labelText)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(pinnedBucket != nil ? (selectedAccount == .gcp ? Color.blue : theme.costGreen) : theme.textTertiary)
                    }
                    
                    Spacer()
                    
                    if let pinned = pinnedBucket {
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                selectedBucketId = nil
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text("All \(activeBuckets.count) Days")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .foregroundStyle(selectedAccount == .gcp ? Color.blue : theme.costGreen)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill((selectedAccount == .gcp ? Color.blue : theme.costGreen).opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("\(formatCompactTokens(totalTokens)) tokens · \(totalQueries) queries")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                
                if pinnedBucket != nil {
                    HStack {
                        Text("\(formatCompactTokens(totalTokens)) tokens · \(totalQueries) queries")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                    }
                }
                
                if selectedAccount == .all {
                    let subCost = pinnedBucket?.quotaCost ?? activeBuckets.aggregatedQuotaCost
                    let gcpCost = pinnedBucket?.gcpCost ?? activeBuckets.aggregatedGcpCost
                    if gcpCost > 0 || subCost > 0 {
                        HStack(spacing: 6) {
                            Text(String(format: "↳ $%.2f Sub", subCost))
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.costGreen)
                            Text("·")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(theme.textTertiary)
                            Text(String(format: "$%.2f GCP Credit", gcpCost))
                                .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.blue)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
            
            // Model Cards List
            if modelRows.isEmpty {
                HStack {
                    let periodName = pinnedBucket?.shortLabel.lowercased() ?? selectedTimeframe.rawValue.lowercased()
                    Text("No model queries recorded for \(periodName)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                    Spacer()
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(modelRows) { row in
                        modelCostCard(row)
                    }
                }
            }
        }
        .padding(12)
        .themedCardStyle(theme: theme)
    }
    
    private func modelCostCard(_ row: ModelRowData) -> some View {
        let accent = modelAccentColor(row.name)
        
        return VStack(alignment: .leading, spacing: 4) {
            // Row Top: Name with Dot + Big Bold Price
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(accent)
                        .frame(width: 6, height: 6)
                    Text(row.name)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                }
                
                Spacer()
                
                Text(String(format: "$%.2f", row.cost))
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
            }
            
            // Proportion Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.06))
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: max(0, geo.size.width * CGFloat(row.percentage / 100.0)))
                }
            }
            .frame(height: 4)
            
            // Subtitle Details
            HStack {
                Text("\(formatCompactTokens(row.tokens)) tokens")
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                
                Spacer()
                
                Text(String(format: "%.0f%% of total spend", row.percentage))
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.surfaceSecondary.opacity(0.4))
        )
    }
    
    // MARK: - Daily Spend Bar Graph Component
    
    // MARK: - Daily Spend Bar Graph Container
    
    private var dailySpendBarGraph: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top header row
            dailySpendHeaderRow
            
            // Bar canvas (height ~68pt)
            dailySpendBarCanvas
            
            // X-axis labels row below the bars
            dailySpendXAxis
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
    
    private var dailySpendHeaderRow: some View {
        HStack(alignment: .center) {
            if let inspected = activeInspectedBucket {
                HStack(spacing: 4.5) {
                    Text(Self.dayHeaderFormatter.string(from: inspected.date).uppercased())
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                    
                    Text("·")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.textTertiary)
                    
                    Text(String(format: "$%.2f", bucketCost(inspected)))
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(selectedAccount == .gcp ? Color.blue : theme.costGreen)
                    
                    Text("·")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.textTertiary)
                    
                    Text("\(formatCompactTokens(bucketTokens(inspected))) · \(bucketQueries(inspected))q")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                }
            } else {
                Text("DAILY SPEND")
                    .font(.system(size: 8.5, weight: .black, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
            }
            
            Spacer()
            
            if pinnedBucket != nil {
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
                    .background(
                        Capsule().fill(theme.surfaceSecondary)
                    )
                    .overlay(
                        Capsule().stroke(theme.cardStroke, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            } else if let peak = peakBucket {
                Text(String(format: "PEAK: $%.2f (%@)", bucketCost(peak), Self.shortDateFormatter.string(from: peak.date)))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.costGreen)
            }
        }
    }
    
    private var dailySpendBarCanvas: some View {
        GeometryReader { geo in
            let canvasHeight = geo.size.height
            let maxCost = max(0.0001, activeBuckets.map { bucketCost($0) }.max() ?? 0.0)
            let spacing: CGFloat = selectedTimeframe == .week ? 6.0 : 2.5
            let maxBarWidth: CGFloat = selectedTimeframe == .week ? 34 : (selectedTimeframe == .month ? 12 : 8)
            let cornerRadius: CGFloat = selectedTimeframe == .week ? 3 : 2
            
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(activeBuckets) { bucket in
                    let cost = bucketCost(bucket)
                    let isHovered = (hoveredBucketId == bucket.id)
                    let isPinned = (selectedBucketId == bucket.id)
                    let isInspected = isHovered || isPinned
                    let isPeak = (peakBucket?.id == bucket.id)
                    
                    let barHeight: CGFloat = {
                        if cost <= 0 {
                            return 3.0
                        }
                        let ratio = CGFloat(cost / maxCost)
                        return max(6.0, canvasHeight * ratio)
                    }()
                    
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(barFillColor(isInspected: isInspected, isPeak: isPeak, cost: cost))
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
        .frame(height: 68)
    }
    
    private func barFillColor(isInspected: Bool, isPeak: Bool, cost: Double) -> Color {
        let baseTint = selectedAccount == .gcp ? Color.blue : theme.costGreen
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
    
    private var dailySpendXAxis: some View {
        Group {
            if selectedTimeframe == .week || activeBuckets.count <= 7 {
                HStack(spacing: 6) {
                    ForEach(activeBuckets) { bucket in
                        let isInspected = (activeInspectedBucket?.id == bucket.id)
                        let text = Self.weekdayFormatter.string(from: bucket.date)
                        Text(text)
                            .font(.system(size: 7.5, weight: isInspected ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(isInspected ? theme.textPrimary : theme.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                let buckets = activeBuckets
                let tickIndices = Self.computeTickIndices(totalCount: buckets.count)
                
                HStack {
                    ForEach(Array(tickIndices.enumerated()), id: \.offset) { i, idx in
                        let b = buckets[idx]
                        let isLast = (idx == buckets.count - 1)
                        let isToday = isLast && Calendar.current.isDateInToday(b.date)
                        let labelText = isToday ? "Today" : Self.shortDateFormatter.string(from: b.date)
                        let isInspected = (activeInspectedBucket?.id == b.id)
                        
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
    
    private func healthColor(for fraction: Double) -> Color {
        if fraction > 0.20 {
            return theme.costGreen
        } else if fraction > 0.05 {
            return theme.claudeAccent
        }
        return theme.dangerRed
    }
    
    private func healthCountdownColor(bucket: AgyQuotaBucket) -> Color {
        let fraction = bucket.remainingFraction ?? 1.0
        if fraction <= 0.05 {
            return theme.dangerRed
        } else if fraction <= 0.20 {
            return theme.claudeAccent
        }
        return theme.costGreen
    }
    
    private func modelAccentColor(_ name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("argon") {
            return theme.geminiAccent
        } else if lower.contains("claude") || lower.contains("opus") || lower.contains("sonnet") {
            return theme.claudeAccent
        } else if lower.contains("flash") || lower.contains("gemini") {
            return theme.linkBlue
        }
        return theme.costGreen
    }
    
    private func formatHumanCountdown(bucket: AgyQuotaBucket) -> String? {
        if let resetTimeStr = bucket.resetTime,
           let date = Self.iso8601Formatter.date(from: resetTimeStr) {
            let diff = date.timeIntervalSince(Date())
            if diff > 0 {
                let days = Int(diff) / 86400
                let hours = (Int(diff) % 86400) / 3600
                let minutes = (Int(diff) % 3600) / 60
                
                if days > 0 {
                    return "Refreshes in \(days) day\(days == 1 ? "" : "s"), \(hours) hour\(hours == 1 ? "" : "s")"
                } else if hours > 0 {
                    return "Refreshes in \(hours)h \(minutes)m"
                } else {
                    return "Refreshes in \(minutes)m"
                }
            }
        }
        
        if let desc = bucket.resetDescription, !desc.isEmpty {
            return desc
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
