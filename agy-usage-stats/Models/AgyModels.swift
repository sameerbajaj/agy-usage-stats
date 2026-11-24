//
//  AgyModels.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import Foundation
import SwiftUI

nonisolated public struct ConversationDbMeta: Codable, Hashable, Sendable {
    public let llmCalls: Int
    public let totalOutputBytes: Int
    public var inputTokens: Int? = nil
    public var outputTokens: Int? = nil
    public var cachedInputTokens: Int? = nil
}

nonisolated public struct QueryEntry: Identifiable, Codable, Hashable, Sendable {
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
    public var accountEmail: String? = nil

    public init(
        display: String,
        timestamp: Date,
        workspace: String,
        conversationId: String? = nil,
        type: String? = nil,
        conversationMeta: ConversationDbMeta? = nil,
        modelName: String? = nil,
        isGcp: Bool = false,
        gcpProject: String? = nil,
        accountEmail: String? = nil
    ) {
        self.display = display
        self.timestamp = timestamp
        self.workspace = workspace
        self.conversationId = conversationId
        self.type = type
        self.conversationMeta = conversationMeta
        self.modelName = modelName
        self.isGcp = isGcp
        self.gcpProject = gcpProject
        self.accountEmail = accountEmail
    }

    public var cleanWorkspaceName: String {
        let url = URL(fileURLWithPath: workspace)
        return url.lastPathComponent.isEmpty ? workspace : url.lastPathComponent
    }
    
    public var billingBadge: String {
        isGcp ? "GCP" : "Quota"
    }
    
    public var accountDisplayName: String {
        if isGcp {
            if let proj = gcpProject, !proj.isEmpty {
                return "GCP (\(proj))"
            }
            return "Google Cloud API"
        }
        if let email = accountEmail, !email.isEmpty {
            return email
        }
        return "Account Quota"
    }
}

nonisolated public struct WorkspaceStats: Identifiable, Codable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public var name: String {
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent.isEmpty ? path : url.lastPathComponent
    }
    public var queryCount: Int
    public var lastActiveAt: Date
}

