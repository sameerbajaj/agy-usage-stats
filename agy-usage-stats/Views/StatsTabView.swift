//
//  StatsTabView.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import SwiftUI

// MARK: - Telemetry Badge
struct TelemetryBadge: View {
    @State private var pulse = false
    
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color.green)
                .frame(width: 4, height: 4)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .opacity(pulse ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
            
            Text("telemetry")
                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.08))
        )
        .onAppear {
            pulse = true
        }
    }
}

// MARK: - Quota Bucket Row
struct QuotaBucketRow: View {
    @Environment(\.colorScheme) var colorScheme
    let groupDisplayName: String
    let bucket: AgyQuotaBucket
    
    private var isDark: Bool { colorScheme == .dark }
    private var geminiColor: Color { Color.gemini(isDark: isDark) }
    private var claudeColor: Color { Color.claude(isDark: isDark) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                
                Spacer()
                
                if let fraction = bucket.remainingFraction {
                    Text(String(format: "%.0f%%", fraction * 100))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(quotaTextColor(for: groupDisplayName, fraction: fraction))
                } else {
                    Text("unlimited")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            
            if let fraction = bucket.remainingFraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.primary.opacity(0.04))
                        
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(
                                LinearGradient(
                                    colors: quotaGradientColors(for: groupDisplayName, fraction: fraction),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * CGFloat(fraction)))
                    }
                }
                .frame(height: 3)
            }
            
            if let cleaned = resolveResetDescription() {
                Text(cleaned)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
        }
        .padding(.vertical, 2)
    }
    
    private func resolveResetDescription() -> String? {
        if let resetTimeStr = bucket.resetTime,
           let date = ISO8601DateFormatter().date(from: resetTimeStr) {
            let now = Date()
            let diff = date.timeIntervalSince(now)
            if diff > 0 {
                let days = Int(diff) / 86400
                let hours = (Int(diff) % 86400) / 3600
                let minutes = (Int(diff) % 3600) / 60
                
                let timeString: String
                if days > 0 {
                    timeString = "refreshes in \(days) day\(days == 1 ? "" : "s"), \(hours) hour\(hours == 1 ? "" : "s")"
                } else if hours > 0 {
                    timeString = "refreshes in \(hours) hour\(hours == 1 ? "" : "s"), \(minutes) minute\(minutes == 1 ? "" : "s")"
                } else {
                    timeString = "refreshes in \(minutes) minute\(minutes == 1 ? "" : "s")"
                }
                
                if let desc = bucket.resetDescription {
                    let sentences = desc.components(separatedBy: ".")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    
                    let extraSentences = sentences.filter { sentence in
                        let lower = sentence.lowercased()
                        return !lower.contains("refresh") && !lower.contains("reset") && !lower.contains("limit")
                    }
                    
                    if !extraSentences.isEmpty {
                        let joinedExtra = extraSentences.joined(separator: ". ")
                        return timeString + ". " + joinedExtra.lowercased()
                    }
                }
                return timeString
            }
        }
        
        guard let desc = bucket.resetDescription else { return nil }
        let lower = desc.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        for key in ["fully refresh in ", "refreshes in ", "refresh in "] {
            if let range = lower.range(of: key) {
                let timePart = String(lower[range.upperBound...])
                return "refreshes in " + timePart
            }
        }
        return lower
    }
    
    private func quotaTextColor(for group: String, fraction: Double) -> Color {
        if fraction <= 0.2 {
            return Color(red: 1.0, green: 0.35, blue: 0.35)
        }
        let isGemini = group.lowercased().contains("gemini")
        return isGemini ? geminiColor : claudeColor
    }
    
    private func quotaGradientColors(for group: String, fraction: Double) -> [Color] {
        if fraction <= 0.2 {
            return [Color(red: 1.0, green: 0.3, blue: 0.3), Color(red: 1.0, green: 0.45, blue: 0.45)]
        }
        let isGemini = group.lowercased().contains("gemini")
        if isGemini {
            return [geminiColor, Color(red: 0.28, green: 0.68, blue: 1.0)]
        } else {
            return [claudeColor, Color(red: 1.0, green: 0.65, blue: 0.2)]
        }
    }
}

// MARK: - Tool Stat Row
struct ToolStatRow: View {
    let tool: ToolStat
    let maxCount: Double
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tool.iconName)
                .font(.system(size: 9))
                .foregroundStyle(tool.categoryColor)
                .frame(width: 16, height: 16)
                .background(tool.categoryColor.opacity(0.08))
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(tool.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                    Spacer()
                    Text("\(tool.count)")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                
                GeometryReader { geo in
                    let pct = maxCount > 0 ? Double(tool.count) / maxCount : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.primary.opacity(0.04))
                        
                        RoundedRectangle(cornerRadius: 1)
                            .fill(tool.categoryColor.opacity(0.8))
                            .frame(width: geo.size.width * CGFloat(pct))
                    }
                }
                .frame(height: 2.5)
            }
        }
        .padding(6)
        .background(Color.primary.opacity(isHovered ? 0.035 : 0.0))
        .cornerRadius(6)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Main View
