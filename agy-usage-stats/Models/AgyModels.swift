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
    public var cachedInputTokens: Int? = nil
}

public struct QueryEntry: Identifiable, Codable, Hashable {
    public var id: String { "\(timestamp.timeIntervalSince1970)-\(display.prefix(30))" }
    public let display: String
    public let timestamp: Date
    public let workspace: String
    public var conversationId: String?
    public let type: String?
    public var conversationMeta: ConversationDbMeta? = nil
    public var modelName: String? = nil
    public var isGcp: Bool = false
    public var gcpProject: String? = nil

    public var cleanWorkspaceName: String {
        let url = URL(fileURLWithPath: workspace)
        return url.lastPathComponent.isEmpty ? workspace : url.lastPathComponent
    }
    
    public var billingBadge: String {
        isGcp ? "GCP" : "Quota"
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

public struct UsageTimeBucket: Identifiable, Codable, Hashable, Sendable {
    public var id: String { periodKey }
    public let periodKey: String
    public let label: String
    public let shortLabel: String
    public let date: Date
    public var queryCount: Int
    public var totalCost: Double
    public var inputTokens: Int
    public var outputTokens: Int
    public var modelBreakdown: [String: Double]
    public var modelQueryBreakdown: [String: Int]
    public var gcpCost: Double
    public var quotaCost: Double
    
    public init(
        periodKey: String,
        label: String,
        shortLabel: String,
        date: Date,
        queryCount: Int = 0,
        totalCost: Double = 0.0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        modelBreakdown: [String: Double] = [:],
        modelQueryBreakdown: [String: Int] = [:],
        gcpCost: Double = 0.0,
        quotaCost: Double = 0.0
    ) {
        self.periodKey = periodKey
        self.label = label
        self.shortLabel = shortLabel
        self.date = date
        self.queryCount = queryCount
        self.totalCost = totalCost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.modelBreakdown = modelBreakdown
        self.modelQueryBreakdown = modelQueryBreakdown
        self.gcpCost = gcpCost
        self.quotaCost = quotaCost
    }
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
    public var dailyUsage: [UsageTimeBucket]
    public var monthlyUsage: [UsageTimeBucket]
    
    // Auth & GCP tracking
    public var gcpProject: String?
    public var gcpLocation: String?
    public var isGcpActive: Bool { gcpProject != nil && !(gcpProject?.isEmpty ?? true) }
    
    public var gcpTotalCost: Double
    public var gcpTodayCost: Double
    public var gcpWeeklyCost: Double
    
    public var quotaTotalCost: Double
    public var quotaTodayCost: Double
    public var quotaWeeklyCost: Double
    
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
        todayCostEstimate: 0.0,
        dailyUsage: [],
        monthlyUsage: [],
        gcpProject: nil,
        gcpLocation: nil,
        gcpTotalCost: 0.0,
        gcpTodayCost: 0.0,
        gcpWeeklyCost: 0.0,
        quotaTotalCost: 0.0,
        quotaTodayCost: 0.0,
        quotaWeeklyCost: 0.0
    )
}

public struct GcpConfig: Codable, Equatable, Hashable {
    public var project: String?
    public var location: String?
    
    public init(project: String? = nil, location: String? = nil) {
        self.project = project
        self.location = location
    }
}

public struct AgySettings: Codable, Equatable {
    public var colorScheme: String?
    public var enableTelemetry: Bool?
    public var model: String?
    public var trustedWorkspaces: [String]?
    public var gcp: GcpConfig?
    
    public static let `default` = AgySettings(
        colorScheme: "dark",
        enableTelemetry: false,
        model: "Unknown",
        trustedWorkspaces: [],
        gcp: nil
    )
}

public struct ModelCostInfo: Identifiable, Codable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let inputPricePerMillion: Double
    public let outputPricePerMillion: Double
    public let cachedInputPricePerMillion: Double
    public let tier: ModelTier
    
    public init(
        name: String,
        inputPricePerMillion: Double,
        outputPricePerMillion: Double,
        cachedInputPricePerMillion: Double? = nil,
        tier: ModelTier
    ) {
        self.name = name
        self.inputPricePerMillion = inputPricePerMillion
        self.outputPricePerMillion = outputPricePerMillion
        self.cachedInputPricePerMillion = cachedInputPricePerMillion ?? (inputPricePerMillion * 0.25)
        self.tier = tier
    }
    
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
        let trimmed = query.display.trimmingCharacters(in: .whitespacesAndNewlines)
        let offlineCommands: Set<String> = ["/help", "/clear", "/exit", "/theme", "/status", "/resume", "/settings", "/version", "/usage", "/model", "/context"]
        let commandName = trimmed.components(separatedBy: .whitespaces).first?.lowercased() ?? ""
        let isOfflineCommand = offlineCommands.contains(commandName)
        
        let hasNoMeta = (query.conversationMeta?.totalOutputBytes ?? 0) == 0 &&
            (query.conversationMeta?.inputTokens ?? 0) == 0 &&
            (query.conversationMeta?.cachedInputTokens ?? 0) == 0
        
        if isOfflineCommand && (query.conversationMeta?.llmCalls ?? 0) == 0 && hasNoMeta {
            return (0, 0, 0.0)
        }
        