nonisolated public struct ToolStat: Identifiable, Codable, Hashable, Sendable {
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

public typealias ModelQuotaBucket = AgyQuotaBucket
public typealias ModelQuotaGroup = AgyQuotaGroup

nonisolated public struct AgyQuotaBucket: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String { bucketId }
    public let bucketId: String
    public let displayName: String
    public let remainingFraction: Double?
    public let resetDescription: String?
    public let disabled: Bool
    public let resetTime: String?
    /// Optional server/drift-verified flag: `false` when consecutive polls show `resetTime` sliding forward with wall-clock time (timer not started), `true` when anchored and counting down.
    public let isTimerStarted: Bool?

    public init(
        bucketId: String,
        displayName: String,
        remainingFraction: Double? = nil,
        resetDescription: String? = nil,
        disabled: Bool = false,
        resetTime: String? = nil,
        isTimerStarted: Bool? = nil
    ) {
        self.bucketId = bucketId
        self.displayName = displayName
        self.remainingFraction = remainingFraction
        self.resetDescription = resetDescription
        self.disabled = disabled
        self.resetTime = resetTime
        self.isTimerStarted = isTimerStarted
    }

    public var parsedResetDate: Date? {
        guard let resetTime = resetTime else { return nil }
        return AgyQuotaInfo.parseResetTime(resetTime)
    }

    public var isWeeklyBucket: Bool {
        let name = displayName.lowercased()
        let id = bucketId.lowercased()
        return name.contains("week") || id.contains("week")
    }

    public var isFiveHourBucket: Bool {
        let name = displayName.lowercased()
        let id = bucketId.lowercased()
        return name.contains("5h") || id.contains("5h") || name.contains("five") || id.contains("five")
    }

    /// Returns `true` when the bucket's reset countdown clock has not actually started yet
    /// (e.g. AGY CLI returns 100% / ~99% with a floating `now + 5h` / `now + 7d` timestamp and no active refresh description,
    /// or consecutive live polls observed `resetTime` drifting forward with wall-clock time).
    public func isWindowTimerIdle(now: Date = Date()) -> Bool {
        guard !disabled else { return false }
        if let explicit = isTimerStarted {
            return !explicit
        }

        let frac = remainingFraction ?? 1.0
        let hasActiveDescription = !(resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        if frac >= 0.999 {
            if resetTime == nil || !hasActiveDescription {
                return true
            }
            if let resetDate = parsedResetDate {
                let diff = resetDate.timeIntervalSince(now)
                if isFiveHourBucket && diff >= (5.0 * 3600.0 - 120.0) {
                    return true
                }
                if isWeeklyBucket && diff >= (7.0 * 86400.0 - 300.0) {
                    return true
                }
            }
        } else if frac >= 0.985 && !hasActiveDescription {
            guard let resetDate = parsedResetDate else { return true }
            let diff = resetDate.timeIntervalSince(now)
            if isFiveHourBucket && diff >= (5.0 * 3600.0 - 120.0) {
                return true
            }
            if isWeeklyBucket && diff >= (7.0 * 86400.0 - 300.0) {
                return true
            }
        }

        return false
    }

    public func normalizedForCurrentTime(now: Date = Date()) -> AgyQuotaBucket {
        guard let resetDate = parsedResetDate, resetDate <= now else {
            return self
        }
        if (remainingFraction ?? 0.0) < 1.0 {
            return AgyQuotaBucket(
                bucketId: bucketId,
                displayName: displayName,
                remainingFraction: 1.0,
                resetDescription: resetDescription,
                disabled: disabled,
                resetTime: nil,
                isTimerStarted: false
            )
        }
        return self
    }
}

nonisolated public struct AgyQuotaGroup: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String { displayName }
    public let displayName: String
    public let description: String?
    public let buckets: [AgyQuotaBucket]

    public init(
        displayName: String,
        description: String? = nil,
        buckets: [AgyQuotaBucket]
    ) {
        self.displayName = displayName
        self.description = description
        self.buckets = buckets
    }

    public func normalizedForCurrentTime(now: Date = Date()) -> AgyQuotaGroup {
        let updatedBuckets = buckets.map { $0.normalizedForCurrentTime(now: now) }
        return AgyQuotaGroup(
            displayName: displayName,
            description: description,
            buckets: updatedBuckets
        )
    }
    
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

nonisolated public struct AgyQuotaInfo: Codable, Equatable, Hashable, Sendable {
    public let email: String?
    public let plan: String?
    public let groups: [AgyQuotaGroup]
    public let googleOneAiCredits: Int?
    public let minimumCreditAmountForUsage: Int?
    public let lastUpdated: Date?

    public init(
        email: String? = nil,
        plan: String? = nil,
        groups: [AgyQuotaGroup],
        googleOneAiCredits: Int? = nil,
        minimumCreditAmountForUsage: Int? = nil,
        lastUpdated: Date? = nil
    ) {
        self.email = email
        self.plan = plan
        self.groups = groups
        self.googleOneAiCredits = googleOneAiCredits
        self.minimumCreditAmountForUsage = minimumCreditAmountForUsage
        self.lastUpdated = lastUpdated
    }

    private static let iso8601Formatter = ISO8601DateFormatter()
    private static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func parseResetTime(_ resetTime: String) -> Date? {
        if let date = iso8601Formatter.date(from: resetTime) {
            return date
        }
        if let date = iso8601FractionalFormatter.date(from: resetTime) {
            return date
        }
        if let epoch = Double(resetTime) {
            if epoch > 100_000_000_000 {
                return Date(timeIntervalSince1970: epoch / 1000.0)
            }
            return Date(timeIntervalSince1970: epoch)
        }
        return nil
    }

    public func normalizedForCurrentTime(now: Date = Date()) -> AgyQuotaInfo {
        let hasAnyResetTime = groups.contains { group in
            group.buckets.contains { $0.resetTime != nil }
        }
        guard hasAnyResetTime else { return self }
        let updatedGroups = groups.map { $0.normalizedForCurrentTime(now: now) }
        return AgyQuotaInfo(
            email: email,
            plan: plan,
            groups: updatedGroups,
            googleOneAiCredits: googleOneAiCredits,
            minimumCreditAmountForUsage: minimumCreditAmountForUsage,
            lastUpdated: lastUpdated
        )
    }

    public var hasUsedAnyQuota: Bool {
        groups.flatMap(\.buckets).contains { !$0.disabled && ($0.remainingFraction ?? 1.0) < 0.999 }
    }

    public var compactQuotaSummary: String {
        let nonDisabledBuckets = groups.flatMap(\.buckets).filter { !$0.disabled }
        guard !nonDisabledBuckets.isEmpty else { return "100% untouched" }
        if !hasUsedAnyQuota {
            return "100% untouched"
        }
        let parts: [String] = groups.compactMap { group in
            let fractions = group.buckets.filter { !$0.disabled }.compactMap(\.remainingFraction)
            guard let minFraction = fractions.min() else { return nil }
            let pct = Int((minFraction * 100.0).rounded())
            let lower = group.displayName.lowercased()
            let shortName: String
            if lower.contains("neon") {
                shortName = "Neon"
            } else if lower.contains("carbon") {
                shortName = "Carbon"
            } else if lower.contains("argon") {
                shortName = "Argon"
            } else if lower.contains("hydrogen") {
                shortName = "Hydrogen"
            } else if lower.contains("gemini") {
                shortName = "Gemini"
            } else if lower.contains("claude") || lower.contains("gpt") {
                shortName = "Claude"
            } else {
                shortName = group.displayName
                    .replacingOccurrences(of: " Models", with: "")
                    .replacingOccurrences(of: " MODELS", with: "")
            }
            return "\(shortName) \(pct)%"
        }
        return parts.isEmpty ? "100% untouched" : parts.joined(separator: " · ")
    }
}

nonisolated public struct UsageTimeBucket: Identifiable, Codable, Hashable, Sendable {
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
    public var accountCostBreakdown: [String: Double]
    public var accountQueryBreakdown: [String: Int]
    public var accountModelBreakdown: [String: [String: Double]] = [:]
    public var accountTokenBreakdown: [String: Int] = [:]
    public var gcpModelBreakdown: [String: Double]
    public var quotaModelBreakdown: [String: Double]
    public var gcpInputTokens: Int
    public var gcpOutputTokens: Int
    public var quotaInputTokens: Int
    public var quotaOutputTokens: Int
    public var gcpQueryCount: Int
    public var quotaQueryCount: Int
    
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
        quotaCost: Double = 0.0,
        accountCostBreakdown: [String: Double] = [:],
        accountQueryBreakdown: [String: Int] = [:],
        accountModelBreakdown: [String: [String: Double]] = [:],
        accountTokenBreakdown: [String: Int] = [:],
        gcpModelBreakdown: [String: Double] = [:],
        quotaModelBreakdown: [String: Double] = [:],
        gcpInputTokens: Int = 0,
        gcpOutputTokens: Int = 0,
        quotaInputTokens: Int = 0,
        quotaOutputTokens: Int = 0,
        gcpQueryCount: Int = 0,
        quotaQueryCount: Int = 0
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
        self.accountCostBreakdown = accountCostBreakdown
        self.accountQueryBreakdown = accountQueryBreakdown
        self.accountModelBreakdown = accountModelBreakdown
        self.accountTokenBreakdown = accountTokenBreakdown
        self.gcpModelBreakdown = gcpModelBreakdown
        self.quotaModelBreakdown = quotaModelBreakdown
        self.gcpInputTokens = gcpInputTokens
        self.gcpOutputTokens = gcpOutputTokens
        self.quotaInputTokens = quotaInputTokens
        self.quotaOutputTokens = quotaOutputTokens
        self.gcpQueryCount = gcpQueryCount
        self.quotaQueryCount = quotaQueryCount
    }
}

