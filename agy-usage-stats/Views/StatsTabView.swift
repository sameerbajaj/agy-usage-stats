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
        HStack(spacing: 4) {
            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)
                .scaleEffect(pulse ? 1.4 : 1.0)
                .opacity(pulse ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            
            Text("Telemetry Active")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.green.opacity(0.1))
                .overlay(Capsule().stroke(Color.green.opacity(0.2), lineWidth: 1))
        )
        .onAppear {
            pulse = true
        }
    }
}

// MARK: - Metric Card Component
struct MetricCardView: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(isHovered ? 0.6 : 0.0), radius: 3)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .premiumCardStyle(isHovered: isHovered, accentColor: color)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Quota Bucket Row
struct QuotaBucketRow: View {
    let groupDisplayName: String
    let bucket: AgyQuotaBucket
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(bucket.displayName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                
                Spacer()
                
                if let fraction = bucket.remainingFraction {
                    Text(String(format: "%.1f%% remaining", fraction * 100))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(quotaTextColor(for: groupDisplayName, fraction: fraction))
                } else {
                    Text("Unlimited")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            
            if let fraction = bucket.remainingFraction {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Track background
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.06))
                        
                        // Fill track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: quotaGradientColors(for: groupDisplayName, fraction: fraction),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, geo.size.width * CGFloat(fraction)))
                            .shadow(color: quotaGradientColors(for: groupDisplayName, fraction: fraction)[0].opacity(0.3), radius: 3, x: 0, y: 0)
                    }
                }
                .frame(height: 6)
            }
            
            if let resetDesc = bucket.resetDescription {
                Text(resetDesc)
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .padding(.vertical, 4)
    }
    
    private func quotaTextColor(for group: String, fraction: Double) -> Color {
        if fraction <= 0.2 {
            return Color(red: 1.0, green: 0.35, blue: 0.35) // Soft red warning
        }
        let isGemini = group.lowercased().contains("gemini")
        if isGemini {
            return Color(red: 0.55, green: 0.75, blue: 1.0) // Soft sapphire blue
        } else {
            return Color(red: 1.0, green: 0.7, blue: 0.4) // Soft amber orange
        }
    }
    
    private func quotaGradientColors(for group: String, fraction: Double) -> [Color] {
        if fraction <= 0.2 {
            return [Color(red: 1.0, green: 0.3, blue: 0.3), Color(red: 1.0, green: 0.5, blue: 0.5)]
        }
        let isGemini = group.lowercased().contains("gemini")
        if isGemini {
            return [Color(red: 0.58, green: 0.38, blue: 0.95), Color(red: 0.28, green: 0.68, blue: 1.0)]
        } else {
            return [Color(red: 0.95, green: 0.45, blue: 0.2), Color(red: 1.0, green: 0.68, blue: 0.35)]
        }
    }
}

// MARK: - Tool Stat Row
struct ToolStatRow: View {
    let tool: ToolStat
    let maxCount: Double
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(tool.categoryColor.opacity(isHovered ? 0.2 : 0.12))
                    .frame(width: 24, height: 24)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
                
                Image(systemName: tool.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(tool.categoryColor)
                    .shadow(color: tool.categoryColor.opacity(isHovered ? 0.5 : 0.0), radius: 3)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(tool.displayName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(tool.count)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.85))
                }
                
                GeometryReader { geo in
                    let pct = maxCount > 0 ? Double(tool.count) / maxCount : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.06))
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(tool.categoryColor)
                            .frame(width: geo.size.width * CGFloat(pct))
                            .shadow(color: tool.categoryColor.opacity(isHovered ? 0.4 : 0.0), radius: 2)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isHovered ? 0.03 : 0.015))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(isHovered ? 0.06 : 0.02), lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Main View
struct StatsTabView: View {
    let viewModel: AgyStatsViewModel
    
    @State private var quotaCardHovered: [String: Bool] = [:]
    @State private var activeModelCardHovered = false
    @State private var toolsCardHovered = false
    
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
    