        if let meta = query.conversationMeta {
            let promptTokens = meta.inputTokens ?? 0
            let cachedTokens = meta.cachedInputTokens ?? 0
            let outTokens = meta.outputTokens ?? 0
            
            if promptTokens > 0 || cachedTokens > 0 || outTokens > 0 {
                let promptCost = (Double(promptTokens) / 1_000_000.0) * inputPricePerMillion
                let cachedCost = (Double(cachedTokens) / 1_000_000.0) * cachedInputPricePerMillion
                let outputCost = (Double(outTokens) / 1_000_000.0) * outputPricePerMillion
                let totalInput = promptTokens + cachedTokens
                return (totalInput, outTokens, promptCost + cachedCost + outputCost)
            }
        }
        
        let calls = max(1, query.conversationMeta?.llmCalls ?? 1)
        let outBytes = query.conversationMeta?.totalOutputBytes ?? 0
        
        let promptLen = max(10, trimmed.count / 4)
        let contextPerCall = min(15000.0, tier.inputTokens)
        let inputTokens = promptLen + (calls - 1) * Int(contextPerCall) + Int(tier.inputTokens * 0.35)
        
        let outputTokens: Int
        if outBytes > 0 {
            outputTokens = max(80, outBytes / 4)
        } else {
            outputTokens = Int(tier.outputTokens) * calls
        }
        
        let inputCost = (Double(inputTokens) / 1_000_000.0) * inputPricePerMillion
        let outputCost = (Double(outputTokens) / 1_000_000.0) * outputPricePerMillion
        
        return (inputTokens, outputTokens, inputCost + outputCost)
    }
}

public let knownModels = [
    ModelCostInfo(name: "Gemini 3.8 Flash (Low)", inputPricePerMillion: 0.75, outputPricePerMillion: 3.75, cachedInputPricePerMillion: 0.075, tier: .low),
    ModelCostInfo(name: "Gemini 3.8 Flash (Medium)", inputPricePerMillion: 0.75, outputPricePerMillion: 3.75, cachedInputPricePerMillion: 0.075, tier: .medium),
    ModelCostInfo(name: "Gemini 3.8 Flash (High)", inputPricePerMillion: 0.75, outputPricePerMillion: 3.75, cachedInputPricePerMillion: 0.075, tier: .high),
    ModelCostInfo(name: "Gemini 3.8 Flash Cyber", inputPricePerMillion: 0.75, outputPricePerMillion: 3.75, cachedInputPricePerMillion: 0.075, tier: .high),
    ModelCostInfo(name: "Gemini 3.7 Flash (Low)", inputPricePerMillion: 0.75, outputPricePerMillion: 3.75, cachedInputPricePerMillion: 0.075, tier: .low),
    ModelCostInfo(name: "Gemini 3.7 Flash (Medium)", inputPricePerMillion: 0.75, outputPricePerMillion: 3.75, cachedInputPricePerMillion: 0.075, tier: .medium),
    ModelCostInfo(name: "Gemini 3.7 Flash (High)", inputPricePerMillion: 0.75, outputPricePerMillion: 3.75, cachedInputPricePerMillion: 0.075, tier: .high),
    ModelCostInfo(name: "Gemini 3.6 Flash (Low)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .low),
    ModelCostInfo(name: "Gemini 3.6 Flash (Medium)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .medium),
    ModelCostInfo(name: "Gemini 3.6 Flash (High)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .high),
    ModelCostInfo(name: "Gemini 3.5 Flash (Low)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, cachedInputPricePerMillion: 0.15, tier: .low),
    ModelCostInfo(name: "Gemini 3.5 Flash (Medium)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, cachedInputPricePerMillion: 0.15, tier: .medium),
    ModelCostInfo(name: "Gemini 3.5 Flash (High)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, cachedInputPricePerMillion: 0.15, tier: .high),
    ModelCostInfo(name: "Gemini 3.1 Pro (Low)", inputPricePerMillion: 2.00, outputPricePerMillion: 12.00, cachedInputPricePerMillion: 0.20, tier: .low),
    ModelCostInfo(name: "Gemini 3.1 Pro (High)", inputPricePerMillion: 2.00, outputPricePerMillion: 12.00, cachedInputPricePerMillion: 0.20, tier: .high),
    ModelCostInfo(name: "Claude Sonnet 4.6 (Thinking)", inputPricePerMillion: 3.00, outputPricePerMillion: 15.00, cachedInputPricePerMillion: 0.30, tier: .thinking),
    ModelCostInfo(name: "Claude Opus 4.6 (Thinking)", inputPricePerMillion: 5.00, outputPricePerMillion: 25.00, cachedInputPricePerMillion: 0.50, tier: .thinking),
    ModelCostInfo(name: "GPT-OSS-120B", inputPricePerMillion: 0.15, outputPricePerMillion: 0.60, cachedInputPricePerMillion: 0.015, tier: .medium)
]

public var defaultGeminiModel: ModelCostInfo {
    knownModels.first(where: { $0.name == "Gemini 3.7 Flash (High)" }) ?? knownModels[0]
}