struct StatsTabView: View {
    @Environment(\.colorScheme) var colorScheme
    let viewModel: AgyStatsViewModel
    
    @State private var quotaCardHovered: [String: Bool] = [:]
    @State private var toolsCardHovered = false
    
    private var isDark: Bool { colorScheme == .dark }
    private var geminiColor: Color { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme).geminiAccent }
    private var claudeColor: Color { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme).claudeAccent }
    private var theme: ThemeColors { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme) }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Active Model Row
                activeModelRow
                    .padding(.top, 4)
                
                // Metrics Strip
                metricsStrip
                
                // Remaining Quotas List
                remainingQuotasList
                
                // Tool Execution Breakdown
                toolExecutionBreakdown
            }
            .padding(12)
        }
        .background(theme.surfacePrimary)
    }
    
    private var activeModelRow: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(geminiColor)
                Text(viewModel.settings.model ?? (viewModel.stats.quotaInfo?.plan ?? "Gemini 3.5 Flash"))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            Spacer()
            if viewModel.settings.enableTelemetry == true {
                TelemetryBadge()
            }
        }
        .padding(.horizontal, 2)
    }
    
    private var metricsStrip: some View {
        HStack(spacing: 0) {
            metricItem(title: "today", value: "\(viewModel.stats.queriesToday)", color: geminiColor)
            metricDivider
            metricItem(title: "week", value: "\(viewModel.stats.queriesThisWeek)", color: Color(red: 0.28, green: 0.68, blue: 1.0))
            metricDivider
            metricItem(title: "total", value: "\(viewModel.stats.totalQueries)", color: Color(red: 0.15, green: 0.85, blue: 0.55))
            metricDivider
            metricItem(title: "tools", value: "\(viewModel.stats.totalToolCalls)", color: Color(red: 1.0, green: 0.45, blue: 0.45))
        }
        .padding(.vertical, 8)
        .themedCardStyle(theme: theme)
    }
    
    private var metricDivider: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(width: 0.75)
            .frame(maxHeight: 18)
    }
    
    private func metricItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var remainingQuotasList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("remaining quotas")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if let email = viewModel.stats.quotaInfo?.email {
                    Text(email)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
            }
            .padding(.horizontal, 4)
            
            if let quota = viewModel.stats.quotaInfo, !quota.groups.isEmpty {
                VStack(spacing: 8) {
                    ForEach(quota.groups) { group in
                        let isHovered = quotaCardHovered[group.displayName] ?? false
                        let isGemini = group.displayName.lowercased().contains("gemini")
                        let cardAccent = isGemini ? geminiColor : claudeColor
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(group.displayName.lowercased())
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(cardAccent)
                                
                                Spacer()
                            }
                            
                            VStack(spacing: 8) {
                                ForEach(group.sortedBuckets) { bucket in
                                    QuotaBucketRow(groupDisplayName: group.displayName, bucket: bucket)
                                }
                            }
                        }
                        .padding(10)
                        .themedCardStyle(theme: theme, isHovered: isHovered, accentColor: cardAccent)
                        .onHover { hovering in
                            quotaCardHovered[group.displayName] = hovering
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.yellow.opacity(0.6))
                        
                        Text("no active quota session")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.85))
                        
                        Text("run agy cli to activate quota info")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 16)
                    Spacer()
                }
                .themedCardStyle(theme: theme)
            }
        }
    }
    
    private var toolExecutionBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("tool executions")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            if viewModel.stats.toolStats.isEmpty {
                HStack {
                    Spacer()
                    Text("no tool calls recorded")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .padding(.vertical, 16)
                    Spacer()
                }
                .themedCardStyle(theme: theme)
            } else {
                VStack(spacing: 4) {
                    let maxCount = Double(viewModel.stats.toolStats.first?.count ?? 1)
                    ForEach(viewModel.stats.toolStats) { tool in
                        ToolStatRow(tool: tool, maxCount: maxCount)
                    }
                }
                .padding(8)
                .themedCardStyle(theme: theme, isHovered: toolsCardHovered, accentColor: Color(red: 1.0, green: 0.45, blue: 0.45))
                .onHover { hovering in
                    toolsCardHovered = hovering
                }
            }
        }
    }
}
