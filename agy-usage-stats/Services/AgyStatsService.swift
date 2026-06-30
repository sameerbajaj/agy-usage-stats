//
//  AgyStatsService.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import Foundation
import SQLite3

public enum AgyStatsService {
    
    private struct HistoryLine: Decodable {
        let display: String
        let timestamp: Int64
        let workspace: String
        let conversationId: String?
        let type: String?
    }
    
    public static func getDefaultCliDir() -> String {
        return "\(NSHomeDirectory())/.gemini/antigravity-cli"
    }
    
    public static func loadStats(cliDir: String) async -> (AgyUsageStats, AgySettings) {
        return await Task.detached(priority: .userInitiated) {
            let expandedDir = cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
            let historyPath = (expandedDir as NSString).appendingPathComponent("history.jsonl")
            let settingsPath = (expandedDir as NSString).appendingPathComponent("settings.json")
            let conversationsDir = (expandedDir as NSString).appendingPathComponent("conversations")
            
            print("AgyStatsService: --- Loading Stats ---")
            print("AgyStatsService: cliDir = \(cliDir)")
            print("AgyStatsService: NSHomeDirectory = \(NSHomeDirectory())")
            print("AgyStatsService: expandedDir = \(expandedDir)")
            print("AgyStatsService: historyPath = \(historyPath)")
            print("AgyStatsService: settingsPath = \(settingsPath)")
            print("AgyStatsService: conversationsDir = \(conversationsDir)")
            
            // Load Settings
            let settings = loadSettings(at: settingsPath)
            print("AgyStatsService: Loaded settings: model=\(settings.model ?? "nil")")
            
            // Load History Lines
            var (loadedQueries, workspaces, lastQuery) = loadHistory(at: historyPath)
            print("AgyStatsService: Loaded history: queries count = \(loadedQueries.count), workspaces count = \(workspaces.count)")
            
            // Default to settings.model or Gemini 3.5 Flash (High)
            let defaultModel = settings.model ?? "Gemini 3.5 Flash (High)"
            let queries = loadedQueries.map { q -> QueryEntry in
                var copy = q
                copy.modelName = defaultModel
                return copy
            }
            
            // Load DB metadata and exact model names from SQLite for the first 150 queries
            var queriesWithMeta: [QueryEntry] = []
            var dbCache: [String: DbConversationData] = [:]
            
            for (index, q) in queries.enumerated() {
                var newQ = q
                if index < 150, let conversationId = q.conversationId {
                    let convData: DbConversationData
                    if let cached = dbCache[conversationId] {
                        convData = cached
                    } else {
                        convData = loadDbConversationData(conversationId: conversationId, cliDir: expandedDir)
                        dbCache[conversationId] = convData
                    }
                    
                    // Align queries with second-resolution timestamps in gen_metadata
                    let start = Date(timeIntervalSince1970: floor(q.timestamp.timeIntervalSince1970))
                    
                    // Find the next chronological query in the same conversation to establish the time window
                    var end = Date.distantFuture
                    for i in (0..<index).reversed() {
                        let nextQ = queries[i]
                        if nextQ.conversationId == conversationId {
                            end = Date(timeIntervalSince1970: floor(nextQ.timestamp.timeIntervalSince1970))
                            break
                        }
                    }
                    
                    // Find generations within this query's time window [start, end)
                    let turnGens = convData.generations.filter { gen in
                        guard let gTs = gen.timestamp else { return false }
                        return gTs >= start && gTs < end
                    }
                    
                    if !turnGens.isEmpty {
                        let llmCalls = turnGens.count
                        let totalOutputBytes = turnGens.reduce(0) { $0 + $1.size }
                        let totalInTokens = turnGens.compactMap { $0.inputTokens }.reduce(0, +)
                        let totalOutTokens = turnGens.compactMap { $0.outputTokens }.reduce(0, +)
                        newQ.conversationMeta = ConversationDbMeta(
                            llmCalls: llmCalls,
                            totalOutputBytes: totalOutputBytes,
                            inputTokens: totalInTokens,
                            outputTokens: totalOutTokens
                        )
                        
                        let turnModels = turnGens.compactMap { $0.modelName }
                        if let model = turnModels.last {
                            newQ.modelName = model
                        } else {
                            newQ.modelName = defaultModel
                        }
                    } else {
                        newQ.conversationMeta = ConversationDbMeta(llmCalls: 0, totalOutputBytes: 0)
                        
                        // Fallback: Use the latest model used prior to this query
                        let priorGens = convData.generations.filter { gen in
                            guard let gTs = gen.timestamp else { return false }
                            return gTs < start
                        }
                        if let lastPriorModel = priorGens.compactMap({ $0.modelName }).last {
                            newQ.modelName = lastPriorModel
                        } else if let firstPostModel = convData.generations.compactMap({ $0.modelName }).first {
                            newQ.modelName = firstPostModel
                        } else {
                            newQ.modelName = defaultModel
                        }
                    }
                }
                queriesWithMeta.append(newQ)
            }
            
            // Count queries today and this week
            let now = Date()
            let calendar = Calendar.current
            var queriesToday = 0
            var queriesThisWeek = 0
            
            let startOfToday = calendar.startOfDay(for: now)
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            
            for q in queriesWithMeta {
                if q.timestamp >= startOfToday {
                    queriesToday += 1
                }
                if q.timestamp >= sevenDaysAgo {
                    queriesThisWeek += 1
                }
            }
            print("AgyStatsService: Queries today = \(queriesToday), this week = \(queriesThisWeek)")
            
            // Load Tool Stats from SQLite Conversations DBs
            let toolStats = await loadToolStats(conversationsDir: conversationsDir)
            let totalToolCalls = toolStats.reduce(0) { $0 + $1.count }
            print("AgyStatsService: Loaded tool stats: count = \(toolStats.count), total calls = \(totalToolCalls)")
            
            // Fetch Quota Info
            let quotaInfo = await AgyQuotaService.fetchQuota()
            if let quotaInfo = quotaInfo {
                print("AgyStatsService: Fetched quota: plan = \(quotaInfo.plan ?? "nil"), email = \(quotaInfo.email ?? "nil"), groups count = \(quotaInfo.groups.count)")
            } else {
                print("AgyStatsService: Fetched quota: NONE")
            }
            
            // Model distribution and cost calculations
            var modelDist: [String: Int] = [:]
            var todayCost = 0.0
            var weekCost = 0.0
            var totalCost = 0.0
            
            for q in queriesWithMeta {
                if let modelName = q.modelName {
                    modelDist[modelName, default: 0] += 1
                }
                
                // Find model cost info
                let name = q.modelName ?? settings.model ?? ""
                let cleaned = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let model = knownModels.first(where: {
                    let mName = $0.name.lowercased()
                    return cleaned.contains(mName) || mName.contains(cleaned)
                }) ?? knownModels[2] // default Gemini 3.5 Flash (High)
                
                let (_, _, cost) = model.estimateTokensAndCost(for: q)
                
                totalCost += cost
                if q.timestamp >= startOfToday {
                    todayCost += cost
                }
                if q.timestamp >= sevenDaysAgo {
                    weekCost += cost
                }
            }
            
            let stats = AgyUsageStats(
                totalQueries: queries.count,
                queriesToday: queriesToday,
                queriesThisWeek: queriesThisWeek,
                lastQueryAt: lastQuery,
                workspaces: workspaces,
                modelDistribution: modelDist,
                recentQueries: Array(queriesWithMeta.prefix(100)),
                toolStats: toolStats,
                totalToolCalls: totalToolCalls,
                quotaInfo: quotaInfo,
                totalCostEstimate: totalCost,
                weeklyCostEstimate: weekCost,
                todayCostEstimate: todayCost
            )
            
            return (stats, settings)
        }.value
    }
    
