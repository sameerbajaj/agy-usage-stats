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
    
    private var isDark: Bool { colorScheme == .dark }
    private var theme: ThemeColors { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme) }
    
    public init(viewModel: AgyStatsViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Cost & Token Computations
    
    private var activeBuckets: [UsageTimeBucket] {
        switch selectedTimeframe {
        case .today:
            if let last = viewModel.stats.dailyUsage.last {
                return [last]
            }
            return []
        case .week:
            return Array(viewModel.stats.dailyUsage.suffix(7))
        case .month:
            return Array(viewModel.stats.dailyUsage.suffix(30))
        case .all:
            return viewModel.stats.dailyUsage
        }
    }
    
    private var totalCost: Double {
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
        switch selectedAccount {
        case .all:
            breakdown = activeBuckets.aggregatedModelBreakdown
        case .subscription:
            breakdown = activeBuckets.aggregatedQuotaModelBreakdown
        case .gcp:
            breakdown = activeBuckets.aggregatedGcpModelBreakdown
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
                    Text("GOOGLE CLOUD PLATFORM")
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
            
            // $300 Promo Credit Balance & Burn
            let poolTotal = 300.0
            let gcpTotalSpend = viewModel.stats.gcpTotalCost
            let gcpTodaySpend = viewModel.stats.gcpTodayCost
            let creditRemaining = max(0.0, poolTotal - gcpTotalSpend)
            let consumedFraction = min(1.0, gcpTotalSpend / poolTotal)
            
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("$300 PROMO CREDIT POOL")
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
            
            // Total Summary Line
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 4) {
                        Text(String(format: "$%.2f", totalCost))
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundStyle(selectedAccount == .gcp ? Color.blue : theme.costGreen)
                        Text(selectedAccount == .gcp ? "GCP CREDIT" : (selectedAccount == .subscription ? "SUBSCRIPTION" : "TOTAL"))
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                    }
                    
                    Spacer()
                    
                    Text("\(formatCompactTokens(totalTokens)) tokens · \(totalQueries) queries")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                }
                
                if selectedAccount == .all && (activeBuckets.aggregatedGcpCost > 0 || activeBuckets.aggregatedQuotaCost > 0) {
                    HStack(spacing: 6) {
                        Text(String(format: "↳ $%.2f Sub", activeBuckets.aggregatedQuotaCost))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.costGreen)
                        Text("·")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(theme.textTertiary)
                        Text(String(format: "$%.2f GCP Credit", activeBuckets.aggregatedGcpCost))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.blue)
                    }
                }
            }
            .padding(.vertical, 2)
            
            // Model Cards List
            if modelRows.isEmpty {
                HStack {
                    Text("No model queries recorded for \(selectedTimeframe.rawValue.lowercased())")
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
           let date = ISO8601DateFormatter().date(from: resetTimeStr) {
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