nonisolated public struct GcpSpendEntry: Codable, Equatable, Hashable, Sendable {
    public let timestamp: Double
    public let cost: Double
    
    public init(timestamp: Double, cost: Double) {
        self.timestamp = timestamp
        self.cost = cost
    }
}

nonisolated public struct AccountSpendEntry: Codable, Equatable, Hashable, Sendable {
    public let email: String
    public let timestamp: TimeInterval
    public let cost: Double

    public init(email: String, timestamp: TimeInterval, cost: Double) {
        self.email = email
        self.timestamp = timestamp
        self.cost = cost
    }
}

nonisolated public struct AgyUsageStats: Codable, Equatable, Sendable {
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
    public var gcpSpendEntries: [GcpSpendEntry] = []
    
    public var quotaTotalCost: Double
    public var quotaTodayCost: Double
    public var quotaWeeklyCost: Double
    
    // Multi-account tracking
    public var availableAccounts: [String]
    public var accountCostTotals: [String: Double]
    public var accountTodayTotals: [String: Double]
    public var accountWeeklyTotals: [String: Double]
    public var accountQueryTodayTotals: [String: Int] = [:]
    public var accountQueryWeeklyTotals: [String: Int] = [:]
    public var accountQueryTotals: [String: Int] = [:]
    public var consumerSpendEntries: [AccountSpendEntry] = []
    public var discoveredConsumerEmails: [String] = []
    
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
        quotaWeeklyCost: 0.0,
        availableAccounts: [],
        accountCostTotals: [:],
        accountTodayTotals: [:],
        accountWeeklyTotals: [:],
        accountQueryTodayTotals: [:],
        accountQueryWeeklyTotals: [:],
        accountQueryTotals: [:],
        consumerSpendEntries: [],
        discoveredConsumerEmails: []
    )
}

