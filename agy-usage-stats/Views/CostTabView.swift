//
//  CostTabView.swift
//  agy-usage-stats
//

import SwiftUI


struct CostTabView: View {
    let viewModel: AgyStatsViewModel
    
    @State private var hoveredModelId: String? = nil
    @State private var localSelectedModelId: String? = nil
    @State private var showPricingTemplates = false
    
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
                
                // Collapsible Pricing Templates
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                // Today's Query Logs Section
                Text("today's query logs")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                
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
                    .premiumCardStyle()
                } else {
                    VStack(spacing: 4) {
                        ForEach(todayQueries) { query in
                            let modelInfo = getModelCostInfo(for: query)
                            let (inTokens, outTokens, cost) = modelInfo.estimateTokensAndCost(for: query)
                            let calls = query.conversationMeta?.llmCalls ?? 1
                            
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
                                        .foregroundStyle(.green)
                                }
                                
                                HStack(spacing: 4) {
                                    Text(modelInfo.name.replacingOccurrences(of: " (current)", with: "").replacingOccurrences(of: " (Low)", with: "").replacingOccurrences(of: " (Medium)", with: "").replacingOccurrences(of: " (High)", with: "").replacingOccurrences(of: " (Thinking)", with: ""))
                                        .font(.system(size: 8, weight: .bold, design: .rounded))
                                        .foregroundStyle(.orange.opacity(0.85))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.orange.opacity(0.06)))
                                    
                                    Text("\(inTokens) in / \(outTokens) out")
                                        .font(.system(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    
                                    if calls > 1 {
                                        Text("\(calls) turns")
                                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.blue.opacity(0.8))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Color.blue.opacity(0.06)))
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
                                    .fill(Color.primary.opacity(0.015))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.03), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(8)
                    .premiumCardStyle()
                }
            }
            .padding(12)
        }
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
            .premiumCardStyle()
        }
    }
    
    private var metricDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
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
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
