//
//  CostTabView.swift
//  agy-usage-stats
//

import SwiftUI

struct ModelCostInfo: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let inputPricePerMillion: Double
    let outputPricePerMillion: Double
    let tier: ModelTier
    
    enum ModelTier {
        case low, medium, high, thinking
        
        var name: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .thinking: return "Thinking"
            }
        }
        
        var inputTokens: Double {
            switch self {
            case .low: return 15_000
            case .medium: return 45_000
            case .high: return 120_000
            case .thinking: return 80_000
            }
        }
        
        var outputTokens: Double {
            switch self {
            case .low: return 1_500
            case .medium: return 3_000
            case .high: return 6_000
            case .thinking: return 12_000
            }
        }
    }
    
    var costPerQuery: Double {
        let inputCost = (tier.inputTokens / 1_000_000.0) * inputPricePerMillion
        let outputCost = (tier.outputTokens / 1_000_000.0) * outputPricePerMillion
        return inputCost + outputCost
    }
}

struct CostTabView: View {
    let viewModel: AgyStatsViewModel
    
    @State private var hoveredModelId: String? = nil
    @State private var localSelectedModelId: String? = nil
    
    let knownModels = [
        ModelCostInfo(name: "Gemini 3.5 Flash (Low)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, tier: .low),
        ModelCostInfo(name: "Gemini 3.5 Flash (Medium)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, tier: .medium),
        ModelCostInfo(name: "Gemini 3.5 Flash (High)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, tier: .high),
        ModelCostInfo(name: "Gemini 3.1 Pro (Low)", inputPricePerMillion: 2.00, outputPricePerMillion: 12.00, tier: .low),
        ModelCostInfo(name: "Gemini 3.1 Pro (High)", inputPricePerMillion: 2.00, outputPricePerMillion: 12.00, tier: .high),
        ModelCostInfo(name: "Claude Sonnet 4.6 (Thinking)", inputPricePerMillion: 3.00, outputPricePerMillion: 15.00, tier: .thinking),
        ModelCostInfo(name: "Claude Opus 4.6 (Thinking)", inputPricePerMillion: 5.00, outputPricePerMillion: 25.00, tier: .thinking)
    ]
    
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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Estimated API Cost Strip
                costSummaryCard
                
                // Header Label
                Text("pricing templates")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                
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
                    Text(selectedModel.name.lowercased())
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            
            HStack(spacing: 0) {
                costColumn(title: "today", queries: viewModel.stats.queriesToday)
                metricDivider
                costColumn(title: "week", queries: viewModel.stats.queriesThisWeek)
                metricDivider
                costColumn(title: "total", queries: viewModel.stats.totalQueries)
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
    
    private func costColumn(title: String, queries: Int) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            
            Text(String(format: "$%.2f", Double(queries) * selectedModel.costPerQuery))
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}
