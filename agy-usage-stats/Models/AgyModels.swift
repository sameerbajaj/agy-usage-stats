//
//  AgyModels.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import Foundation
import SwiftUI

public struct QueryEntry: Identifiable, Codable, Hashable {
    public var id: String { "\(timestamp.timeIntervalSince1970)-\(display.prefix(30))" }
    public let display: String
    public let timestamp: Date
    public let workspace: String
    public let conversationId: String?
    public let type: String?

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
        quotaInfo: nil
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
