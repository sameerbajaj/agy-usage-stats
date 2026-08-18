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
    
    enum TimeScope: String, CaseIterable, Identifiable {
        case week = "7D"
        case twoWeeks = "14D"
        case month = "30D"
        case monthly = "Monthly"
        
        var id: String { rawValue }
        var displayName: String { rawValue }
    }
    
    enum MetricType: String, CaseIterable, Identifiable {
        case cost = "Cost ($)"
        case queries = "Queries"
        case tokens = "Tokens"
        
        var id: String { rawValue }
        var label: String { rawValue }
    }
    
    @State private var timeScope: TimeScope = .week
    @State private var metricType: MetricType = .cost
    @State private var monthOffset: Int = 0
    @State private var hoveredBucketId: String? = nil
    
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
        
        return defaultGeminiModel
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
        return defaultGeminiModel
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // API Cost Estimates Summary Card
                costSummaryCard
                
                // Interactive Usage & Cost History Bar Chart
                usageTrendsSection
                
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
                        .foregroundStyle(theme.costGreen)
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
    
    // MARK: - Interactive Usage & Cost History Bar Chart Section
    
    // MARK: - Calendar Month Navigation & Active Buckets Helpers
    
    private var currentTargetMonthDate: Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }
    
    private var monthDisplayTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentTargetMonthDate)
    }
    
    private var earliestRecordedDate: Date {
        viewModel.stats.dailyUsage.first?.date ?? Date()
    }
    
    private var canGoBack: Bool {
        let calendar = Calendar.current
        let targetComp = calendar.dateComponents([.year, .month], from: currentTargetMonthDate)
        let earliestComp = calendar.dateComponents([.year, .month], from: earliestRecordedDate)
        
        let tYear = targetComp.year ?? 0
        let tMonth = targetComp.month ?? 0
        let eYear = earliestComp.year ?? 0
        let eMonth = earliestComp.month ?? 0
        
        if tYear > eYear { return true }
        if tYear == eYear { return tMonth > eMonth }
        return false
    }
    
    private var canGoForward: Bool {
        monthOffset < 0
    }
    
    private func getMonthBuckets(for targetDate: Date) -> [UsageTimeBucket] {
        let calendar = Calendar.current
        let comp = calendar.dateComponents([.year, .month], from: targetDate)
        guard let targetYear = comp.year, let targetMonth = comp.month else { return [] }
        
        return viewModel.stats.dailyUsage.filter { bucket in
            let bComp = calendar.dateComponents([.year, .month], from: bucket.date)
            return bComp.year == targetYear && bComp.month == targetMonth
        }
    }
    
    private var activeBuckets: [UsageTimeBucket] {
        switch timeScope {
        case .week:
            if monthOffset == 0 {
                return Array(viewModel.stats.dailyUsage.suffix(7))
            } else {
                let monthDays = getMonthBuckets(for: currentTargetMonthDate)
                return Array(monthDays.suffix(7))
            }
        case .twoWeeks:
            if monthOffset == 0 {
                return Array(viewModel.stats.dailyUsage.suffix(14))
            } else {
                let monthDays = getMonthBuckets(for: currentTargetMonthDate)
                return Array(monthDays.suffix(14))
            }
        case .month:
            let monthDays = getMonthBuckets(for: currentTargetMonthDate)
            if monthDays.isEmpty && monthOffset == 0 {
                return Array(viewModel.stats.dailyUsage.suffix(30))
            }
            return monthDays
        case .monthly:
            return viewModel.stats.monthlyUsage
        }
    }
    
    private var activeHoveredBucket: UsageTimeBucket? {
        if let id = hoveredBucketId, let found = activeBuckets.first(where: { $0.id == id }) {
            return found
        }
        return activeBuckets.last
    }
    
    private func value(for bucket: UsageTimeBucket) -> Double {
        switch metricType {
        case .cost:
            return bucket.totalCost
        case .queries:
            return Double(bucket.queryCount)
        case .tokens:
            return Double(bucket.inputTokens + bucket.outputTokens)
        }
    }
    
    private func formattedValue(_ val: Double) -> String {
        switch metricType {
        case .cost:
            return String(format: "$%.2f", val)
        case .queries:
            return "\(Int(val)) q"
        case .tokens:
            if val >= 1_000_000 {
                return String(format: "%.1fM", val / 1_000_000)
            } else if val >= 1_000 {
                return String(format: "%.0fk", val / 1_000)
            } else {
                return "\(Int(val))"
            }
        }
    }
    
    private func formatTokensCompact(_ count: Int) -> String {
        let d = Double(count)
        if d >= 1_000_000 {
            return String(format: "%.2fM", d / 1_000_000)
        } else if d >= 1_000 {
            return String(format: "%.0fk", d / 1_000)
        } else {
            return "\(count)"
        }
    }
    
    private var usageTrendsSection: some View {
        let buckets = activeBuckets
        let maxVal = max(0.001, buckets.map { value(for: $0) }.max() ?? 1.0)
        let inspected = activeHoveredBucket
        
        return VStack(alignment: .leading, spacing: 8) {
            trendsHeaderRow
            
            VStack(alignment: .leading, spacing: 8) {
                trendsRangePicker
                
                if let bucket = inspected {
                    trendsInspectorView(bucket: bucket)
                }
                
                // Month navigator bar directly above chart
                if timeScope != .monthly {
                    monthNavigatorBar
                }
                
                if buckets.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("no historical usage data for \(monthDisplayTitle.lowercased())")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 105)
                } else {
                    VStack(spacing: 4) {
                        trendsBarsCanvas(buckets: buckets, maxVal: maxVal, inspected: inspected)
                        trendsXAxis(buckets: buckets, inspected: inspected)
                    }
                    .padding(.horizontal, 2)
                }
                
                if !buckets.isEmpty {
                    trendsSummary(buckets: buckets)
                }
            }
            .padding(10)
            .themedCardStyle(theme: theme, accentColor: theme.geminiAccent)
        }
    }
    
    private var monthNavigatorBar: some View {
        HStack(alignment: .center, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if canGoBack {
                        monthOffset -= 1
                        hoveredBucketId = nil
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(canGoBack ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.25))
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(canGoBack ? theme.surfaceSecondary : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            
            Spacer()
            
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 8))
                    .foregroundStyle(theme.geminiAccent)
                
                Text(monthDisplayTitle)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.9))
                
                if monthOffset != 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            monthOffset = 0
                            hoveredBucketId = nil
                        }
                    } label: {
                        Text("Current")
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.geminiAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(theme.geminiAccent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if canGoForward {
                        monthOffset += 1
                        hoveredBucketId = nil
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(canGoForward ? Color.primary.opacity(0.85) : Color.secondary.opacity(0.25))
                .frame(width: 22, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(canGoForward ? theme.surfaceSecondary : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.surfaceSecondary.opacity(0.4))
        )
    }
    
    private var trendsHeaderRow: some View {
        HStack(alignment: .center) {
            HStack(spacing: 5) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.geminiAccent)
                Text("usage & cost trends")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 2) {
                ForEach(MetricType.allCases) { metric in
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            metricType = metric
                        }
                    } label: {
                        Text(metric.label)
                            .font(.system(size: 8, weight: metricType == metric ? .bold : .medium, design: .rounded))
                            .foregroundStyle(metricType == metric ? theme.geminiAccent : Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(metricType == metric ? theme.geminiAccent.opacity(0.14) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(2)
            .background(Capsule().fill(theme.surfaceSecondary))
        }
        .padding(.horizontal, 4)
    }
    
    private var trendsRangePicker: some View {
        HStack {
            HStack(spacing: 2) {
                ForEach(TimeScope.allCases) { scope in
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            timeScope = scope
                            hoveredBucketId = nil
                        }
                    } label: {
                        Text(scope.displayName)
                            .font(.system(size: 8, weight: timeScope == scope ? .bold : .medium, design: .rounded))
                            .foregroundStyle(timeScope == scope ? Color.primary : Color.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(timeScope == scope ? theme.surfacePrimary : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(2)
            .background(Capsule().fill(theme.surfaceSecondary))
            
            Spacer()
        }
    }
    
    private func trendsInspectorView(bucket: UsageTimeBucket) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(metricType == .cost ? theme.costGreen : theme.geminiAccent)
                            .frame(width: 4, height: 4)
                        Text(bucket.label)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.9))
                    }
                    
                    HStack(spacing: 5) {
                        Text("\(bucket.queryCount) \(bucket.queryCount == 1 ? "query" : "queries")")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                        
                        Text("•")
                            .font(.system(size: 7))
                            .foregroundStyle(.secondary.opacity(0.4))
                        
                        Text("\(formatTokensCompact(bucket.inputTokens)) in / \(formatTokensCompact(bucket.outputTokens)) out")
                            .font(.system(size: 8, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 1) {
                    Text(formattedValue(value(for: bucket)))
                        .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(metricType == .cost ? theme.costGreen : theme.geminiAccent)
                    
                    if metricType != .cost {
                        Text(String(format: "$%.2f est.", bucket.totalCost))
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.costGreen)
                    }
                }
            }
            
            if !bucket.modelBreakdown.isEmpty {
                HStack(spacing: 4) {
                    ForEach(bucket.modelBreakdown.keys.sorted(), id: \.self) { mName in
                        if let mCost = bucket.modelBreakdown[mName], mCost > 0 {
                            let isGemini = mName.lowercased().contains("gemini")
                            let mColor = isGemini ? theme.geminiAccent : theme.claudeAccent
                            let shortName = mName.replacingOccurrences(of: " (current)", with: "")
                                .replacingOccurrences(of: " (Low)", with: "")
                                .replacingOccurrences(of: " (Medium)", with: "")
                                .replacingOccurrences(of: " (High)", with: "")
                                .replacingOccurrences(of: " (Thinking)", with: "")
                            
                            HStack(spacing: 2) {
                                Text(shortName)
                                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(mColor)
                                Text(String(format: "$%.2f", mCost))
                                    .font(.system(size: 7.5, weight: .medium, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(mColor.opacity(0.08)))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.surfaceSecondary.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.cardStroke, lineWidth: 0.5)
        )
    }
    
    private func trendsBarsCanvas(buckets: [UsageTimeBucket], maxVal: Double, inspected: UsageTimeBucket?) -> some View {
        GeometryReader { canvasGeo in
            let canvasWidth = canvasGeo.size.width
            let count = buckets.count
            let stepWidth = count > 0 ? canvasWidth / CGFloat(count) : 1
            
            ZStack(alignment: .bottomLeading) {
                if let bucket = inspected,
                   let idx = buckets.firstIndex(where: { $0.id == bucket.id }) {
                    let colX = CGFloat(idx) * stepWidth
                    RoundedRectangle(cornerRadius: 4)
                        .fill(theme.geminiAccent.opacity(0.08))
                        .frame(width: stepWidth, height: canvasGeo.size.height)
                        .offset(x: colX, y: 0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: bucket.id)
                }
                
                let spacing: CGFloat = timeScope == .monthly ? 14 : (timeScope == .week ? 8 : (timeScope == .twoWeeks ? 4 : 2))
                let maxBarWidth: CGFloat = timeScope == .monthly ? 34 : (timeScope == .week ? 26 : (timeScope == .twoWeeks ? 16 : .infinity))
                let cornerRadius: CGFloat = timeScope == .monthly ? 5 : (timeScope == .week ? 4 : 3)
                
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(buckets) { bucket in
                        let val = value(for: bucket)
                        let heightRatio = maxVal > 0 ? CGFloat(val / maxVal) : 0
                        let isHovered = inspected?.id == bucket.id
                        
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(theme.surfaceSecondary.opacity(isHovered ? 0.8 : 0.45))
                                .frame(maxWidth: maxBarWidth, maxHeight: .infinity)
                            
                            let barHeight = max(val > 0 ? 5.0 : 0.0, canvasGeo.size.height * heightRatio)
                            
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(
                                    LinearGradient(
                                        colors: barGradientColors(isHovered: isHovered),
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: maxBarWidth == .infinity ? nil : maxBarWidth, height: barHeight)
                                .overlay(
                                    RoundedRectangle(cornerRadius: cornerRadius)
                                        .stroke(isHovered ? Color.white.opacity(0.4) : Color.clear, lineWidth: 1)
                                )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard count > 0, canvasWidth > 0 else { return }
                            let rawIndex = Int(location.x / stepWidth)
                            let clampedIndex = max(0, min(count - 1, rawIndex))
                            let target = buckets[clampedIndex]
                            if hoveredBucketId != target.id {
                                hoveredBucketId = target.id
                            }
                        case .ended:
                            break
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard count > 0, canvasWidth > 0 else { return }
                                let rawIndex = Int(value.location.x / stepWidth)
                                let clampedIndex = max(0, min(count - 1, rawIndex))
                                let target = buckets[clampedIndex]
                                if hoveredBucketId != target.id {
                                    hoveredBucketId = target.id
                                }
                            }
                    )
            }
        }
        .frame(height: 80)
    }
    
    private func trendsXAxis(buckets: [UsageTimeBucket], inspected: UsageTimeBucket?) -> some View {
        HStack {
            if timeScope == .week {
                ForEach(buckets) { b in
                    let isHovered = inspected?.id == b.id
                    Text(b.shortLabel)
                        .font(.system(size: 8, weight: isHovered ? .bold : .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(isHovered ? theme.geminiAccent : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            } else if timeScope == .twoWeeks {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { idx, b in
                    if idx % 2 == 0 || idx == buckets.count - 1 {
                        Text(b.shortLabel)
                            .font(.system(size: 7.5, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(inspected?.id == b.id ? theme.geminiAccent : Color.secondary)
                        if idx != buckets.count - 1 {
                            Spacer()
                        }
                    }
                }
            } else if timeScope == .month {
                let count = buckets.count
                if count > 0 {
                    let indices = Array(Set([0, count / 4, count / 2, (count * 3) / 4, count - 1])).sorted()
                    ForEach(indices, id: \.self) { idx in
                        if idx < count {
                            let b = buckets[idx]
                            Text(b.shortLabel)
                                .font(.system(size: 7.5, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(inspected?.id == b.id ? theme.geminiAccent : Color.secondary)
                            if idx != indices.last {
                                Spacer()
                            }
                        }
                    }
                }
            } else {
                ForEach(buckets) { b in
                    let isHovered = inspected?.id == b.id
                    Text(b.shortLabel)
                        .font(.system(size: 8, weight: isHovered ? .bold : .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(isHovered ? theme.geminiAccent : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
    
    private func trendsSummary(buckets: [UsageTimeBucket]) -> some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.vertical, 2)
            
            HStack {
                let totalSum = buckets.reduce(0.0) { $0 + value(for: $1) }
                let avg = totalSum / Double(max(1, buckets.count))
                let peak = buckets.map { value(for: $0) }.max() ?? 0
                
                summaryItem(title: "Peak", value: formattedValue(peak))
                Spacer()
                summaryItem(title: "Avg/\(timeScope == .monthly ? "mo" : "day")", value: formattedValue(avg))
                Spacer()
                summaryItem(title: "Scope Total", value: formattedValue(totalSum))
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func barGradientColors(isHovered: Bool) -> [Color] {
        switch metricType {
        case .cost:
            return isHovered ? [theme.costGreen, theme.costGreen.opacity(0.85)] : [theme.costGreen.opacity(0.9), theme.costGreen.opacity(0.55)]
        case .queries:
            return isHovered ? [theme.geminiAccent, theme.geminiAccent.opacity(0.85)] : [theme.geminiAccent.opacity(0.9), theme.geminiAccent.opacity(0.55)]
        case .tokens:
            return isHovered ? [Color.cyan, Color.blue.opacity(0.85)] : [Color.cyan.opacity(0.85), Color.blue.opacity(0.5)]
        }
    }
    
    private func summaryItem(title: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(title + ":")
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 8.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary.opacity(0.85))
        }
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