    private static func loadSettings(at path: String) -> AgySettings {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return .default
        }
        do {
            return try JSONDecoder().decode(AgySettings.self, from: data)
        } catch {
            print("AgyStatsService: Failed to decode settings: \(error)")
            return .default
        }
    }
    
    private static func loadHistory(at path: String) -> ([QueryEntry], [WorkspaceStats], Date?) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ([], [], nil)
        }
        
        let lines = content.components(separatedBy: .newlines)
        var queries: [QueryEntry] = []
        var workspaceMap: [String: (count: Int, lastActive: Date)] = [:]
        
        let decoder = JSONDecoder()
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            
            if let data = trimmed.data(using: .utf8),
               let raw = try? decoder.decode(HistoryLine.self, from: data) {
                let date = Date(timeIntervalSince1970: TimeInterval(raw.timestamp) / 1000.0)
                let entry = QueryEntry(
                    display: raw.display,
                    timestamp: date,
                    workspace: raw.workspace,
                    conversationId: raw.conversationId,
                    type: raw.type
                )
                queries.append(entry)
                
                // Aggregate workspace stats
                let current = workspaceMap[raw.workspace] ?? (count: 0, lastActive: date)
                workspaceMap[raw.workspace] = (
                    count: current.count + 1,
                    lastActive: max(current.lastActive, date)
                )
            }
        }
        
        // Sort queries newest first
        queries.sort { $0.timestamp > $1.timestamp }
        let lastQuery = queries.first?.timestamp
        
        // Convert workspaces map to array and sort by query count descending
        let workspaces = workspaceMap.map { path, info in
            WorkspaceStats(path: path, queryCount: info.count, lastActiveAt: info.lastActive)
        }.sorted { $0.queryCount > $1.queryCount }
        
        return (queries, workspaces, lastQuery)
    }
    
    private static func loadToolStats(conversationsDir: String) async -> [ToolStat] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: conversationsDir) else {
            return []
        }
        
        let dbFiles = files.filter { $0.hasSuffix(".db") }
        var aggregatedStats: [String: Int] = [:]
        
        // Process DB files concurrently in groups
        for file in dbFiles {
            let dbPath = (conversationsDir as NSString).appendingPathComponent(file)
            let stats = queryToolStats(forDbPath: dbPath)
            for (tool, count) in stats {
                aggregatedStats[tool, default: 0] += count
            }
        }
        
        // Convert to ToolStat array sorted by count descending
        return aggregatedStats.map { toolName, count in
            ToolStat(toolName: toolName, count: count)
        }.sorted { $0.count > $1.count }
    }
    
    private struct DbGeneration {
        let idx: Int
        let size: Int
        let timestamp: Date?
        let modelName: String?
        let inputTokens: Int?
        let outputTokens: Int?
    }
    
    private struct DbConversationData {
        let generations: [DbGeneration]
    }
    
    private static func loadDbConversationData(conversationId: String, cliDir: String) -> DbConversationData {
        let dbPath = (cliDir as NSString).appendingPathComponent("conversations/\(conversationId).db")
        var generations: [DbGeneration] = []
        
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2("file:\(dbPath)?immutable=1", &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return DbConversationData(generations: [])
        }
        defer { sqlite3_close(db) }
        
        var statement: OpaquePointer?
        let query = "SELECT idx, data, size FROM gen_metadata ORDER BY idx ASC"
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            var lastTimestamp: Date? = nil
            while sqlite3_step(statement) == SQLITE_ROW {
                let idx = Int(sqlite3_column_int(statement, 0))
                let size = Int(sqlite3_column_int(statement, 2))
                var modelName: String? = nil
                var timestamp: Date? = nil
                var inputTokens: Int? = nil
                var outputTokens: Int? = nil
                
                if let blob = sqlite3_column_blob(statement, 1) {
                    let blobSize = sqlite3_column_bytes(statement, 1)
                    if blobSize > 0 {
                        let data = Data(bytes: blob, count: Int(blobSize))
                        let meta = extractMetadata(from: data)
                        modelName = meta.modelName
                        timestamp = meta.timestamp
                        inputTokens = meta.inputTokens
                        outputTokens = meta.outputTokens
                    }
                }
                
                if timestamp == nil {
                    timestamp = lastTimestamp
                } else {
                    lastTimestamp = timestamp
                }
                
                generations.append(DbGeneration(
                    idx: idx,
                    size: size,
                    timestamp: timestamp,
                    modelName: modelName,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens
                ))
            }
        }
        sqlite3_finalize(statement)
        
        return DbConversationData(generations: generations)
    }
    
    private static func parseProtobufFields(data: Data) -> [Int: Any] {
        var fields: [Int: Any] = [:]
        var index = data.startIndex
        while index < data.endIndex {
            var tag = 0
            var shift = 0
            var tagReadSuccess = false
            while index < data.endIndex {
                let b = data[index]
                index += 1
                tag |= Int(b & 0x7F) << shift
                if (b & 0x80) == 0 {
                    tagReadSuccess = true
                    break
                }
                shift += 7
            }
            guard tagReadSuccess, tag > 0 else { break }
            
            let wireType = tag & 0x07
            let fieldNumber = tag >> 3
            
            if wireType == 0 { // Varint
                var val = 0
                var valShift = 0
                var valReadSuccess = false
                while index < data.endIndex {
                    let b = data[index]
                    index += 1
                    val |= Int(b & 0x7F) << valShift
                    if (b & 0x80) == 0 {
                        valReadSuccess = true
                        break
                    }
                    valShift += 7
                }
                guard valReadSuccess else { break }
                fields[fieldNumber] = val
            } else if wireType == 1 { // 64-bit
                guard index + 8 <= data.endIndex else { break }
                let sub = data[index..<(index + 8)]
                index += 8
                fields[fieldNumber] = sub
            } else if wireType == 2 { // Length-delimited
                var length = 0
                var lenShift = 0
                var lenReadSuccess = false
                while index < data.endIndex {
                    let b = data[index]
                    index += 1
                    length |= Int(b & 0x7F) << lenShift
                    if (b & 0x80) == 0 {
                        lenReadSuccess = true
                        break
                    }
                    lenShift += 7
                }
                guard lenReadSuccess, index + length <= data.endIndex else { break }
                let sub = data[index..<(index + length)]
                index += length
                
                if fieldNumber == 1 || fieldNumber == 8 || fieldNumber == 9 || fieldNumber == 4 {
                    let subfields = parseProtobufFields(data: sub)
                    fields[fieldNumber] = subfields
                } else {
                    fields[fieldNumber] = sub
                }
            } else if wireType == 5 { // 32-bit
                guard index + 4 <= data.endIndex else { break }
                let sub = data[index..<(index + 4)]
                index += 4
                fields[fieldNumber] = sub
            } else {
                break
            }
        }
        return fields
    }
    
    private static func extractMetadata(from data: Data) -> (modelName: String?, timestamp: Date?, inputTokens: Int?, outputTokens: Int?) {
        let fields = parseProtobufFields(data: data)
        var modelName: String? = nil
        var timestamp: Date? = nil
        var inputTokens: Int? = nil
        var outputTokens: Int? = nil
        
        // Try getting model from nested Field 1
        if let f1 = fields[1] as? [Int: Any] {
            if let modelData = f1[19] as? Data,
               let name = String(data: modelData, encoding: .utf8) {
                modelName = cleanAndMapModelName(name)
            }
            
            // Try getting timestamp from Field 1 -> Field 9 -> Field 4 -> Field 1
            if let f9 = f1[9] as? [Int: Any],
               let f4 = f9[4] as? [Int: Any],
               let seconds = f4[1] as? Int {
                timestamp = Date(timeIntervalSince1970: TimeInterval(seconds))
            }
            
            // Try getting input/output tokens from Field 1 -> Field 4 -> Field 2 and Field 3
            if let f4 = f1[4] as? [Int: Any] {
                if let input = f4[2] as? Int {
                    inputTokens = input
                }
                if let output = f4[3] as? Int {
                    outputTokens = output
                }
            }
        }
        
        // Fallback: Try getting model from top-level field 19 if present
        if modelName == nil,
           let modelData = fields[19] as? Data,
           let name = String(data: modelData, encoding: .utf8) {
            modelName = cleanAndMapModelName(name)
        }
        
        return (modelName, timestamp, inputTokens, outputTokens)
    }
    
    private static func cleanAndMapModelName(_ name: String) -> String? {
        let cleaned = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let mappings: [(pattern: String, modelName: String)] = [
            ("opus", "Claude Opus 4.6 (Thinking)"),
            ("sonnet", "Claude Sonnet 4.6 (Thinking)"),
            ("claude-sonnet-4-6", "Claude Sonnet 4.6 (Thinking)"),
            ("gemini-3-pro-low", "Gemini 3.1 Pro (Low)"),
            ("pro-low", "Gemini 3.1 Pro (Low)"),
            ("gemini-3-pro-high", "Gemini 3.1 Pro (High)"),
            ("pro-high", "Gemini 3.1 Pro (High)"),
            ("gemini-3.1-pro-preview", "Gemini 3.1 Pro (High)"),
            ("gemini-1.5-pro", "Gemini 3.1 Pro (High)"),
            ("flash-extra-low", "Gemini 3.5 Flash (Low)"),
            ("flash-low", "Gemini 3.5 Flash (Low)"),
            ("flash-medium", "Gemini 3.5 Flash (Medium)"),
            ("flash-a", "Gemini 3.5 Flash (High)"),
            ("flash-agent", "Gemini 3.5 Flash (High)"),
            ("flash-high", "Gemini 3.5 Flash (High)"),
            ("gemini-3.5-flash", "Gemini 3.5 Flash (High)"),
            ("gemini-3-flash-preview", "Gemini 3.5 Flash (High)"),
            ("gemini-3-flash", "Gemini 3.5 Flash (High)"),
            ("gemini-2.0-flash", "Gemini 3.5 Flash (High)"),
            ("gemini-5h", "Gemini 3.5 Flash (High)")
        ]
        
        for mapping in mappings {
            if cleaned.contains(mapping.pattern) {
                return mapping.modelName
            }
        }
        
        let knownModelNames = [
            "Gemini 3.5 Flash (Low)",
            "Gemini 3.5 Flash (Medium)",
            "Gemini 3.5 Flash (High)",
            "Gemini 3.1 Pro (Low)",
            "Gemini 3.1 Pro (High)",
            "Claude Sonnet 4.6 (Thinking)",
            "Claude Opus 4.6 (Thinking)"
        ]
        for knownName in knownModelNames {
            if cleaned.contains(knownName.lowercased()) {
                return knownName
            }
        }
        
        return nil
    }
    
    private static func queryToolStats(forDbPath dbPath: String) -> [String: Int] {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2("file:\(dbPath)?immutable=1", &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return [:]
        }
        defer { sqlite3_close(db) }
        
        let query = "SELECT metadata, step_payload FROM steps"
        var statement: OpaquePointer?
        
        var stats: [String: Int] = [:]
        
        let tools = [
            "run_command", "replace_file_content", "view_file", "list_dir",
            "grep_search", "search_web", "read_url_content", "read_browser_page",
            "write_to_file", "ask_question", "ask_permission", "multi_replace_file_content",
            "define_subagent", "invoke_subagent", "send_message", "manage_subagents",
            "manage_task", "schedule"
        ]
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                var matchedTool: String? = nil
                
                // Check metadata (col 0) and step_payload (col 1)
                for col in [Int32(0), Int32(1)] {
                    guard let blobBytes = sqlite3_column_blob(statement, col) else { continue }
                    let blobSize = sqlite3_column_bytes(statement, col)
                    guard blobSize > 0 else { continue }
                    
                    let data = Data(bytes: blobBytes, count: Int(blobSize))
                    
                    // Fast check to see if any tool string matches ascii content
                    if let str = String(data: data, encoding: .ascii) {
                        for tool in tools {
                            if str.contains(tool) {
                                // Double check exact protobuf wire tag: tag 18 (0x12) followed by length byte
                                let lenByte = UInt8(tool.count)
                                let pattern: [UInt8] = [18, lenByte] + Array(tool.utf8)
                                if searchPattern(pattern, in: data) {
                                    matchedTool = tool
                                    break
                                }
                            }
                        }
                    }
                    if matchedTool != nil { break }
                }
                
                if let tool = matchedTool {
                    stats[tool, default: 0] += 1
                }
            }
        }
        sqlite3_finalize(statement)
        return stats
    }
    
    private static func searchPattern(_ pattern: [UInt8], in data: Data) -> Bool {
        guard data.count >= pattern.count else { return false }
        for i in 0...(data.count - pattern.count) {
            var match = true
            for j in 0..<pattern.count {
                if data[i + j] != pattern[j] {
                    match = false
                    break
                }
            }
            if match { return true }
        }
        return false
    }
}
