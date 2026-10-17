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
        
        public var id: String { rawValue }
    }
    
    @State private var selectedTimeframe: CostTimeframe = .week
    
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
        }
    }
    
    private var totalCost: Double {
        activeBuckets.aggregatedTotalCost
    }
    
    private var totalTokens: Int {
        activeBuckets.aggregatedInputTokens + activeBuckets.aggregatedOutputTokens
    }
    
    private var totalQueries: Int {
        activeBuckets.aggregatedQueryCount
    }
    
    private struct ModelRowData: Identifiable {
        let id: String
        let name: String
        let cost: Double
        let percentage: Double
        let tokens: Int
    }
    
    private var modelRows: [ModelRowData] {
        let breakdown = activeBuckets.aggregatedModelBreakdown
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
            VStack(spacing: 14) {
                // Title & Account Header
                titleRow
                
                // Terminal-Identical Quota Groups
                quotaGroupsSection
                
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
        HStack(alignment: .firstTextBaseline) {
            Text("MODELS & QUOTA")
                .font(.system(size: 11.5, weight: .black, design: .monospaced))
                .foregroundStyle(theme.textPrimary)
            
            Spacer()
            
            if let email = viewModel.stats.quotaInfo?.email, !email.isEmpty {
                Text("Account: \(email)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.linkBlue)
            } else if viewModel.stats.isGcpActive, let project = viewModel.stats.gcpProject {
                Text("GCP: \(project)")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.linkBlue)
            }
        }
        .padding(.bottom, 2)
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
            // Group Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(group.displayName.uppercased())
                    .font(.system(size: 10.5, weight: .black, design: .monospaced))
                    .foregroundStyle(groupAccent)
                
                if let desc = group.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(2)
                }
            }
            
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
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    Text(String(format: "$%.2f", totalCost))
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundStyle(theme.costGreen)
                    Text("TOTAL")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }
                
                Spacer()
                
                Text("\(formatCompactTokens(totalTokens)) tokens · \(totalQueries) queries")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
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
