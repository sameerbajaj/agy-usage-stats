//
//  AgyModels.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import Foundation
import SwiftUI

public struct ConversationDbMeta: Codable, Hashable, Sendable {
    public let llmCalls: Int
    public let totalOutputBytes: Int
    public var inputTokens: Int? = nil
    public var outputTokens: Int? = nil
}

public struct QueryEntry: Identifiable, Codable, Hashable {
    public var id: String { "\(timestamp.timeIntervalSince1970)-\(display.prefix(30))" }
    public let display: String
    public let timestamp: Date
    public let workspace: String
    public let conversationId: String?
    public let type: String?
    public var conversationMeta: ConversationDbMeta? = nil
    public var modelName: String? = nil

    public var cleanWorkspaceName: String {
        let url = URL(fileURLWithPath: workspace)
        return url.lastPathComponent.isEmpty ? workspace : url.lastPathComponent
    }
}

public struct WorkspaceStats: Identifiable, Codable, Hashable {
    public var id: String { path }
    public let path: String
    public var name: String {
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent.isEmpty ? path : url.lastPathComponent
    }
    public var queryCount: Int
    public var lastActiveAt: Date
}

public struct ToolStat: Identifiable, Codable, Hashable {
    public var id: String { toolName }
    public let toolName: String
    public var count: Int
    
    public var displayName: String {
        switch toolName {
        case "run_command": return "Terminal Command"
        case "replace_file_content", "multi_replace_file_content": return "Modify File"
        case "write_to_file": return "Create File"
        case "view_file": return "View File"
        case "list_dir": return "List Directory"
        case "grep_search": return "Text Search (Grep)"
        case "search_web": return "Web Search"
        case "read_url_content", "read_browser_page": return "Fetch URL"
        case "invoke_subagent", "define_subagent": return "Spawn Agent"
        case "send_message": return "Agent Message"
        case "ask_question": return "Ask Question"
        case "ask_permission": return "Ask Permission"
        case "manage_task", "schedule": return "Task / Timer"
        default: return toolName.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    
    public var iconName: String {
        switch toolName {
        case "run_command": return "terminal.fill"
        case "replace_file_content", "multi_replace_file_content", "write_to_file": return "doc.text.fill"
        case "view_file": return "eye.fill"
        case "list_dir": return "folder.fill"
        case "grep_search": return "magnifyingglass"
        case "search_web": return "globe"
        case "read_url_content", "read_browser_page": return "safari.fill"
        case "invoke_subagent", "define_subagent": return "cpu.fill"
        case "send_message": return "bubble.left.and.bubble.right.fill"
        case "ask_question": return "questionmark.bubble.fill"
        case "ask_permission": return "exclamationmark.lock.fill"
        case "manage_task", "schedule": return "clock.fill"
        default: return "wrench.and.screwdriver.fill"
        }
    }
    
    public var categoryColor: Color {
        switch toolName {
        case "run_command": return .blue
        case "replace_file_content", "multi_replace_file_content", "write_to_file": return .green
        case "view_file", "list_dir", "grep_search": return .cyan
        case "search_web", "read_url_content", "read_browser_page": return .orange
        case "invoke_subagent", "define_subagent", "send_message": return .purple
        case "ask_question", "ask_permission": return .yellow
        case "manage_task", "schedule": return .pink
        default: return .gray
        }
    }
}

public struct AgyQuotaBucket: Identifiable, Codable, Hashable, Sendable {
    public var id: String { bucketId }
    public let bucketId: String
    public let displayName: String
    public let remainingFraction: Double?
    public let resetDescription: String?
    public let disabled: Bool
    public let resetTime: String?
}

public struct AgyQuotaGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: String { displayName }
    public let displayName: String
    public let description: String?
    public let buckets: [AgyQuotaBucket]
    
    public var sortedBuckets: [AgyQuotaBucket] {
        buckets.sorted { a, b in
            let aName = a.displayName.lowercased()
            let aId = a.bucketId.lowercased()
            let bName = b.displayName.lowercased()
            let bId = b.bucketId.lowercased()
            
            let aIsWeekly = aName.contains("week") || aId.contains("week")
            let bIsWeekly = bName.contains("week") || bId.contains("week")
            let aIsFiveHour = aName.contains("5h") || aId.contains("5h") || aName.contains("five") || aId.contains("five")
            let bIsFiveHour = bName.contains("5h") || bId.contains("5h") || bName.contains("five") || bId.contains("five")
            
            let aWeight: Int
            if aIsFiveHour {
                aWeight = 0
            } else if aIsWeekly {
                aWeight = 2
            } else {
                aWeight = 1
            }
            
            let bWeight: Int
            if bIsFiveHour {
                bWeight = 0
            } else if bIsWeekly {
                bWeight = 2
            } else {
                bWeight = 1
            }
            
            if aWeight != bWeight {
                return aWeight < bWeight
            }
            
            return a.displayName < b.displayName
        }
    }
}

public struct AgyQuotaInfo: Codable, Hashable, Sendable {
    public let email: String?
    public let plan: String?
    public let groups: [AgyQuotaGroup]
}

public struct AgyUsageStats: Codable {
    public var totalQueries: Int
    public var queriesToday: Int
    public var queriesThisWeek: Int
    public var lastQueryAt: Date?
    public var workspaces: [WorkspaceStats]
    public var modelDistribution: [String: Int]
    public var recentQueries: [QueryEntry]
    public var toolStats: [ToolStat]
    public var totalToolCalls: Int
    public var quotaInfo: AgyQuotaInfo?
    public var totalCostEstimate: Double
    public var weeklyCostEstimate: Double
    public var todayCostEstimate: Double
    
