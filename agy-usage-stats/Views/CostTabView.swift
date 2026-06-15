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
        
        // Assumed average tokens per query in agy
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
        
        // Find best match in our list
        if let matched = knownModels.first(where: { cleanedActive.contains($0.name.replacingOccurrences(of: " (current)", with: "").lowercased()) || $0.name.lowercased().contains(cleanedActive) }) {
            return matched
        }
        
        // Default fallback (usually High)
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
                // Section 1: Summary Banner
                costSummaryCard
                
                // Section 2: Model Pricing Table
                Text("Select Model to Estimate Cost")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                
                VStack(spacing: 8) {
                    ForEach(knownModels) { model in
                        let isActive = model.id == activeModel.id
                        let isSelected = model.id == selectedModel.id
                        let isHovered = hoveredModelId == model.id
                        
                        Button {
                            localSelectedModelId = model.id
                        } label: {
                            HStack(spacing: 10) {
                                // Selection indicator / bullet
                                Circle()
                                    .fill(isSelected ? Color.green : Color.white.opacity(0.15))
                                    .frame(width: 6, height: 6)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(model.name)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.8))
                                        
                                        if isActive {
                                            Text("Active")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.green)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1.5)
                                                .background(Capsule().fill(Color.green.opacity(0.15)))
                                        }
                                    }
                                    
                                    Text(String(format: "Assumes %dK in / %dK out • $%.3f/q", Int(model.tier.inputTokens/1000), Int(model.tier.outputTokens/1000), model.costPerQuery))
                                        .font(.system(size: 8.5))
                                        .foregroundStyle(Color.white.opacity(0.45))
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(String(format: "In: $%.2f/M", model.inputPricePerMillion))
                                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                                        .foregroundStyle(Color.white.opacity(0.55))
                                    Text(String(format: "Out: $%.2f/M", model.outputPricePerMillion))
                                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                                        .foregroundStyle(Color.white.opacity(0.55))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(
                                        isSelected 
                                        ? Color.green.opacity(0.06) 
                                        : (isHovered ? Color.white.opacity(0.04) : Color.white.opacity(0.015))
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isSelected 
                                        ? Color.green.opacity(0.35) 
                                        : (isHovered ? Color.white.opacity(0.12) : Color.white.opacity(0.05)),
                                        lineWidth: 1
                                    )
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
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ESTIMATED API COST")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.45))
                    
                    Text(selectedModel.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                Image(systemName: "banknote.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
                    .shadow(color: Color.green.opacity(0.4), radius: 3)
            }
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            HStack(spacing: 8) {
                costColumn(title: "Today", queries: viewModel.stats.queriesToday)
                dividerLine
                costColumn(title: "Week", queries: viewModel.stats.queriesThisWeek)
                dividerLine
                costColumn(title: "Total", queries: viewModel.stats.totalQueries)
            }
        }
        .padding(12)
        .premiumCardStyle(isHovered: false, accentColor: .green)
    }
    
    private var dividerLine: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 2)
    }
    
    private func costColumn(title: String, queries: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.4))
            
            Text(String(format: "$%.2f", Double(queries) * selectedModel.costPerQuery))
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            
            Text("\(queries) queries")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