    // MARK: - Remaining Quotas Card
    private var remainingQuotasCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Remaining Quotas")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                if let email = viewModel.stats.quotaInfo?.email {
                    Text(email)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 4)
            
            if let quota = viewModel.stats.quotaInfo, !quota.groups.isEmpty {
                VStack(spacing: 12) {
                    ForEach(quota.groups) { group in
                        let isHovered = quotaCardHovered[group.displayName] ?? false
                        let isGemini = group.displayName.lowercased().contains("gemini")
                        let cardAccent = isGemini 
                            ? Color(red: 0.55, green: 0.25, blue: 0.95)
                            : Color(red: 1.0, green: 0.45, blue: 0.2)
                        
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                HStack(spacing: 6) {
                                    Image(systemName: isGemini ? "sparkles" : "cpu.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(cardAccent)
                                        .shadow(color: cardAccent.opacity(isHovered ? 0.6 : 0.0), radius: 3)
                                    
                                    Text(group.displayName)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                
                                Spacer()
                                
                                if let desc = group.description {
                                    let cleanDesc = desc.replacingOccurrences(of: "Models within this group: ", with: "")
                                    Text(cleanDesc)
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundStyle(Color.white.opacity(0.35))
                                        .lineLimit(1)
                                }
                            }
                            
                            VStack(spacing: 10) {
                                ForEach(group.buckets) { bucket in
                                    QuotaBucketRow(groupDisplayName: group.displayName, bucket: bucket)
                                }
                            }
                        }
                        .padding(12)
                        .premiumCardStyle(isHovered: isHovered, accentColor: cardAccent)
                        .onHover { hovering in
                            quotaCardHovered[group.displayName] = hovering
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.yellow.opacity(0.8))
                        
                        Text("No Active Quota Session")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Text("Start the agy CLI or language server to view remaining limits.")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 24)
                    Spacer()
                }
                .premiumCardStyle()
            }
        }
    }
    
    // MARK: - Metrics Grid
    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricCardView(
                title: "Queries Today",
                value: "\(viewModel.stats.queriesToday)",
                systemImage: "calendar.badge.clock",
                color: Color(red: 0.58, green: 0.38, blue: 0.95) // Violet
            )
            
            MetricCardView(
                title: "Queries This Week",
                value: "\(viewModel.stats.queriesThisWeek)",
                systemImage: "waveform.path.ecg",
                color: Color(red: 0.28, green: 0.68, blue: 1.0) // Sapphire
            )
            
            MetricCardView(
                title: "Total Queries",
                value: "\(viewModel.stats.totalQueries)",
                systemImage: "command",
                color: Color(red: 0.15, green: 0.85, blue: 0.55) // Emerald
            )
            
            MetricCardView(
                title: "Tool Calls",
                value: "\(viewModel.stats.totalToolCalls)",
                systemImage: "cpu",
                color: Color(red: 1.0, green: 0.45, blue: 0.45) // Sunset Coral
            )
        }
    }
    
    // MARK: - Active Model Card
    private var activeModelCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.58, green: 0.38, blue: 0.95), Color(red: 0.28, green: 0.68, blue: 1.0)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 32, height: 32)
                    .shadow(color: Color(red: 0.58, green: 0.38, blue: 0.95).opacity(activeModelCardHovered ? 0.5 : 0.0), radius: 4)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("ACTIVE MODEL")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.45))
                
                Text(viewModel.settings.model ?? (viewModel.stats.quotaInfo?.plan ?? "Gemini 3.5 Flash"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            Spacer()
            
            if viewModel.settings.enableTelemetry == true {
                TelemetryBadge()
            }
        }
        .padding(12)
        .premiumCardStyle(isHovered: activeModelCardHovered, accentColor: Color(red: 0.58, green: 0.38, blue: 0.95))
        .onHover { hovering in
            activeModelCardHovered = hovering
        }
    }
    
    // MARK: - Tool Execution Breakdown
    private var toolExecutionBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tool Executions")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .padding(.horizontal, 4)
            
            if viewModel.stats.toolStats.isEmpty {
                HStack {
                    Spacer()
                    Text("No tool calls recorded yet")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.3))
                        .padding(.vertical, 24)
                    Spacer()
                }
                .premiumCardStyle()
            } else {
                VStack(spacing: 8) {
                    let maxCount = Double(viewModel.stats.toolStats.first?.count ?? 1)
                    
                    ForEach(viewModel.stats.toolStats) { tool in
                        ToolStatRow(tool: tool, maxCount: maxCount)
                    }
                }
                .padding(10)
                .premiumCardStyle(isHovered: toolsCardHovered, accentColor: .pink)
                .onHover { hovering in
                    toolsCardHovered = hovering
                }
            }
        }
    }
}