    public static let empty = AgyUsageStats(
        totalQueries: 0,
        queriesToday: 0,
        queriesThisWeek: 0,
        lastQueryAt: nil,
        workspaces: [],
        modelDistribution: [:],
        recentQueries: [],
        toolStats: [],
        totalToolCalls: 0,
        quotaInfo: nil,
        totalCostEstimate: 0.0,
        weeklyCostEstimate: 0.0,
        todayCostEstimate: 0.0
    )
}

public struct AgySettings: Codable {
    public var colorScheme: String?
    public var enableTelemetry: Bool?
    public var model: String?
    public var trustedWorkspaces: [String]?
    
    public static let `default` = AgySettings(
        colorScheme: "dark",
        enableTelemetry: false,
        model: "Unknown",
        trustedWorkspaces: []
    )
}

public struct ModelCostInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let inputPricePerMillion: Double
    public let outputPricePerMillion: Double
    public let tier: ModelTier
    
    public enum ModelTier: String, Codable, Sendable {
        case low, medium, high, thinking
        
        public var name: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .thinking: return "Thinking"
            }
        }
        
        public var inputTokens: Double {
            switch self {
            case .low: return 15_000
            case .medium: return 45_000
            case .high: return 120_000
            case .thinking: return 80_000
            }
        }
        
        public var outputTokens: Double {
            switch self {
            case .low: return 1_500
            case .medium: return 3_000
            case .high: return 6_000
            case .thinking: return 12_000
            }
        }
    }
    
    public var costPerQuery: Double {
        let inputCost = (tier.inputTokens / 1_000_000.0) * inputPricePerMillion
        let outputCost = (tier.outputTokens / 1_000_000.0) * outputPricePerMillion
        return inputCost + outputCost
    }

    public func estimateTokensAndCost(for query: QueryEntry) -> (inputTokens: Int, outputTokens: Int, cost: Double) {
        if let meta = query.conversationMeta {
            if meta.llmCalls == 0 {
                return (0, 0, 0.0)
            }
            if let inTokens = meta.inputTokens, inTokens > 0,
               let outTokens = meta.outputTokens, outTokens > 0 {
                let inputCost = (Double(inTokens) / 1_000_000.0) * inputPricePerMillion
                let outputCost = (Double(outTokens) / 1_000_000.0) * outputPricePerMillion
                return (inTokens, outTokens, inputCost + outputCost)
            }
        }
        
        let calls = max(1, query.conversationMeta?.llmCalls ?? 1)
        let outBytes = query.conversationMeta?.totalOutputBytes ?? 0
        
        let promptLen = query.display.count / 4
        let contextPerCall = min(12000.0, tier.inputTokens)
        let inputTokens = promptLen + (calls - 1) * Int(contextPerCall) + 5000
        
        let outputTokens: Int
        if outBytes > 0 {
            outputTokens = max(50, outBytes / 4)
        } else {
            outputTokens = Int(tier.outputTokens) * calls
        }
        
        let inputCost = (Double(inputTokens) / 1_000_000.0) * inputPricePerMillion
        let outputCost = (Double(outputTokens) / 1_000_000.0) * outputPricePerMillion
        
        return (inputTokens, outputTokens, inputCost + outputCost)
    }
}

public let knownModels = [
    ModelCostInfo(name: "Gemini 3.5 Flash (Low)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, tier: .low),
    ModelCostInfo(name: "Gemini 3.5 Flash (Medium)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, tier: .medium),
    ModelCostInfo(name: "Gemini 3.5 Flash (High)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, tier: .high),
    ModelCostInfo(name: "Gemini 3.1 Pro (Low)", inputPricePerMillion: 2.00, outputPricePerMillion: 12.00, tier: .low),
    ModelCostInfo(name: "Gemini 3.1 Pro (High)", inputPricePerMillion: 2.00, outputPricePerMillion: 12.00, tier: .high),
    ModelCostInfo(name: "Claude Sonnet 4.6 (Thinking)", inputPricePerMillion: 3.00, outputPricePerMillion: 15.00, tier: .thinking),
    ModelCostInfo(name: "Claude Opus 4.6 (Thinking)", inputPricePerMillion: 5.00, outputPricePerMillion: 25.00, tier: .thinking)
]
