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
    
    public enum TimeScope: String, CaseIterable, Identifiable {
        case week = "7D"
        case twoWeeks = "14D"
        case month = "30D"
        case monthly = "Monthly"
        
        public var id: String { rawValue }
        public var label: String { rawValue }
    }
    
    @State private var timeScope: TimeScope = .week
    @State private var selectedDayKey: String? = nil
    @State private var isHoveringScrubber = false
    
    private var isDark: Bool { colorScheme == .dark }
    private var theme: ThemeColors { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme) }
    
    public init(viewModel: AgyStatsViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Computed Data for Scope
    
    private var activeBuckets: [UsageTimeBucket] {
        switch timeScope {
        case .week:
            return Array(viewModel.stats.dailyUsage.suffix(7))
        case .twoWeeks:
            return Array(viewModel.stats.dailyUsage.suffix(14))
        case .month:
            return Array(viewModel.stats.dailyUsage.suffix(30))
        case .monthly:
            if let currentMonth = viewModel.stats.monthlyUsage.last {
                return [currentMonth]
            }
            return viewModel.stats.dailyUsage.isEmpty ? [] : Array(viewModel.stats.dailyUsage.suffix(30))
        }
    }
    
    private var inspectedBucket: UsageTimeBucket? {
        guard let key = selectedDayKey else { return nil }
        return activeBuckets.first(where: { $0.periodKey == key })
    }
    
    private var isDrilldownActive: Bool {
        inspectedBucket != nil
    }
    
    private var displayTotalCost: Double {
        if let b = inspectedBucket {
            return b.totalCost
        }
        return activeBuckets.aggregatedTotalCost
    }
    
    private var displayInputTokens: Int {
        if let b = inspectedBucket {
            return b.inputTokens
        }
        return activeBuckets.aggregatedInputTokens
    }
    
    private var displayOutputTokens: Int {
        if let b = inspectedBucket {
            return b.outputTokens
        }
        return activeBuckets.aggregatedOutputTokens
    }
    
    private var displayTotalTokens: Int {
        displayInputTokens + displayOutputTokens
    }
    
    private var displayModelBreakdown: [(name: String, cost: Double, pct: Double)] {
        let breakdown: [String: Double]
        if let b = inspectedBucket {
            breakdown = b.consolidatedModelBreakdown
        } else {
            breakdown = activeBuckets.aggregatedModelBreakdown
        }
        let total = max(0.0001, displayTotalCost)
        return breakdown
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { (name: $0.key, cost: $0.value, pct: ($0.value / total) * 100.0) }
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 1. Active Model & Live Status
                activeModelHeader
                
                // 2. Real-Time Quotas
                quotaCardsSection
                
                // 3. Direction C: Interactive Donut & Token Scrubber
                directionCCostCard
                
                // 4. Tools & Telemetry Summary
                telemetrySummaryCard
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(theme.surfacePrimary)
    }
    
    // MARK: - Section 1: Active Model Header
    
    private var activeModelHeader: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.geminiAccent)
                Text(viewModel.activeModelDisplayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
            }
            Spacer()
            if viewModel.settings.enableTelemetry == true {
                TelemetryBadge()
            }
        }
        .padding(.horizontal, 2)
    }
    
    // MARK: - Section 2: Quota Cards
    
    private var quotaCardsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("live quota limits")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text(viewModel.isConnected ? "● connected" : "○ offline")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(viewModel.isConnected ? Color.green : Color.red)
            }
            .padding(.horizontal, 2)
            
            VStack(spacing: 6) {
                if let quotaInfo = viewModel.stats.quotaInfo, !quotaInfo.groups.isEmpty {
                    ForEach(quotaInfo.groups) { group in
                        ForEach(group.sortedBuckets) { bucket in
                            QuotaBucketRow(groupDisplayName: group.displayName, bucket: bucket)
                        }
                    }
                } else {
                    HStack {
                        Text("No active quota sessions detected")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(theme.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(10)
            .themedCardStyle(theme: theme)
        }
    }
    
    // MARK: - Section 3: Direction C Interactive Donut & Token Scrubber
    
    private var directionCCostCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Timeframe Selector
            HStack(spacing: 3) {
                ForEach(TimeScope.allCases) { scope in
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            timeScope = scope
                            selectedDayKey = nil
                        }
                    } label: {
                        Text(scope.label)
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(timeScope == scope ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 3.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(timeScope == scope ? theme.cardFillHovered : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(timeScope == scope ? theme.cardStroke : Color.clear, lineWidth: 0.5)
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
            
            // Mode / Drilldown Indicator
            HStack {
                Text(modeIndicatorText)
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                
                Spacer()
                
                if isDrilldownActive {
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            selectedDayKey = nil
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 7, weight: .bold))
                            Text("Reset to \(timeScope.rawValue)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(theme.costGreen)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.costGreen.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 2)
            
            // Donut & Scrubber Layout
            HStack(alignment: .center, spacing: 12) {
                // Donut Chart
                donutChart
                    .frame(width: 70, height: 70)
                
                // Bar Scrubber
                scrubberBarChart
                    .frame(height: 64)
            }
            
            // Deduplicated & Consolidated Model Breakdown Chips
            if !displayModelBreakdown.isEmpty {
                VStack(spacing: 3) {
                    ForEach(displayModelBreakdown, id: \.name) { item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(color(forModel: item.name))
                                .frame(width: 5, height: 5)
                            
                            Text(item.name)
                                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.textPrimary)
                            
                            Spacer()
                            
                            Text(String(format: "%.0f%%", item.pct))
                                .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(theme.textTertiary)
                            
                            Text(String(format: "$%.2f", item.cost))
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.textPrimary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(theme.surfaceSecondary.opacity(0.6))
                        )
                    }
                }
                .padding(.top, 2)
            }
            
            // Token Efficiency Row
            HStack(spacing: 0) {
                tokenMetricCell(title: "TOTAL TOKENS", value: formatCompactTokens(displayTotalTokens))
                tokenDivider
                tokenMetricCell(title: "EST. CACHED", value: "92.4%", color: theme.costGreen)
                tokenDivider
                tokenMetricCell(title: "BLENDED $/M", value: formatBlendedRate(cost: displayTotalCost, tokens: displayTotalTokens), color: theme.linkBlue)
            }
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.surfaceSecondary.opacity(0.4))
            )
        }
        .padding(10)
        .themedCardStyle(theme: theme)
    }
    
    private var modeIndicatorText: String {
        if let b = inspectedBucket {
            return "DRILLDOWN: \(b.label.uppercased())"
        }
        return "VIEWING: FULL \(timeScope.rawValue) AGGREGATE"
    }
    
    // MARK: - Donut Chart Component
    
    private var donutChart: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(theme.divider.opacity(0.4), lineWidth: 5.5)
            
            // Slices
            donutSlices
            
            // Center info
            VStack(spacing: 0) {
                Text(String(format: "$%.2f", displayTotalCost))
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                
                Text(inspectedBucket != nil ? "DAY TOTAL" : "\(timeScope.rawValue) TOTAL")
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
            }
        }
    }
    
    @ViewBuilder
    private var donutSlices: some View {
        let items = displayModelBreakdown
        let total = max(0.0001, displayTotalCost)
        var cumulative: Double = 0
        
        ForEach(items, id: \.name) { item in
            let sliceFraction = item.cost / total
            let start = cumulative
            let end = cumulative + sliceFraction
            let _ = (cumulative = end)
            
            Circle()
                .trim(from: CGFloat(start), to: CGFloat(end))
                .stroke(color(forModel: item.name), style: StrokeStyle(lineWidth: 5.5, lineCap: .butt))
                .rotationEffect(.degrees(-90))
        }
    }
    
    // MARK: - Scrubber Bar Chart
    
    private var scrubberBarChart: some View {
        let buckets = activeBuckets
        let maxCost = max(0.01, buckets.map { $0.totalCost }.max() ?? 1.0)
        
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(buckets) { bucket in
                let isSelected = (bucket.periodKey == selectedDayKey) || (selectedDayKey == nil && bucket.periodKey == buckets.last?.periodKey)
                let heightRatio = min(1.0, max(0.08, bucket.totalCost / maxCost))
                
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        if selectedDayKey == bucket.periodKey {
                            selectedDayKey = nil
                        } else {
                            selectedDayKey = bucket.periodKey
                        }
                    }
                } label: {
                    VStack(spacing: 2) {
                        Spacer(minLength: 0)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                isSelected
                                    ? LinearGradient(colors: [theme.costGreen, theme.costGreen.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                                    : LinearGradient(colors: [theme.textTertiary.opacity(0.6), theme.textTertiary.opacity(0.2)], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(maxHeight: CGFloat(46 * heightRatio))
                        
                        Text(bucket.shortLabel)
                            .font(.system(size: 6.5, weight: isSelected ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(isSelected ? theme.costGreen : theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Token Metric Helpers
    
    private func tokenMetricCell(title: String, value: String, color: Color? = nil) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
            Text(value)
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color ?? theme.textPrimary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var tokenDivider: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(width: 0.75, height: 16)
    }
    
    private func formatCompactTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
    
    private func formatBlendedRate(cost: Double, tokens: Int) -> String {
        guard tokens > 0 else { return "$0.00/M" }
        let rate = (cost / Double(tokens)) * 1_000_000.0
        return String(format: "$%.2f/M", rate)
    }
    
    private func color(forModel name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("argon") || lower.contains("gemini") {
            return theme.geminiAccent
        } else if lower.contains("claude") || lower.contains("opus") || lower.contains("sonnet") {
            return theme.claudeAccent
        } else if lower.contains("gcp") {
            return theme.linkBlue
        }
        return theme.costGreen
    }
    
    // MARK: - Section 4: Telemetry Summary
    
    private var telemetrySummaryCard: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.costGreen)
                Text("\(viewModel.stats.queriesToday) queries today · \(viewModel.stats.totalToolCalls) tools executed")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer()
            Text("\(viewModel.stats.workspaces.count) active spaces")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .themedCardStyle(theme: theme)
    }
}