nonisolated public struct GcpConfig: Codable, Equatable, Hashable, Sendable {
    public var project: String?
    public var location: String?
    
    public init(project: String? = nil, location: String? = nil) {
        self.project = project
        self.location = location
    }
}

nonisolated public struct AgySettings: Codable, Equatable, Sendable {
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

nonisolated public struct ModelCostInfo: Identifiable, Codable, Hashable, Sendable {
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
    
    public static let gcpRegionalMultiplier: Double = 1.10

    public var costPerQuery: Double {
        let inputCost = (tier.inputTokens / 1_000_000.0) * inputPricePerMillion
        let outputCost = (tier.outputTokens / 1_000_000.0) * outputPricePerMillion
        return inputCost + outputCost
    }

    public func estimateTokensAndCost(for query: QueryEntry, regionalMultiplier: Double? = nil) -> (inputTokens: Int, outputTokens: Int, cost: Double) {
        let multiplier = regionalMultiplier ?? (query.isGcp ? Self.gcpRegionalMultiplier : 1.0)
        let trimmed = query.display.trimmingCharacters(in: .whitespacesAndNewlines)
        let offlineCommands: Set<String> = ["/help", "/clear", "/exit", "/theme", "/status", "/resume", "/settings", "/version", "/usage", "/model", "/context", "/rewind", "/auth", "/login", "/logout"]
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
                return (totalInput, outTokens, (promptCost + cachedCost + outputCost) * multiplier)
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
        
        return (inputTokens, outputTokens, (inputCost + outputCost) * multiplier)
    }
    public static let carbonStandardPriceCutoffTimestamp: TimeInterval = 1796083200 // 2026-12-01 00:00:00 UTC

    /// Base SKU pricing helper for Gemini 4 Carbon.
    /// Standard tier base rates: $4.00 input, $20.00 output, $0.20 cached input per MTok
    /// (Vertex AI 'us' GCP billing applies the 1.10x regional multiplier -> $4.40 / $22.00 / $0.22).
    public static func gemini4CarbonPricing(at date: Date = Date()) -> (input: Double, output: Double, cached: Double) {
        return (input: 4.00, output: 20.00, cached: 0.20)
    }
    public static func knownModels(at date: Date = Date()) -> [ModelCostInfo] {
        let carbonPricing = gemini4CarbonPricing(at: date)
        return [
            // Gemini 4 Neon: Google Gemini API / Vertex AI Standard tier pricing.
            // Base rates: $3.00/M input, $15.00/M output (incl. thinking), $0.15/M cached input (GCP 1.10x: $3.30 / $16.50 / $0.165).
            ModelCostInfo(name: "Gemini 4 Neon (Low)", inputPricePerMillion: 3.00, outputPricePerMillion: 15.00, cachedInputPricePerMillion: 0.15, tier: .low),
            ModelCostInfo(name: "Gemini 4 Neon (Medium)", inputPricePerMillion: 3.00, outputPricePerMillion: 15.00, cachedInputPricePerMillion: 0.15, tier: .medium),
            ModelCostInfo(name: "Gemini 4 Neon (High)", inputPricePerMillion: 3.00, outputPricePerMillion: 15.00, cachedInputPricePerMillion: 0.15, tier: .high),
            ModelCostInfo(name: "Gemini 4 Neon (XHigh)", inputPricePerMillion: 3.00, outputPricePerMillion: 15.00, cachedInputPricePerMillion: 0.15, tier: .high),
            ModelCostInfo(name: "Orchestrator (Neon)", inputPricePerMillion: 3.00, outputPricePerMillion: 15.00, cachedInputPricePerMillion: 0.15, tier: .high),

            // Gemini 4 Hydrogen: Google Gemini API Standard tier pricing.
            // Rates are per 1M tokens; cached input is implicit caching.
            ModelCostInfo(name: "Gemini 4 Hydrogen (Low)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.075, tier: .low),
            ModelCostInfo(name: "Gemini 4 Hydrogen (Medium)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.075, tier: .medium),
            ModelCostInfo(name: "Gemini 4 Hydrogen (High)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.075, tier: .high),
            ModelCostInfo(name: "Gemini 4 Hydrogen (XHigh)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.075, tier: .high),

            // Frontier / Gemini 4 Reasoning (Carbon)
            ModelCostInfo(name: "Gemini 4 Carbon (Low)", inputPricePerMillion: carbonPricing.input, outputPricePerMillion: carbonPricing.output, cachedInputPricePerMillion: carbonPricing.cached, tier: .low),
            ModelCostInfo(name: "Gemini 4 Carbon (Medium)", inputPricePerMillion: carbonPricing.input, outputPricePerMillion: carbonPricing.output, cachedInputPricePerMillion: carbonPricing.cached, tier: .medium),
            ModelCostInfo(name: "Gemini 4 Carbon (High)", inputPricePerMillion: carbonPricing.input, outputPricePerMillion: carbonPricing.output, cachedInputPricePerMillion: carbonPricing.cached, tier: .high),

            // Frontier / Gemini 4 (Argon)
            ModelCostInfo(name: "Gemini 4 Argon (Low)", inputPricePerMillion: 4.00, outputPricePerMillion: 20.00, cachedInputPricePerMillion: 0.20, tier: .low),
            ModelCostInfo(name: "Gemini 4 Argon (Medium)", inputPricePerMillion: 4.00, outputPricePerMillion: 20.00, cachedInputPricePerMillion: 0.20, tier: .medium),
            ModelCostInfo(name: "Gemini 4 Argon (High)", inputPricePerMillion: 4.00, outputPricePerMillion: 20.00, cachedInputPricePerMillion: 0.20, tier: .high),
            ModelCostInfo(name: "Orchestrator (Argon)", inputPricePerMillion: 4.00, outputPricePerMillion: 20.00, cachedInputPricePerMillion: 0.20, tier: .high),

            // Claude 5.5 Series
            ModelCostInfo(name: "Claude Sonnet 5.5 (Low)", inputPricePerMillion: 2.00, outputPricePerMillion: 10.00, cachedInputPricePerMillion: 0.20, tier: .low),
            ModelCostInfo(name: "Claude Sonnet 5.5 (Medium)", inputPricePerMillion: 2.00, outputPricePerMillion: 10.00, cachedInputPricePerMillion: 0.20, tier: .medium),
            ModelCostInfo(name: "Claude Sonnet 5.5 (High)", inputPricePerMillion: 2.00, outputPricePerMillion: 10.00, cachedInputPricePerMillion: 0.20, tier: .high),
            ModelCostInfo(name: "Claude Opus 5.5 (Low)", inputPricePerMillion: 4.00, outputPricePerMillion: 20.00, cachedInputPricePerMillion: 0.20, tier: .low),
            ModelCostInfo(name: "Claude Opus 5.5 (Medium)", inputPricePerMillion: 4.00, outputPricePerMillion: 20.00, cachedInputPricePerMillion: 0.20, tier: .medium),
            ModelCostInfo(name: "Claude Opus 5.5 (High)", inputPricePerMillion: 4.00, outputPricePerMillion: 20.00, cachedInputPricePerMillion: 0.20, tier: .high),

            // Gemini 3.8 Series
            ModelCostInfo(name: "Gemini 3.8 Flash (Low)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .low),
            ModelCostInfo(name: "Gemini 3.8 Flash (Medium)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .medium),
            ModelCostInfo(name: "Gemini 3.8 Flash (High)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .high),
            ModelCostInfo(name: "Gemini 3.8 Flash Cyber", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .high),

            // Gemini 3.7 Series
            ModelCostInfo(name: "Gemini 3.7 Flash (Low)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .low),
            ModelCostInfo(name: "Gemini 3.7 Flash (Medium)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .medium),
            ModelCostInfo(name: "Gemini 3.7 Flash (High)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .high),

            // Gemini 3.6 Series
            ModelCostInfo(name: "Gemini 3.6 Flash (Low)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .low),
            ModelCostInfo(name: "Gemini 3.6 Flash (Medium)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .medium),
            ModelCostInfo(name: "Gemini 3.6 Flash (High)", inputPricePerMillion: 1.50, outputPricePerMillion: 7.50, cachedInputPricePerMillion: 0.15, tier: .high),

            // Gemini 3.5 & 3.1 Series
            ModelCostInfo(name: "Gemini 3.5 Flash Lite", inputPricePerMillion: 0.30, outputPricePerMillion: 2.50, cachedInputPricePerMillion: 0.03, tier: .low),
            ModelCostInfo(name: "Gemini 3.5 Flash (Low)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, cachedInputPricePerMillion: 0.15, tier: .low),
            ModelCostInfo(name: "Gemini 3.5 Flash (Medium)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, cachedInputPricePerMillion: 0.15, tier: .medium),
            ModelCostInfo(name: "Gemini 3.5 Flash (High)", inputPricePerMillion: 1.50, outputPricePerMillion: 9.00, cachedInputPricePerMillion: 0.15, tier: .high),
            ModelCostInfo(name: "Gemini 3.1 Pro (Low)", inputPricePerMillion: 2.00, outputPricePerMillion: 12.00, cachedInputPricePerMillion: 0.20, tier: .low),
            ModelCostInfo(name: "Gemini 3.1 Pro (High)", inputPricePerMillion: 2.00, outputPricePerMillion: 12.00, cachedInputPricePerMillion: 0.20, tier: .high),

            // Legacy Claude 4.6 (Historical)
            ModelCostInfo(name: "Claude Sonnet 4.6 (Thinking)", inputPricePerMillion: 3.00, outputPricePerMillion: 15.00, cachedInputPricePerMillion: 0.30, tier: .thinking),
            ModelCostInfo(name: "Claude Opus 4.6 (Thinking)", inputPricePerMillion: 5.00, outputPricePerMillion: 25.00, cachedInputPricePerMillion: 0.50, tier: .thinking),

            // Open Source
            ModelCostInfo(name: "GPT-OSS 120B (Medium)", inputPricePerMillion: 0.15, outputPricePerMillion: 0.60, cachedInputPricePerMillion: 0.015, tier: .medium),
            ModelCostInfo(name: "GPT-OSS-120B", inputPricePerMillion: 0.15, outputPricePerMillion: 0.60, cachedInputPricePerMillion: 0.015, tier: .medium)
        ]
    }
}

/// Global convenience accessor for date-aware Gemini 4 Carbon pricing
nonisolated public func gemini4CarbonPricing(at date: Date = Date()) -> (input: Double, output: Double, cached: Double) {
    ModelCostInfo.gemini4CarbonPricing(at: date)
}

nonisolated public var knownModels: [ModelCostInfo] {
    ModelCostInfo.knownModels(at: Date())
}

nonisolated public func knownModels(at date: Date) -> [ModelCostInfo] {
    ModelCostInfo.knownModels(at: date)
}

nonisolated public var defaultGeminiModel: ModelCostInfo {
    knownModels.first(where: { $0.name == "Gemini 3.8 Flash (High)" }) ??
    knownModels.first(where: { $0.name == "Gemini 3.7 Flash (High)" }) ??
    knownModels[0]
}

// MARK: - Canonical Model Consolidation & Aggregation

nonisolated public func canonicalModelDisplayName(from rawName: String) -> String {
    var name = rawName
    for suffix in [" (XHigh)", " (Low)", " (Medium)", " (High)", " (Thinking)", " (current)"] {
        name = name.replacingOccurrences(of: suffix, with: "")
    }
    let lower = name.lowercased()
    if lower.contains("neon") {
        return "Gemini 4 Neon"
    } else if lower.contains("hydrogen") {
        return "Gemini 4 Hydrogen"
    } else if lower.contains("carbon") {
        return "Gemini 4 Carbon"
    } else if lower.contains("argon") {
        return "Gemini 4 Argon"
    } else if lower.contains("sonnet 5.5") {
        return "Claude Sonnet 5.5"
    } else if lower.contains("opus 5.5") {
        return "Claude Opus 5.5"
    } else if lower.contains("3.8 flash") || lower.contains("flash 3.8") {
        return "Gemini 3.8 Flash"
    } else if lower.contains("3.7 flash") || lower.contains("flash 3.7") {
        return "Gemini 3.7 Flash"
    } else if lower.contains("3.6 flash") || lower.contains("flash 3.6") {
        return "Gemini 3.6 Flash"
    } else if lower.contains("3.5 flash lite") || lower.contains("flash-lite") || lower.contains("flash lite") {
        return "Gemini 3.5 Flash Lite"
    } else if lower.contains("3.5 flash") || lower.contains("flash 3.5") {
        return "Gemini 3.5 Flash"
    }
    return name
}

nonisolated public extension UsageTimeBucket {
    /// Returns model breakdown grouped and summed by canonical model name
    var consolidatedModelBreakdown: [String: Double] {
        var result: [String: Double] = [:]
        for (rawModel, cost) in modelBreakdown where cost > 0 {
            let canonical = canonicalModelDisplayName(from: rawModel)
            result[canonical, default: 0.0] += cost
        }
        return result
    }
    
    var consolidatedGcpModelBreakdown: [String: Double] {
        var result: [String: Double] = [:]
        for (rawModel, cost) in gcpModelBreakdown where cost > 0 {
            let canonical = canonicalModelDisplayName(from: rawModel)
            result[canonical, default: 0.0] += cost
        }
        return result
    }
    
    var consolidatedQuotaModelBreakdown: [String: Double] {
        var result: [String: Double] = [:]
        for (rawModel, cost) in quotaModelBreakdown where cost > 0 {
            let canonical = canonicalModelDisplayName(from: rawModel)
            result[canonical, default: 0.0] += cost
        }
        return result
    }
}

nonisolated public extension Sequence where Element == UsageTimeBucket {
    var aggregatedModelBreakdown: [String: Double] {
        var result: [String: Double] = [:]
        for bucket in self {
            for (model, cost) in bucket.consolidatedModelBreakdown {
                result[model, default: 0.0] += cost
            }
        }
        return result
    }
    
    var aggregatedGcpModelBreakdown: [String: Double] {
        var result: [String: Double] = [:]
        for bucket in self {
            for (model, cost) in bucket.consolidatedGcpModelBreakdown {
                result[model, default: 0.0] += cost
            }
        }
        return result
    }
    
    var aggregatedQuotaModelBreakdown: [String: Double] {
        var result: [String: Double] = [:]
        for bucket in self {
            for (model, cost) in bucket.consolidatedQuotaModelBreakdown {
                result[model, default: 0.0] += cost
            }
        }
        return result
    }
    
    var aggregatedTotalCost: Double {
        reduce(0.0) { $0 + $1.totalCost }
    }
    
    var aggregatedGcpCost: Double {
        reduce(0.0) { $0 + $1.gcpCost }
    }
    
    var aggregatedQuotaCost: Double {
        reduce(0.0) { $0 + $1.quotaCost }
    }
    
    var aggregatedInputTokens: Int {
        reduce(0) { $0 + $1.inputTokens }
    }
    
    var aggregatedOutputTokens: Int {
        reduce(0) { $0 + $1.outputTokens }
    }
    
    var aggregatedGcpTokens: Int {
        reduce(0) { $0 + ($1.gcpInputTokens + $1.gcpOutputTokens) }
    }
    
    var aggregatedQuotaTokens: Int {
        reduce(0) { $0 + ($1.quotaInputTokens + $1.quotaOutputTokens) }
    }
    
    var aggregatedQueryCount: Int {
        reduce(0) { $0 + $1.queryCount }
    }
    
    var aggregatedGcpQueryCount: Int {
        reduce(0) { $0 + $1.gcpQueryCount }
    }
    
    var aggregatedQuotaQueryCount: Int {
        reduce(0) { $0 + $1.quotaQueryCount }
    }
}

public enum AccountFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case subscription = "Sub"
    case gcp = "GCP"
    
    public var id: String { rawValue }
}

public enum MenuBarAccountTarget: String, Codable, CaseIterable, Identifiable {
    case subscription = "Subscription Quota"
    case gcp = "GCP Cloud Credit"
    case auto = "Dynamic (Active Session)"
    
    public var id: String { rawValue }
}

// MARK: - Muse (muse.ai) Quota Models

nonisolated public enum MuseFetchStatus: Equatable, Sendable {
    case idle
    case loading
    case connected
    case missingSession(String)
    case sessionExpired(String)
    case error(String)
}

nonisolated public struct MuseQuotaInfo: Codable, Equatable, Hashable, Sendable {
    public let planName: String
    public let subscriptionType: String
    public let percentUsed: Double
    public let resetsAt: Date?
    public let statusSubtitle: String?
    public let usageRowLabel: String?
    public let usageRowValueLabel: String?
    public let quotaStatus: String?
    public let topupRowLabel: String?
    public let topupRowValueLabel: String?
    public let topupBalance: Double?
    public let topupTotal: Double?
    public let renewsAt: Date?
    public let lastUpdated: Date

    public init(
        planName: String,
        subscriptionType: String,
        percentUsed: Double,
        resetsAt: Date? = nil,
        statusSubtitle: String? = nil,
        usageRowLabel: String? = nil,
        usageRowValueLabel: String? = nil,
        quotaStatus: String? = nil,
        topupRowLabel: String? = nil,
        topupRowValueLabel: String? = nil,
        topupBalance: Double? = nil,
        topupTotal: Double? = nil,
        renewsAt: Date? = nil,
        lastUpdated: Date = Date()
    ) {
        self.planName = planName
        self.subscriptionType = subscriptionType
        self.percentUsed = min(100.0, max(0.0, percentUsed))
        self.resetsAt = resetsAt
        self.statusSubtitle = statusSubtitle
        self.usageRowLabel = usageRowLabel
        self.usageRowValueLabel = usageRowValueLabel
        self.quotaStatus = quotaStatus
        self.topupRowLabel = topupRowLabel
        self.topupRowValueLabel = topupRowValueLabel
        self.topupBalance = topupBalance
        self.topupTotal = topupTotal
        self.renewsAt = renewsAt
        self.lastUpdated = lastUpdated
    }

    public var remainingFraction: Double {
        max(0.0, min(1.0, (100.0 - percentUsed) / 100.0))
    }

    public var remainingPercent: Double {
        remainingFraction * 100.0
    }

    public var shortPlanBadge: String {
        let lower = "\(subscriptionType) \(planName)".lowercased()
        if lower.contains("maximum") || lower.contains("max") { return "MAX" }
        if lower.contains("power") { return "POWER" }
        if lower.contains("free") { return "FREE" }
        return subscriptionType.uppercased()
    }

    public var topupRemainingFraction: Double? {
        guard let balance = topupBalance, let total = topupTotal, total > 0 else { return nil }
        return max(0.0, min(1.0, balance / total))
    }

    public var topupTokensLeftText: String? {
        if let extracted = Self.extractTokensLeft(from: topupRowValueLabel) {
            return extracted
        }
        if let label = topupRowValueLabel, !label.isEmpty {
            return label
        }
        if let balance = topupBalance, balance > 0 {
            return String(format: "$%.2f left", balance / 1_000_000.0)
        }
        return nil
    }

    public var weeklyTokensLeftText: String? {
        Self.extractTokensLeft(from: usageRowValueLabel)
    }

    public func compactCountdown(now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let diff = resetsAt.timeIntervalSince(now)
        guard diff > 0 else { return "Resetting…" }
        let totalMinutes = Int(diff) / 60
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(1, minutes))m"
        }
    }

    public func ultraCompactCountdown(now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let diff = resetsAt.timeIntervalSince(now)
        guard diff > 0 else { return "now" }
        let totalMinutes = Int(diff) / 60
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        if days > 0 {
            return "\(days)d"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(max(1, totalMinutes))m"
        }
    }

    public func normalizedForCurrentTime(now: Date = Date()) -> MuseQuotaInfo {
        guard let resetsAt, resetsAt <= now, percentUsed > 0 else {
            return self
        }
        return MuseQuotaInfo(
            planName: planName,
            subscriptionType: subscriptionType,
            percentUsed: 0.0,
            resetsAt: nil,
            statusSubtitle: "Weekly limit reset",
            usageRowLabel: usageRowLabel,
            usageRowValueLabel: "0% used",
            quotaStatus: quotaStatus,
            topupRowLabel: topupRowLabel,
            topupRowValueLabel: topupRowValueLabel,
            topupBalance: topupBalance,
            topupTotal: topupTotal,
            renewsAt: renewsAt,
            lastUpdated: lastUpdated
        )
    }

    private static func extractTokensLeft(from label: String?) -> String? {
        guard let label,
              let regex = try? NSRegularExpression(pattern: #"\(([^()]+ tokens left)\)"#) else {
            return nil
        }
        let ns = label as NSString
        guard let match = regex.firstMatch(in: label, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }
}


