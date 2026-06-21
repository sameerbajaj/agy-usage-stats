//
//  CostTabView.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import SwiftUI

struct CostTabView: View {
    @Environment(\.colorScheme) var colorScheme
    let viewModel: AgyStatsViewModel
    
    @State private var hoveredModelId: String? = nil
    @State private var localSelectedModelId: String? = nil
    @State private var showPricingTemplates = false
    @State private var showQueryLogs = false
    
    private var isDark: Bool { colorScheme == .dark }
    private var theme: ThemeColors { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme) }
    
    struct ModelAnalysis: Identifiable {
        let id: String
        let modelName: String
        let queryCount: Int
        let totalCost: Double
        let inputTokens: Int
        let outputTokens: Int
    }
    
    private var todayModelAnalysis: [ModelAnalysis] {
        let todayQueries = viewModel.stats.recentQueries.filter { q in
            Calendar.current.isDateInToday(q.timestamp)
        }
        
        var groups: [String: (count: Int, cost: Double, input: Int, output: Int)] = [:]
        
        for q in todayQueries {
            let modelInfo = getModelCostInfo(for: q)
            let (inTokens, outTokens, cost) = modelInfo.estimateTokensAndCost(for: q)
            
            let current = groups[modelInfo.name] ?? (count: 0, cost: 0.0, input: 0, output: 0)
            groups[modelInfo.name] = (
                count: current.count + 1,
                cost: current.cost + cost,
                input: current.input + inTokens,
                output: current.output + outTokens
            )
        }
        
        return groups.map { modelName, data in
            ModelAnalysis(
                id: modelName,
                modelName: modelName,
                queryCount: data.count,
                totalCost: data.cost,
                inputTokens: data.input,
                outputTokens: data.output
            )
        }.sorted { $0.totalCost > $1.totalCost }
    }
    
    private var todayInsights: [String] {
        let analysis = todayModelAnalysis
        guard !analysis.isEmpty else {
            return ["No query activity recorded yet for today."]
        }
        
        var insights: [String] = []
        let totalCost = analysis.reduce(0.0) { $0 + $1.totalCost }
        let totalQueries = analysis.reduce(0) { $0 + $1.queryCount }
        let totalInput = analysis.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = analysis.reduce(0) { $0 + $1.outputTokens }
        
        if let highest = analysis.first {
            let percentage = totalCost > 0 ? (highest.totalCost / totalCost) * 100 : 0
            if percentage > 40 {
                let cleanedName = highest.modelName
                    .replacingOccurrences(of: " (Thinking)", with: "")
                    .replacingOccurrences(of: " (High)", with: "")
                    .replacingOccurrences(of: " (Medium)", with: "")
                    .replacingOccurrences(of: " (Low)", with: "")
                insights.append(String(format: "%@ was responsible for %.0f%% of today's spend ($%.2f).", cleanedName, percentage, highest.totalCost))
            }
        }
        
        let totalTokens = totalInput + totalOutput
        if totalTokens > 0 {
            let outputRatio = Double(totalOutput) / Double(totalTokens) * 100
            insights.append(String(format: "Output tokens represent %.1f%% of today's volume (reasoning intensive).", outputRatio))
        }
        
        if totalQueries > 0 {
            let avgCost = totalCost / Double(totalQueries)
            insights.append(String(format: "Average cost per query today is $%.3f across %d runs.", avgCost, totalQueries))
        }
        
        return insights
    }
    
    private var activeModel: ModelCostInfo {
        let activeName = viewModel.settings.model ?? ""
        let cleanedActive = activeName.replacingOccurrences(of: " (current)", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        if let matched = knownModels.first(where: { cleanedActive.contains($0.name.replacingOccurrences(of: " (current)", with: "").lowercased()) || $0.name.lowercased().contains(cleanedActive) }) {
            return matched
        }
        
        return knownModels[2] // Gemini 3.5 Flash (High)
    }
    
    private var selectedModel: ModelCostInfo {
        if let localId = localSelectedModelId,
           let found = knownModels.first(where: { $0.id == localId }) {
            return found
        }
        return activeModel
    }
    
    private func getModelCostInfo(for query: QueryEntry) -> ModelCostInfo {
        let name = query.modelName ?? viewModel.settings.model ?? ""
        let cleaned = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let found = knownModels.first(where: {
            let mName = $0.name.lowercased()
            return cleaned.contains(mName) || mName.contains(cleaned)
        }) {
            return found
        }
        return knownModels[2] // default Gemini 3.5 Flash (High)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // API Cost Estimates Summary Card
                costSummaryCard
                
                // Today's Usage & Cost Analysis Section
                todayAnalysisSection
                
                // Collapsible Pricing Templates
                VStack(spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showPricingTemplates.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showPricingTemplates ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                            
                            Text("pricing templates")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                    
                    if showPricingTemplates {
                        VStack(spacing: 4) {
                            ForEach(knownModels) { model in
                                let isActive = model.id == activeModel.id
                                let isSelected = model.id == selectedModel.id
                                let isHovered = hoveredModelId == model.id
                                
                                Button {
                                    localSelectedModelId = model.id
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(isSelected ? Color.green : Color.clear)
                                            .frame(width: 4, height: 4)
                                            .overlay(Circle().stroke(Color.primary.opacity(isSelected ? 0 : 0.2), lineWidth: 0.75))
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 4) {
                                                Text(model.name)
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.8))
                                                
                                                if isActive {
                                                    Text("active")
                                                        .font(.system(size: 7.5, weight: .bold))
                                                        .foregroundStyle(.green)
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Capsule().fill(Color.green.opacity(0.08)))
                                                }
                                            }
                                            
                                            Text(String(format: "$%.3f/q • rate: $%.2f / $%.2f per M", model.costPerQuery, model.inputPricePerMillion, model.outputPricePerMillion))
                                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelected ? Color.green.opacity(0.04) : (isHovered ? Color.primary.opacity(0.02) : Color.clear))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(isSelected ? Color.green.opacity(0.15) : Color.clear, lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)
                                .onHover { hovering in
                                    hoveredModelId = hovering ? model.id : nil
                                }
                            }
                        }
                    }
                }
                
                // Collapsible Today's Query Logs Section
                VStack(spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showQueryLogs.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showQueryLogs ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                            
                            Text("today's query logs")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                    }
                    .buttonStyle(.plain)
                    
                    if showQueryLogs {
                        let todayQueries = viewModel.stats.recentQueries.filter { q in
                            Calendar.current.isDateInToday(q.timestamp)
                        }
                        
                        if todayQueries.isEmpty {
                            VStack(spacing: 6) {
                                Image(systemName: "clock.badge.checkmark")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Text("no queries run today")
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .themedCardStyle(theme: theme)
                        } else {
                            VStack(spacing: 4) {
                                ForEach(todayQueries) { query in
                                    let modelInfo = getModelCostInfo(for: query)
                                    let (inTokens, outTokens, cost) = modelInfo.estimateTokensAndCost(for: query)
                                    let calls = query.conversationMeta?.llmCalls ?? 1
                                    let isGemini = modelInfo.name.lowercased().contains("gemini")
                                    let modelColor = isGemini ? theme.geminiAccent : theme.claudeAccent
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(alignment: .top) {
                                            Text(query.display)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.primary.opacity(0.85))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                            
                                            Spacer()
                                            
                                            Text(String(format: "$%.3f", cost))
                                                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                                                .foregroundStyle(theme.costGreen)
                                        }
                                        
                                        HStack(spacing: 4) {
                                            Text(modelInfo.name.replacingOccurrences(of: " (current)", with: "").replacingOccurrences(of: " (Low)", with: "").replacingOccurrences(of: " (Medium)", with: "").replacingOccurrences(of: " (High)", with: "").replacingOccurrences(of: " (Thinking)", with: ""))
                                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                                .foregroundStyle(modelColor)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(modelColor.opacity(0.06)))
                                            
                                            Text("\(formatNumber(inTokens)) in / \(formatNumber(outTokens)) out")
                                                .font(.system(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                            
                                            if calls > 1 {
                                                Text("\(calls) turns")
                                                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(theme.linkBlue)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Capsule().fill(theme.linkBlue.opacity(0.08)))
                                            }
                                            
                                            Spacer()
                                            
                                            Text(formattedTime(query.timestamp))
                                                .font(.system(size: 8))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(theme.surfaceSecondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(theme.cardStroke, lineWidth: 0.5)
                                    )
                                }
                            }
                            .padding(8)
                            .themedCardStyle(theme: theme)
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(theme.surfacePrimary)
    }
    
    // MARK: - Cost Summary Card
    
    private var costSummaryCard: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "banknote")
                        .font(.system(size: 9))
                        .foregroundStyle(.green)
                    Text("api cost estimates")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            
            HStack(spacing: 0) {
                costColumn(title: "today", cost: viewModel.stats.todayCostEstimate)
                metricDivider
                costColumn(title: "week", cost: viewModel.stats.weeklyCostEstimate)
                metricDivider
                costColumn(title: "total", cost: viewModel.stats.totalCostEstimate)
            }
            .padding(.vertical, 8)
            .themedCardStyle(theme: theme)
        }
    }
    
    private var metricDivider: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(width: 0.75)
            .frame(maxHeight: 18)
    }
    
    private func costColumn(title: String, cost: Double) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            
            Text(String(format: "$%.2f", cost))
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Today's Cost & Token Analysis Section
    
    private var todayAnalysisSection: some View {
        let analysis = todayModelAnalysis
        let todayTotalCost = viewModel.stats.todayCostEstimate
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.geminiAccent)
                Text("today's cost & token analysis")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                if analysis.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "chart.pie")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary.opacity(0.6))
                            Text("no model activity today")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary.opacity(0.8))
                        }
                        .padding(.vertical, 16)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(analysis) { model in
                            let isGemini = model.modelName.lowercased().contains("gemini")
                            let modelColor = isGemini ? theme.geminiAccent : theme.claudeAccent
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(model.modelName.replacingOccurrences(of: " (current)", with: "").replacingOccurrences(of: " (Low)", with: "").replacingOccurrences(of: " (Medium)", with: "").replacingOccurrences(of: " (High)", with: "").replacingOccurrences(of: " (Thinking)", with: ""))
                                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                        .foregroundStyle(modelColor)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Capsule().fill(modelColor.opacity(0.08)))
                                    
                                    Text("\(model.queryCount) \(model.queryCount == 1 ? "query" : "queries")")
                                        .font(.system(size: 8.5, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    
                                    Spacer()
                                    
                                    Text(String(format: "$%.2f", model.totalCost))
                                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(theme.costGreen)
                                }
                                
                                // Cost Share Progress Bar
                                let sharePct = todayTotalCost > 0 ? CGFloat(model.totalCost / todayTotalCost) : 0.0
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.primary.opacity(0.03))
                                        
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(modelColor)
                                            .frame(width: geo.size.width * sharePct)
                                    }
                                }
                                .frame(height: 2.5)
                                .padding(.vertical, 1)
                                
                                // Token Counts
                                HStack {
                                    Text("\(formatNumber(model.inputTokens)) in • \(formatNumber(model.outputTokens)) out")
                                        .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    
                                    Spacer()
                                    
                                    let totalTokens = model.inputTokens + model.outputTokens
                                    Text("\(formatNumber(totalTokens)) total")
                                        .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(.secondary.opacity(0.8))
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(theme.surfaceSecondary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(theme.cardStroke, lineWidth: 0.5)
                            )
                        }
                    }
                    
                    if !todayInsights.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Divider()
                                .padding(.vertical, 4)
                            
                            Text("insights")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                            
                            ForEach(todayInsights, id: \.self) { insight in
                                HStack(alignment: .top, spacing: 5) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8))
                                        .foregroundStyle(theme.geminiAccent)
                                        .padding(.top, 2)
                                    
                                    Text(insight)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.primary.opacity(0.75))
                                        .lineLimit(nil)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .themedCardStyle(theme: theme, accentColor: theme.geminiAccent)
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    private func formatNumber(_ num: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }
}
