//
//  StatsTabView.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import SwiftUI

struct StatsTabView: View {
    let viewModel: AgyStatsViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Section 0: Remaining Quotas
                remainingQuotasCard
                
                // Section 1: Metrics Grid
                metricsGrid
                
                // Section 2: Active Model Card
                activeModelCard
                
                // Section 3: Tool Execution Breakdown
                toolExecutionBreakdown
            }
            .padding(12)
        }
    }
    
    // MARK: - Remaining Quotas
    
    private var remainingQuotasCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Remaining Quotas")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer()
                if let email = viewModel.stats.quotaInfo?.email {
                    Text(email)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 4)
            
            if let quota = viewModel.stats.quotaInfo, !quota.groups.isEmpty {
                VStack(spacing: 12) {
                    ForEach(quota.groups) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(group.displayName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                Spacer()
                                if let desc = group.description {
                                    let cleanDesc = desc.replacingOccurrences(of: "Models within this group: ", with: "")
                                    Text(cleanDesc)
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.white.opacity(0.4))
                                        .lineLimit(1)
                                }
                            }
                            
                            ForEach(group.buckets) { bucket in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(bucket.displayName)
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.8))
                                        Spacer()
                                        if let fraction = bucket.remainingFraction {
                                            Text(String(format: "%.1f%% remaining", fraction * 100))
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(quotaColor(for: fraction))
                                        } else {
                                            Text("Unlimited/Unknown")
                                                .font(.system(size: 10))
                                                .foregroundStyle(Color.white.opacity(0.4))
                                        }
                                    }
                                    
                                    if let fraction = bucket.remainingFraction {
                                        GeometryReader { geo in
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.white.opacity(0.06))
                                                .frame(height: 6)
                                                .overlay(
                                                    HStack(spacing: 0) {
                                                        RoundedRectangle(cornerRadius: 3)
                                                            .fill(
                                                                LinearGradient(
                                                                    colors: quotaGradientColors(for: group.displayName, fraction: fraction),
                                                                    startPoint: .leading,
                                                                    endPoint: .trailing
                                                                )
                                                            )
                                                            .frame(width: geo.size.width * CGFloat(fraction))
                                                        Spacer(minLength: 0)
                                                    }
                                                )
                                        }
                                        .frame(height: 6)
                                    }
                                    
                                    if let resetDesc = bucket.resetDescription {
                                        Text(resetDesc)
                                            .font(.system(size: 8))
                                            .foregroundStyle(Color.white.opacity(0.45))
                                    }
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.015))
                                )
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.02))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                        )
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.yellow.opacity(0.7))
                        Text("No active quota session detected")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                        Text("Start the agy CLI or language server to view remaining limits.")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.02))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
            }
        }
    }
    
    private func quotaColor(for fraction: Double) -> Color {
        if fraction > 0.5 {
            return .green
        } else if fraction > 0.2 {
            return .orange
        } else {
            return .red
        }
    }
    
    private func quotaGradientColors(for group: String, fraction: Double) -> [Color] {
        let isGemini = group.lowercased().contains("gemini")
        if isGemini {
            return [Color(red: 0.55, green: 0.25, blue: 0.95), Color(red: 0.25, green: 0.65, blue: 1.0)]
        } else {
            return [Color(red: 1.0, green: 0.4, blue: 0.2), Color(red: 1.0, green: 0.65, blue: 0.3)]
        }
    }
    
    // MARK: - Metrics Grid
    
    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricCard(
                title: "Queries Today",
                value: "\(viewModel.stats.queriesToday)",
                systemImage: "calendar.badge.clock",
                color: Color(red: 0.55, green: 0.25, blue: 0.95) // Purple
            )
            
            metricCard(
                title: "Queries This Week",
                value: "\(viewModel.stats.queriesThisWeek)",
                systemImage: "waveform.path.ecg",
                color: Color(red: 0.25, green: 0.65, blue: 1.0) // Blue
            )
            
            metricCard(
                title: "Total Queries",
                value: "\(viewModel.stats.totalQueries)",
                systemImage: "command",
                color: Color(red: 0.1, green: 0.8, blue: 0.5) // Green
            )
            
            metricCard(
                title: "Tool Calls",
                value: "\(viewModel.stats.totalToolCalls)",
                systemImage: "cpu",
                color: Color(red: 1.0, green: 0.4, blue: 0.4) // Orange/Red
            )
        }
    }
    
    private func metricCard(title: String, value: String, systemImage: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Active Model Card
    
    private var activeModelCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.55, green: 0.25, blue: 0.95), Color(red: 0.25, green: 0.65, blue: 1.0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Active Model")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                
                Text(viewModel.settings.model ?? (viewModel.stats.quotaInfo?.plan ?? "Gemini 3.5 Flash"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            if viewModel.settings.enableTelemetry == true {
                Text("Telemetry Active")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.12))
                            .overlay(Capsule().stroke(Color.green.opacity(0.25), lineWidth: 1))
                    )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Tool Execution Breakdown
    
    private var toolExecutionBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tool Executions")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.7))
                .padding(.horizontal, 4)
            
            if viewModel.stats.toolStats.isEmpty {
                HStack {
                    Spacer()
                    Text("No tool calls recorded yet")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .padding(.vertical, 20)
                    Spacer()
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white.opacity(0.02))
                )
            } else {
                VStack(spacing: 8) {
                    let maxCount = Double(viewModel.stats.toolStats.first?.count ?? 1)
                    
                    ForEach(viewModel.stats.toolStats) { tool in
                        HStack(spacing: 10) {
                            // Category Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(tool.categoryColor.opacity(0.12))
                                    .frame(width: 22, height: 22)
                                Image(systemName: tool.iconName)
                                    .font(.system(size: 10))
                                    .foregroundStyle(tool.categoryColor)
                            }
                            
                            // Text details
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(tool.displayName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("\(tool.count)")
                                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                                        .foregroundStyle(Color.white.opacity(0.8))
                                }
                                
                                // Progress bar
                                GeometryReader { geo in
                                    let pct = maxCount > 0 ? Double(tool.count) / maxCount : 0
                                    
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.white.opacity(0.06))
                                        .frame(height: 4)
                                        .overlay(
                                            HStack(spacing: 0) {
                                                RoundedRectangle(cornerRadius: 2)
                                                    .fill(tool.categoryColor)
                                                    .frame(width: geo.size.width * CGFloat(pct))
                                                Spacer(minLength: 0)
                                            }
                                        )
                                }
                                .frame(height: 4)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.015))
                        )
                    }
                }
            }
        }
    }
}
