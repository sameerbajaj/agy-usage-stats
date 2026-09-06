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
    
    private struct DbGeneration: Sendable {
        let idx: Int
        let size: Int
        let timestamp: Date?
        let modelName: String?
        let inputTokens: Int?
        let outputTokens: Int?
        let cachedInputTokens: Int?
    }
    
    private struct DbConversationData: Sendable {
        let conversationId: String
        let startTime: Date?
        let generations: [DbGeneration]
    }
    
    // In-memory caches for fast warm refreshes
    private struct ConversationCacheEntry: Sendable {
        let modificationDate: Date
        let fileSize: Int64
        let conversationData: DbConversationData
        let toolCounts: [String: Int]
    }
    
    private struct HistoryCacheEntry {
        let modificationDate: Date
        let fileSize: Int64
        let queries: [QueryEntry]
        let workspaces: [WorkspaceStats]
        let lastQuery: Date?
    }
    
    private struct AuthCacheEntry {
        let fileCount: Int
        let newestName: String?
        let newestModDate: Date?
        let defaultProject: String?
        let cachedAt: Date
        let transitions: [AuthTransition]
    }
    
    private struct LogFileEntry {
        let modDate: Date
        let size: Int64
        let isGcp: Bool
        let project: String?
        let email: String?
    }
    
    private struct PrecomputedAuthState {
        let timestamp: Date
        let state: AuthStateAtDate
    }
    
    private static var conversationCache: [String: ConversationCacheEntry] = [:]
    private static let conversationCacheLock = NSLock()
    
    private static var historyCache: HistoryCacheEntry? = nil
    private static let historyCacheLock = NSLock()
    
    private static var authCache: AuthCacheEntry? = nil
    private static let authCacheLock = NSLock()
    
    private static var logFileCache: [String: LogFileEntry] = [:]
    private static let logFileCacheLock = NSLock()
    
    private struct StatsCacheEntry {
        let settings: AgySettings
        let startOfToday: Date
        let historyModDate: Date
        let historySize: Int64
        let conversationsDirModDate: Date
        let stats: AgyUsageStats
    }
    
    private static var statsCache: StatsCacheEntry? = nil
    private static let statsCacheLock = NSLock()
    
    public static func clearCaches() {
        conversationCacheLock.lock()
        conversationCache.removeAll()
        conversationCacheLock.unlock()
        
        historyCacheLock.lock()
        historyCache = nil
        historyCacheLock.unlock()
        
        authCacheLock.lock()
        authCache = nil
        authCacheLock.unlock()
        
        logFileCacheLock.lock()
        logFileCache.removeAll()
        logFileCacheLock.unlock()
        
        statsCacheLock.lock()
        statsCache = nil
        statsCacheLock.unlock()
        
        AgyQuotaService.clearCache()
    }
    
    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    
    private static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
    
    private static let dayShortLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    
    private static let monthKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()
    
    private static let monthLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    
    private static let monthShortLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM ''yy"
        return f
    }()
    
    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.timeZone = TimeZone.current
        return f
    }()
    
    private static let toolBytePatterns: [(tool: String, pattern: [UInt8])] = [
        "run_command", "replace_file_content", "view_file", "list_dir",
        "grep_search", "search_web", "read_url_content", "read_browser_page",
        "write_to_file", "ask_question", "ask_permission", "multi_replace_file_content",
        "define_subagent", "invoke_subagent", "send_message", "manage_subagents",
        "manage_task", "schedule"
    ].map { tool in
        (tool: tool, pattern: [18, UInt8(tool.count)] + Array(tool.utf8))
    }
    
    private static func binarySearchLowerBound(_ array: [Double], target: Double) -> Int {
        var low = 0
        var high = array.count
        while low < high {
            let mid = (low + high) / 2
            if array[mid] < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
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
            let logDir = (expandedDir as NSString).appendingPathComponent("log")
            
            let fm = FileManager.default
            let calendar = Calendar.current
            let now = Date()
            let startOfToday = calendar.startOfDay(for: now)
            
            let histAttrs = try? fm.attributesOfItem(atPath: historyPath)
            let histMod = histAttrs?[.modificationDate] as? Date ?? Date.distantPast
            let histSize = (histAttrs?[.size] as? NSNumber)?.int64Value ?? 0
            
            let convDirAttrs = try? fm.attributesOfItem(atPath: conversationsDir)
            let convDirMod = convDirAttrs?[.modificationDate] as? Date ?? Date.distantPast
            
            let settings = loadSettings(at: settingsPath)
            
            // Fast cache check: if history.jsonl, conversations dir, and settings haven't changed today, return immediately
            statsCacheLock.lock()
            if let cached = statsCache,
               cached.settings == settings,
               cached.startOfToday == startOfToday,
               cached.historyModDate == histMod,
               cached.historySize == histSize,
               cached.conversationsDirModDate == convDirMod {
                var cachedStats = cached.stats
                statsCacheLock.unlock()
                
                // Fetch fresh quota without blocking UI if already cached
                if let quota = await AgyQuotaService.fetchQuota() {
                    cachedStats.quotaInfo = quota
                }
                return (cachedStats, settings)
            }
            statsCacheLock.unlock()
            
            let tStart = ContinuousClock.now
            // Kick off quota fetch in background concurrently
            async let quotaTask = AgyQuotaService.fetchQuota()
            
            // Load Settings & Auth Transitions
            let currentIsGcp = settings.gcp?.project != nil && !(settings.gcp?.project?.isEmpty ?? true)
            let authTransitions = loadAuthTransitions(logDir: logDir, defaultProject: settings.gcp?.project)
            
            let tHist = ContinuousClock.now
            // Load History Lines
            let (loadedQueries, workspaces, lastQuery, _) = loadHistory(at: historyPath)
            
            // Date-aware fallback thresholds: Gemini 3.7 Flash on August 1, 2026; Gemini 3.8 Flash on September 2, 2026
            let aug2026 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)) ?? Date.distantFuture
            let sep2026 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2)) ?? Date.distantFuture
            
            let queries = loadedQueries.map { q -> QueryEntry in
                var copy = q
                let fallback: String
                if q.timestamp >= sep2026 {
                    fallback = settings.model ?? "Gemini 3.8 Flash (High)"
                } else if q.timestamp >= aug2026 {
                    fallback = "Gemini 3.7 Flash (High)"
                } else {
                    fallback = "Gemini 3.6 Flash (High)"
                }
                copy.modelName = fallback
                return copy
            }
            
            let tDb = ContinuousClock.now
            // Load all SQLite conversation databases and tool stats in a single parallel pass
            let (allDbConversations, toolStats, _) = await loadConversationsAndToolStats(conversationsDir: conversationsDir)
            let totalToolCalls = toolStats.reduce(0) { $0 + $1.count }
            
            var convStartMap: [Int: String] = [:]
            for (cid, conv) in allDbConversations {
                if let st = conv.startTime {
                    convStartMap[Int(floor(st.timeIntervalSince1970))] = cid
                }
            }
            
            // Pre-index subagent candidates by start time for binary search
            let subagentCandidates = allDbConversations.values.compactMap { conv -> (id: String, start: Double, gens: [DbGeneration])? in
                guard let st = conv.startTime else { return nil }
                return (id: conv.conversationId, start: st.timeIntervalSince1970, gens: conv.generations)
            }.sorted { $0.start < $1.start }
            let subagentStarts = subagentCandidates.map { $0.start }
            
            // Pre-resolve conversation IDs for queries to eliminate redundant lookups
            let resolvedConvIds: [String?] = queries.map { $0.conversationId ?? findConversationId(for: $0.timestamp, in: convStartMap) }
            
            // Map each conversation ID to its query timestamps in chronological (ascending) order
            var queryStartsByConv: [String: [Date]] = [:]
            for (i, cid) in resolvedConvIds.enumerated() {
                if let cid = cid {
                    let s = Date(timeIntervalSince1970: floor(queries[i].timestamp.timeIntervalSince1970))
                    queryStartsByConv[cid, default: []].append(s)
                }
            }
            for (cid, arr) in queryStartsByConv {
                queryStartsByConv[cid] = arr.reversed()
            }
            
            let tQueryStart = ContinuousClock.now
            
            let precomputedInitialAuthStates: [PrecomputedAuthState] = authTransitions.map { t in
                let isGcp = t.isGcp
                let project = isGcp ? (t.gcpProject ?? settings.gcp?.project ?? "clawdbot-485304") : nil
                let accountDisplayName: String
                if isGcp {
                    if let p = project, !p.isEmpty {
                        accountDisplayName = "GCP (\(p))"
                    } else {
                        accountDisplayName = "Google Cloud API"
                    }
                } else if let em = t.email, !em.isEmpty {
                    accountDisplayName = em
                } else {
                    accountDisplayName = "Account Quota"
                }
                return PrecomputedAuthState(
                    timestamp: t.timestamp,
                    state: AuthStateAtDate(
                        isGcp: isGcp,
                        email: t.email,
                        gcpProject: project,
                        accountDisplayName: accountDisplayName
                    )
                )
            }
            let initialDefaultAuthState: AuthStateAtDate = {
                let chosen = authTransitions.first
                let isGcp = chosen?.isGcp ?? currentIsGcp
                let project = isGcp ? (chosen?.gcpProject ?? settings.gcp?.project ?? "clawdbot-485304") : nil
                let accountDisplayName: String
                if isGcp {
                    if let p = project, !p.isEmpty {
                        accountDisplayName = "GCP (\(p))"
                    } else {
                        accountDisplayName = "Google Cloud API"
                    }
                } else if let em = chosen?.email, !em.isEmpty {
                    accountDisplayName = em
                } else {
                    accountDisplayName = "Account Quota"
                }
                return AuthStateAtDate(
                    isGcp: isGcp,
                    email: chosen?.email,
                    gcpProject: project,
                    accountDisplayName: accountDisplayName
                )
            }()
            func authForDateInitial(_ date: Date) -> AuthStateAtDate {
                for item in precomputedInitialAuthStates.reversed() {
                    if date >= item.timestamp {
                        return item.state
                    }
                }
                return initialDefaultAuthState
            }
            
            // Load DB metadata and exact model names from SQLite for all available queries
            var queriesWithMeta: [QueryEntry] = []
            queriesWithMeta.reserveCapacity(queries.count)
            
            for (index, q) in queries.enumerated() {
                var newQ = q
                let queryDefaultModel: String
                if q.timestamp >= sep2026 {
                    queryDefaultModel = settings.model ?? "Gemini 3.8 Flash (High)"
                } else if q.timestamp >= aug2026 {
                    queryDefaultModel = "Gemini 3.7 Flash (High)"
                } else {
                    queryDefaultModel = "Gemini 3.6 Flash (High)"
                }
                
                let resolvedConvId = resolvedConvIds[index]
                newQ.conversationId = resolvedConvId
                
                if let conversationId = resolvedConvId, let convData = allDbConversations[conversationId] {
                    // Align queries with second-resolution timestamps in gen_metadata
                    let start = Date(timeIntervalSince1970: floor(q.timestamp.timeIntervalSince1970))
                    
                    // Find the next chronological query in the same conversation to establish the time window (max 30 mins)
                    var end = start.addingTimeInterval(1800)
                    if let convStarts = queryStartsByConv[conversationId] {
                        if let nextStart = convStarts.first(where: { $0 > start }) {
                            end = min(end, nextStart)
                        }
                    }
                    
                    // Primary conversation generations in this query's time window [start, end)
                    let primaryGens = convData.generations.filter { gen in
                        guard let gTs = gen.timestamp else { return false }
                        return gTs >= start && gTs < end
                    }
                    
                    // Subagent conversations spawned during this query window via binary search
                    let startSec = start.timeIntervalSince1970
                    let endSec = end.timeIntervalSince1970
                    let lowIdx = binarySearchLowerBound(subagentStarts, target: startSec)
                    let highIdx = binarySearchLowerBound(subagentStarts, target: endSec)
                    
                    var subagentGens: [DbGeneration] = []
                    if lowIdx < highIdx {
                        for k in lowIdx..<highIdx {
                            let cand = subagentCandidates[k]
                            if cand.id != conversationId {
                                subagentGens.append(contentsOf: cand.gens)
                            }
                        }
                    }
                    
                    let turnGens = primaryGens + subagentGens
                    
                    if !turnGens.isEmpty {
                        var totalOutputBytes = 0
                        var totalInTokens = 0
                        var totalOutTokens = 0
                        var totalCachedTokens = 0
                        var lastTurnModel: String? = nil
                        for g in turnGens {
                            totalOutputBytes += g.size
                            if let inp = g.inputTokens { totalInTokens += inp }
                            if let out = g.outputTokens { totalOutTokens += out }
                            if let c = g.cachedInputTokens { totalCachedTokens += c }
                            if let m = g.modelName { lastTurnModel = m }
                        }
                        newQ.conversationMeta = ConversationDbMeta(
                            llmCalls: turnGens.count,
                            totalOutputBytes: totalOutputBytes,
                            inputTokens: totalInTokens,
                            outputTokens: totalOutTokens,
                            cachedInputTokens: totalCachedTokens
                        )
                        if let model = lastTurnModel {
                            newQ.modelName = enforceDateModelValidity(modelName: model, date: q.timestamp, aug2026: aug2026, sep2026: sep2026)
                        } else {
                            newQ.modelName = queryDefaultModel
                        }
                    } else {
                        newQ.conversationMeta = ConversationDbMeta(llmCalls: 0, totalOutputBytes: 0)
                        
                        // Fallback: Use the latest model used prior to this query
                        let priorGens = convData.generations.filter { gen in
                            guard let gTs = gen.timestamp else { return false }
                            return gTs < start
                        }
                        if let lastPriorModel = priorGens.compactMap({ $0.modelName }).last {
                            newQ.modelName = enforceDateModelValidity(modelName: lastPriorModel, date: q.timestamp, aug2026: aug2026, sep2026: sep2026)
                        } else if let firstPostModel = convData.generations.compactMap({ $0.modelName }).first {
                            newQ.modelName = enforceDateModelValidity(modelName: firstPostModel, date: q.timestamp, aug2026: aug2026, sep2026: sep2026)
                        } else {
                            newQ.modelName = queryDefaultModel
                        }
                    }
                }
                let authState = authForDateInitial(q.timestamp)
                newQ.isGcp = authState.isGcp
                newQ.gcpProject = authState.gcpProject
                newQ.accountEmail = authState.email
                queriesWithMeta.append(newQ)
            }
            
            // Count queries today and this week
            var queriesToday = 0
            var queriesThisWeek = 0
            let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
            
            for q in queriesWithMeta {
                if q.timestamp >= startOfToday {
                    queriesToday += 1
                }
                if q.timestamp >= sevenDaysAgo {
                    queriesThisWeek += 1
                } else {
                    break
                }
            }
            print("AgyStatsService: Queries today = \(queriesToday), this week = \(queriesThisWeek)")
            
            let tQuota = ContinuousClock.now
            // Await Quota Info (which ran concurrently in the background)
            let quotaInfo = await quotaTask
            print("TIME: quotaInfo await = \(tQuota.duration(to: .now))")
            if let quotaInfo = quotaInfo {
                print("AgyStatsService: Fetched quota: plan = \(quotaInfo.plan ?? "nil"), email = \(quotaInfo.email ?? "nil"), groups count = \(quotaInfo.groups.count)")
            } else {
                print("AgyStatsService: Fetched quota: NONE")
            }
            
            let tBuckets = ContinuousClock.now
            // Model distribution, cost calculations, and daily/monthly time buckets
            var modelDist: [String: Int] = [:]
            var todayCost = 0.0
            var weekCost = 0.0
            var totalCost = 0.0
            var gcpTotalCost = 0.0
            var gcpTodayCost = 0.0
            var gcpWeekCost = 0.0
            var quotaTotalCost = 0.0
            var quotaTodayCost = 0.0
            var quotaWeekCost = 0.0
            
            var accountCostTotals: [String: Double] = [:]
            var accountTodayTotals: [String: Double] = [:]
            var accountWeeklyTotals: [String: Double] = [:]
            
            let dayKeyFormatter = Self.dayKeyFormatter
            let dayLabelFormatter = Self.dayLabelFormatter
            let dayShortLabelFormatter = Self.dayShortLabelFormatter
            let monthKeyFormatter = Self.monthKeyFormatter
            let monthLabelFormatter = Self.monthLabelFormatter
            let monthShortLabelFormatter = Self.monthShortLabelFormatter
            
            struct DateBucketInfo {
                let dayKey: String
                let dayLabel: String
                let dayShortLabel: String
                let startOfDay: Date
                let monthKey: String
                let monthLabel: String
                let monthShortLabel: String
                let startOfMonth: Date
            }
            
            var dateBucketCache: [Int: DateBucketInfo] = [:]
            func getDateInfo(for date: Date) -> DateBucketInfo {
                let hourKey = Int(floor(date.timeIntervalSince1970 / 3600.0))
                if let cached = dateBucketCache[hourKey] {
                    return cached
                }
                let dayKey = dayKeyFormatter.string(from: date)
                let dayLabel = dayLabelFormatter.string(from: date)
                let dayShortLabel = dayShortLabelFormatter.string(from: date)
                let startOfDay = calendar.startOfDay(for: date)
                let monthKey = monthKeyFormatter.string(from: date)
                let monthLabel = monthLabelFormatter.string(from: date)
                let monthShortLabel = monthShortLabelFormatter.string(from: date)
                let monthComponents = calendar.dateComponents([.year, .month], from: date)
                let startOfMonth = calendar.date(from: monthComponents) ?? date
                let info = DateBucketInfo(
                    dayKey: dayKey,
                    dayLabel: dayLabel,
                    dayShortLabel: dayShortLabel,
                    startOfDay: startOfDay,
                    monthKey: monthKey,
                    monthLabel: monthLabel,
                    monthShortLabel: monthShortLabel,
                    startOfMonth: startOfMonth
                )
                dateBucketCache[hourKey] = info
                return info
            }
            
            let precomputedAuthStates: [PrecomputedAuthState] = authTransitions.map { t in
                let isGcp = t.isGcp
                let email = t.email ?? quotaInfo?.email
                let project = isGcp ? (t.gcpProject ?? settings.gcp?.project ?? "clawdbot-485304") : nil
                let accountDisplayName: String
                if isGcp {
                    if let p = project, !p.isEmpty {
                        accountDisplayName = "GCP (\(p))"
                    } else {
                        accountDisplayName = "Google Cloud API"
                    }
                } else if let em = email, !em.isEmpty {
                    accountDisplayName = em
                } else {
                    accountDisplayName = "Account Quota"
                }
                return PrecomputedAuthState(
                    timestamp: t.timestamp,
                    state: AuthStateAtDate(
                        isGcp: isGcp,
                        email: email,
                        gcpProject: project,
                        accountDisplayName: accountDisplayName
                    )
                )
            }
            
            let defaultAuthState: AuthStateAtDate = {
                let chosen = authTransitions.first
                let isGcp = chosen?.isGcp ?? currentIsGcp
                let email = chosen?.email ?? quotaInfo?.email
                let project = isGcp ? (chosen?.gcpProject ?? settings.gcp?.project ?? "clawdbot-485304") : nil
                let accountDisplayName: String
                if isGcp {
                    if let p = project, !p.isEmpty {
                        accountDisplayName = "GCP (\(p))"
                    } else {
                        accountDisplayName = "Google Cloud API"
                    }
                } else if let em = email, !em.isEmpty {
                    accountDisplayName = em
                } else {
                    accountDisplayName = "Account Quota"
                }
                return AuthStateAtDate(
                    isGcp: isGcp,
                    email: email,
                    gcpProject: project,
                    accountDisplayName: accountDisplayName
                )
            }()
            
            func authForDate(_ date: Date) -> AuthStateAtDate {
                for item in precomputedAuthStates.reversed() {
                    if date >= item.timestamp {
                        return item.state
                    }
                }
                return defaultAuthState
            }
            
            var modelCache: [String: ModelCostInfo] = [:]
            func resolveModel(name: String, fallback: ModelCostInfo) -> ModelCostInfo {
                if let cached = modelCache[name] {
                    return cached
                }
                let cleaned = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let model = knownModels.first(where: {
                    let mName = $0.name.lowercased()
                    return cleaned.contains(mName) || mName.contains(cleaned)
                }) ?? fallback
                modelCache[name] = model
                return model
            }
            
            final class MutableBucket {
                let periodKey: String
                let label: String
                let shortLabel: String
                let date: Date
                var queryCount: Int = 0
                var totalCost: Double = 0.0
                var inputTokens: Int = 0
                var outputTokens: Int = 0
                var gcpCost: Double = 0.0
                var quotaCost: Double = 0.0
                var modelBreakdown: [String: Double] = [:]
                var modelQueryBreakdown: [String: Int] = [:]
                var accountCostBreakdown: [String: Double] = [:]
                var accountQueryBreakdown: [String: Int] = [:]
                
                init(periodKey: String, label: String, shortLabel: String, date: Date) {
                    self.periodKey = periodKey
                    self.label = label
                    self.shortLabel = shortLabel
                    self.date = date
                }
                
                func toUsageTimeBucket() -> UsageTimeBucket {
                    UsageTimeBucket(
                        periodKey: periodKey,
                        label: label,
                        shortLabel: shortLabel,
                        date: date,
                        queryCount: queryCount,
                        totalCost: totalCost,
                        inputTokens: inputTokens,
                        outputTokens: outputTokens,
                        modelBreakdown: modelBreakdown,
                        modelQueryBreakdown: modelQueryBreakdown,
                        gcpCost: gcpCost,
                        quotaCost: quotaCost,
                        accountCostBreakdown: accountCostBreakdown,
                        accountQueryBreakdown: accountQueryBreakdown
                    )
                }
            }
            
            var dailyBuckets: [String: MutableBucket] = [:]
            var monthlyBuckets: [String: MutableBucket] = [:]
            
            // 2. Aggregate all actual LLM generations from all SQLite databases (ground truth for parent + subagents)
            let allGenerations = allDbConversations.values.flatMap { $0.generations }
            var daysWithDbGens = Set<String>()
            for gen in allGenerations {
                if let gTs = gen.timestamp {
                    daysWithDbGens.insert(getDateInfo(for: gTs).dayKey)
                }
            }
            
            // 1. Initialize buckets, query counts, and fallback estimates for older queries lacking SQLite DB files
            for q in queriesWithMeta {
                let authState = authForDate(q.timestamp)
                let accName = authState.accountDisplayName
                
                let dInfo = getDateInfo(for: q.timestamp)
                let dayKey = dInfo.dayKey
                let dayBucket: MutableBucket
                if let existing = dailyBuckets[dayKey] {
                    dayBucket = existing
                } else {
                    let b = MutableBucket(periodKey: dayKey, label: dInfo.dayLabel, shortLabel: dInfo.dayShortLabel, date: dInfo.startOfDay)
                    dailyBuckets[dayKey] = b
                    dayBucket = b
                }
                dayBucket.queryCount += 1
                dayBucket.accountQueryBreakdown[accName, default: 0] += 1
                if let mName = q.modelName {
                    dayBucket.modelQueryBreakdown[mName, default: 0] += 1
                }
                
                // Fallback for days with no SQLite DBs (e.g. May/June 2026): estimate tokens & cost from query
                if !daysWithDbGens.contains(dayKey) {
                    let name = q.modelName ?? "Gemini 3.6 Flash (High)"
                    let model = resolveModel(name: name, fallback: defaultGeminiModel)
                    
                    let (inTokens, outTokens, cost) = model.estimateTokensAndCost(for: q)
                    dayBucket.totalCost += cost
                    dayBucket.inputTokens += inTokens
                    dayBucket.outputTokens += outTokens
                    dayBucket.modelBreakdown[model.name, default: 0.0] += cost
                    dayBucket.accountCostBreakdown[accName, default: 0.0] += cost
                    totalCost += cost
                    accountCostTotals[accName, default: 0.0] += cost
                    if authState.isGcp {
                        dayBucket.gcpCost += cost
                        gcpTotalCost += cost
                        if q.timestamp >= startOfToday { gcpTodayCost += cost }
                        if q.timestamp >= sevenDaysAgo { gcpWeekCost += cost }
                    } else {
                        dayBucket.quotaCost += cost
                        quotaTotalCost += cost
                        if q.timestamp >= startOfToday { quotaTodayCost += cost }
                        if q.timestamp >= sevenDaysAgo { quotaWeekCost += cost }
                    }
                    if q.timestamp >= startOfToday {
                        accountTodayTotals[accName, default: 0.0] += cost
                    }
                    if q.timestamp >= sevenDaysAgo {
                        accountWeeklyTotals[accName, default: 0.0] += cost
                    }
                    modelDist[model.name, default: 0] += 1
                }
                
                let monthKey = dInfo.monthKey
                let monthBucket: MutableBucket
                if let existing = monthlyBuckets[monthKey] {
                    monthBucket = existing
                } else {
                    let b = MutableBucket(periodKey: monthKey, label: dInfo.monthLabel, shortLabel: dInfo.monthShortLabel, date: dInfo.startOfMonth)
                    monthlyBuckets[monthKey] = b
                    monthBucket = b
                }
                monthBucket.queryCount += 1
                monthBucket.accountQueryBreakdown[accName, default: 0] += 1
                if let mName = q.modelName {
                    monthBucket.modelQueryBreakdown[mName, default: 0] += 1
                }
                if !daysWithDbGens.contains(dayKey) {
                    let name = q.modelName ?? "Gemini 3.6 Flash (High)"
                    let model = resolveModel(name: name, fallback: defaultGeminiModel)
                    
                    let (inTokens, outTokens, cost) = model.estimateTokensAndCost(for: q)
                    monthBucket.totalCost += cost
                    monthBucket.inputTokens += inTokens
                    monthBucket.outputTokens += outTokens
                    monthBucket.modelBreakdown[model.name, default: 0.0] += cost
                    monthBucket.accountCostBreakdown[accName, default: 0.0] += cost
                    if authState.isGcp {
                        monthBucket.gcpCost += cost
                    } else {
                        monthBucket.quotaCost += cost
                    }
                }
            }
            
            for gen in allGenerations {
                let genDate = gen.timestamp ?? startOfToday
                
                let defaultModelForDate: String
                if genDate >= sep2026 {
                    defaultModelForDate = settings.model ?? "Gemini 3.8 Flash (High)"
                } else if genDate >= aug2026 {
                    defaultModelForDate = "Gemini 3.7 Flash (High)"
                } else {
                    defaultModelForDate = "Gemini 3.6 Flash (High)"
                }
                
                let rawName = gen.modelName ?? defaultModelForDate
                let validName = enforceDateModelValidity(modelName: rawName, date: genDate, aug2026: aug2026, sep2026: sep2026)
                let fallbackModel = genDate >= sep2026 ? defaultGeminiModel : (knownModels.first(where: { $0.name == "Gemini 3.7 Flash (High)" }) ?? defaultGeminiModel)
                let model = resolveModel(name: validName, fallback: fallbackModel)
                
                let pTokens = gen.inputTokens ?? 0
                let cTokens = gen.cachedInputTokens ?? 0
                let oTokens = gen.outputTokens ?? 0
                
                let cost: Double
                let inTokens: Int
                let outTokens: Int
                
                if pTokens > 0 || cTokens > 0 || oTokens > 0 {
                    let promptCost = (Double(pTokens) / 1_000_000.0) * model.inputPricePerMillion
                    let cachedCost = (Double(cTokens) / 1_000_000.0) * model.cachedInputPricePerMillion
                    let outputCost = (Double(oTokens) / 1_000_000.0) * model.outputPricePerMillion
                    cost = promptCost + cachedCost + outputCost
                    inTokens = pTokens + cTokens
                    outTokens = oTokens
                } else if gen.size > 0 {
                    outTokens = max(80, gen.size / 4)
                    inTokens = Int(model.tier.inputTokens * 0.35)
                    cost = (Double(inTokens) / 1_000_000.0) * model.inputPricePerMillion + (Double(outTokens) / 1_000_000.0) * model.outputPricePerMillion
                } else {
                    continue
                }
                
                let authState = authForDate(genDate)
                let accName = authState.accountDisplayName
                
                totalCost += cost
                accountCostTotals[accName, default: 0.0] += cost
                if authState.isGcp {
                    gcpTotalCost += cost
                } else {
                    quotaTotalCost += cost
                }
                
                if genDate >= startOfToday {
                    todayCost += cost
                    accountTodayTotals[accName, default: 0.0] += cost
                    if authState.isGcp {
                        gcpTodayCost += cost
                    } else {
                        quotaTodayCost += cost
                    }
                }
                if genDate >= sevenDaysAgo {
                    weekCost += cost
                    accountWeeklyTotals[accName, default: 0.0] += cost
                    if authState.isGcp {
                        gcpWeekCost += cost
                    } else {
                        quotaWeekCost += cost
                    }
                }
                
                modelDist[model.name, default: 0] += 1
                
                let dInfo = getDateInfo(for: genDate)
                let dayKey = dInfo.dayKey
                let dayBucket: MutableBucket
                if let existing = dailyBuckets[dayKey] {
                    dayBucket = existing
                } else {
                    let b = MutableBucket(periodKey: dayKey, label: dInfo.dayLabel, shortLabel: dInfo.dayShortLabel, date: dInfo.startOfDay)
                    dailyBuckets[dayKey] = b
                    dayBucket = b
                }
                dayBucket.totalCost += cost
                dayBucket.inputTokens += inTokens
                dayBucket.outputTokens += outTokens
                dayBucket.modelBreakdown[model.name, default: 0.0] += cost
                dayBucket.accountCostBreakdown[accName, default: 0.0] += cost
                if authState.isGcp {
                    dayBucket.gcpCost += cost
                } else {
                    dayBucket.quotaCost += cost
                }
                
                let monthKey = dInfo.monthKey
                let monthBucket: MutableBucket
                if let existing = monthlyBuckets[monthKey] {
                    monthBucket = existing
                } else {
                    let b = MutableBucket(periodKey: monthKey, label: dInfo.monthLabel, shortLabel: dInfo.monthShortLabel, date: dInfo.startOfMonth)
                    monthlyBuckets[monthKey] = b
                    monthBucket = b
                }
                monthBucket.totalCost += cost
                monthBucket.inputTokens += inTokens
                monthBucket.outputTokens += outTokens
                monthBucket.modelBreakdown[model.name, default: 0.0] += cost
                monthBucket.accountCostBreakdown[accName, default: 0.0] += cost
                if authState.isGcp {
                    monthBucket.gcpCost += cost
                } else {
                    monthBucket.quotaCost += cost
                }
            }
            
            // Fill in missing days from the earliest recorded date up to today so every calendar month has complete daily buckets
            let earliestQueryDate = queries.last?.timestamp ?? startOfToday
            let earliestGenDate = allGenerations.compactMap({ $0.timestamp }).min() ?? startOfToday
            let earliestDate = min(earliestQueryDate, earliestGenDate)
            let earliestMonthComponents = calendar.dateComponents([.year, .month], from: earliestDate)
            let startOfEarliestMonth = calendar.date(from: earliestMonthComponents) ?? startOfToday
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday
            let fillStartDate = min(startOfEarliestMonth, thirtyDaysAgo)
            
            var dayCursor = fillStartDate
            while dayCursor <= startOfToday {
                let dInfo = getDateInfo(for: dayCursor)
                let key = dInfo.dayKey
                if dailyBuckets[key] == nil {
                    dailyBuckets[key] = MutableBucket(
                        periodKey: key,
                        label: dInfo.dayLabel,
                        shortLabel: dInfo.dayShortLabel,
                        date: dayCursor
                    )
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayCursor) else { break }
                dayCursor = nextDay
            }
            
            let sortedDaily = dailyBuckets.values.map { $0.toUsageTimeBucket() }.sorted { $0.date < $1.date }
            let sortedMonthly = monthlyBuckets.values.map { $0.toUsageTimeBucket() }.sorted { $0.date < $1.date }
            
            let stats = AgyUsageStats(
                totalQueries: queries.count,
                queriesToday: queriesToday,
                queriesThisWeek: queriesThisWeek,
                lastQueryAt: lastQuery,
                workspaces: workspaces,
                modelDistribution: modelDist,
                recentQueries: queriesWithMeta,
                toolStats: toolStats,
                totalToolCalls: totalToolCalls,
                quotaInfo: quotaInfo,
                totalCostEstimate: totalCost,
                weeklyCostEstimate: weekCost,
                todayCostEstimate: todayCost,
                dailyUsage: sortedDaily,
                monthlyUsage: sortedMonthly,
                gcpProject: settings.gcp?.project,
                gcpLocation: settings.gcp?.location,
                gcpTotalCost: gcpTotalCost,
                gcpTodayCost: gcpTodayCost,
                gcpWeeklyCost: gcpWeekCost,
                quotaTotalCost: quotaTotalCost,
                quotaTodayCost: quotaTodayCost,
                quotaWeeklyCost: quotaWeekCost,
                availableAccounts: Array(accountCostTotals.keys).sorted(),
                accountCostTotals: accountCostTotals,
                accountTodayTotals: accountTodayTotals,
                accountWeeklyTotals: accountWeeklyTotals
            )
            
            statsCacheLock.lock()
            statsCache = StatsCacheEntry(
                settings: settings,
                startOfToday: startOfToday,
                historyModDate: histMod,
                historySize: histSize,
                conversationsDirModDate: convDirMod,
                stats: stats
            )
            statsCacheLock.unlock()
            
            let dAuth = tStart.duration(to: tHist)
            let dHist = tHist.duration(to: tDb)
            let dDb = tDb.duration(to: tQueryStart)
            let dQuery = tQueryStart.duration(to: tQuota)
            let dQuota = tQuota.duration(to: tBuckets)
            let dBuckets = tBuckets.duration(to: .now)
            let dTotal = tStart.duration(to: .now)
            
            let timingSummary = """
            --- LOAD STATS RUN ---
            Auth: \(dAuth)
            History: \(dHist)
            DB & Tools: \(dDb)
            Query Matching: \(dQuery)
            Quota Await: \(dQuota)
            Buckets: \(dBuckets)
            TOTAL: \(dTotal)
            
            """
            print(timingSummary)
            return (stats, settings)
        }.value
    }
    
    public struct AuthTransition {
        public let timestamp: Date
        public let isGcp: Bool
        public let email: String?
        public let gcpProject: String?
        
        public init(timestamp: Date, isGcp: Bool, email: String? = nil, gcpProject: String? = nil) {
            self.timestamp = timestamp
            self.isGcp = isGcp
            self.email = email
            self.gcpProject = gcpProject
        }
    }
    
    public struct AuthStateAtDate {
        public let isGcp: Bool
        public let email: String?
        public let gcpProject: String?
        public let accountDisplayName: String
    }
    
    private static func loadAuthTransitions(logDir: String, defaultProject: String?) -> [AuthTransition] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: logDir) else {
            return []
        }
        
        let logFiles = files.filter { $0.hasPrefix("cli-") && $0.hasSuffix(".log") }.sorted()
        guard !logFiles.isEmpty else { return [] }
        let newestFile = logFiles.last!
        let newestPath = (logDir as NSString).appendingPathComponent(newestFile)
        let newestMod = (try? fm.attributesOfItem(atPath: newestPath))?[.modificationDate] as? Date
        
        let now = Date()
        authCacheLock.lock()
        if let cached = authCache,
           cached.defaultProject == defaultProject {
            // Fast TTL check: if checked within last 30s, reuse transitions immediately
            if now.timeIntervalSince(cached.cachedAt) < 30.0 {
                let res = cached.transitions
                authCacheLock.unlock()
                return res
            }
            // If beyond 30s, check if file count, newest file, and newest mod date match
            if cached.fileCount == logFiles.count,
               cached.newestName == newestFile,
               cached.newestModDate == newestMod {
                authCache = AuthCacheEntry(
                    fileCount: cached.fileCount,
                    newestName: cached.newestName,
                    newestModDate: cached.newestModDate,
                    defaultProject: defaultProject,
                    cachedAt: now,
                    transitions: cached.transitions
                )
                let res = cached.transitions
                authCacheLock.unlock()
                return res
            }
        }
        authCacheLock.unlock()
        
        var transitions: [AuthTransition] = []
        var lastIsGcp: Bool? = nil
        var lastEmail: String? = nil
        var lastProject: String? = nil
        
        let emailRegex = try? NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        
        for file in logFiles {
            let stripped = file.replacingOccurrences(of: "cli-", with: "").replacingOccurrences(of: ".log", with: "")
            guard let date = Self.logDateFormatter.date(from: stripped) else { continue }
            
            let fullPath = (logDir as NSString).appendingPathComponent(file)
            let attrs = try? fm.attributesOfItem(atPath: fullPath)
            let fileMod = attrs?[.modificationDate] as? Date ?? Date.distantPast
            let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            
            var isGcp: Bool
            var project: String?
            var email: String?
            
            logFileCacheLock.lock()
            if let cachedLog = logFileCache[file],
               cachedLog.modDate == fileMod,
               cachedLog.size == fileSize {
                isGcp = cachedLog.isGcp
                project = cachedLog.project
                email = cachedLog.email
                logFileCacheLock.unlock()
            } else {
                logFileCacheLock.unlock()
                guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: fullPath)) else { continue }
                let data = handle.readData(ofLength: 65536)
                try? handle.close()
                
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else { continue }
                isGcp = text.contains("aiplatform") || text.contains("clawdbot") || text.contains("EnterProject") || text.contains("GCP setup completed")
                project = isGcp ? (defaultProject ?? "clawdbot-485304") : nil
                
                if let regex = emailRegex {
                    let range = NSRange(text.startIndex..., in: text)
                    let matches = regex.matches(in: text, range: range)
                    for match in matches {
                        if let r = Range(match.range, in: text) {
                            let candidate = String(text[r])
                            if candidate.contains("sameer") || candidate.contains("rowan") || candidate.contains("gmail") {
                                email = candidate
                                break
                            }
                        }
                    }
                }
                if email == nil {
                    email = lastEmail ?? "sameerbajaj24@gmail.com"
                }
                
                logFileCacheLock.lock()
                logFileCache[file] = LogFileEntry(
                    modDate: fileMod,
                    size: fileSize,
                    isGcp: isGcp,
                    project: project,
                    email: email
                )
                logFileCacheLock.unlock()
            }
            
            if lastIsGcp != isGcp || (email != nil && email != lastEmail) || project != lastProject {
                transitions.append(AuthTransition(timestamp: date, isGcp: isGcp, email: email, gcpProject: project))
                lastIsGcp = isGcp
                lastEmail = email
                lastProject = project
            }
        }
        
        authCacheLock.lock()
        authCache = AuthCacheEntry(
            fileCount: logFiles.count,
            newestName: newestFile,
            newestModDate: newestMod,
            defaultProject: defaultProject,
            cachedAt: now,
            transitions: transitions
        )
        authCacheLock.unlock()
        
        return transitions
    }
    
    private static func authAt(
        date: Date,
        transitions: [AuthTransition],
        currentIsGcp: Bool,
        currentEmail: String?,
        currentProject: String?
    ) -> AuthStateAtDate {
        var matchTransition: AuthTransition? = nil
        for t in transitions.reversed() {
            if date >= t.timestamp {
                matchTransition = t
                break
            }
        }
        let chosen = matchTransition ?? transitions.first
        let isGcp = chosen?.isGcp ?? currentIsGcp
        let email = chosen?.email ?? currentEmail
        let project = isGcp ? (chosen?.gcpProject ?? currentProject ?? "clawdbot-485304") : nil
        
        let accountDisplayName: String
        if isGcp {
            if let p = project, !p.isEmpty {
                accountDisplayName = "GCP (\(p))"
            } else {
                accountDisplayName = "Google Cloud API"
            }
        } else if let em = email, !em.isEmpty {
            accountDisplayName = em
        } else {
            accountDisplayName = "Account Quota"
        }
        
        return AuthStateAtDate(
            isGcp: isGcp,
            email: email,
            gcpProject: project,
            accountDisplayName: accountDisplayName
        )
    }
    
    private static func isGcpAt(date: Date, transitions: [AuthTransition], currentIsGcp: Bool) -> Bool {
        guard !transitions.isEmpty else { return currentIsGcp }
        for t in transitions.reversed() {
            if date >= t.timestamp {
                return t.isGcp
            }
        }
        return false
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
    
    private static func loadHistory(at path: String) -> ([QueryEntry], [WorkspaceStats], Date?, Bool) {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: path)
        let modDate = attrs?[.modificationDate] as? Date ?? Date.distantPast
        let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        
        historyCacheLock.lock()
        if let cached = historyCache,
           cached.modificationDate == modDate,
           cached.fileSize == fileSize {
            let res = (cached.queries, cached.workspaces, cached.lastQuery, true)
            historyCacheLock.unlock()
            return res
        }
        historyCacheLock.unlock()
        
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return ([], [], nil, false)
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
        
        historyCacheLock.lock()
        historyCache = HistoryCacheEntry(
            modificationDate: modDate,
            fileSize: fileSize,
            queries: queries,
            workspaces: workspaces,
            lastQuery: lastQuery
        )
        historyCacheLock.unlock()
        
        return (queries, workspaces, lastQuery, false)
    }
    
    private struct ProtobufMessage {
        var varints: [Int: [Int]] = [:]
        var byteFields: [Int: [Data]] = [:]
        
        func firstVarint(for tag: Int) -> Int? {
            return varints[tag]?.first
        }
        
        func firstData(for tag: Int) -> Data? {
            return byteFields[tag]?.first
        }
        
        func string(for tag: Int) -> String? {
            guard let d = firstData(for: tag) else { return nil }
            return String(data: d, encoding: .utf8)
        }
        
        func submessage(for tag: Int) -> ProtobufMessage? {
            guard let d = firstData(for: tag) else { return nil }
            return ProtobufMessage.parse(data: d)
        }
        
        func submessages(for tag: Int) -> [ProtobufMessage] {
            guard let list = byteFields[tag] else { return [] }
            return list.compactMap { ProtobufMessage.parse(data: $0) }
        }
        
        static func parse(data: Data) -> ProtobufMessage? {
            var msg = ProtobufMessage()
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
                
                switch wireType {
                case 0: // Varint
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
                    msg.varints[fieldNumber, default: []].append(val)
                    
                case 1: // 64-bit
                    guard index + 8 <= data.endIndex else { break }
                    index += 8
                    
                case 2: // Length-delimited
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
                    msg.byteFields[fieldNumber, default: []].append(sub)
                    
                case 5: // 32-bit
                    guard index + 4 <= data.endIndex else { break }
                    index += 4
                    
                default:
                    return msg
                }
            }
            return msg
        }
    }
    
    private static func findConversationId(for timestamp: Date, in startMap: [Int: String]) -> String? {
        let sec = Int(floor(timestamp.timeIntervalSince1970))
        for offset in [0, 1, -1, 2, -2, 3, -3] {
            if let found = startMap[sec + offset] {
                return found
            }
        }
        return nil
    }
    
    private static func parseDbConversationAndToolStats(file: String, conversationsDir: String, fm: FileManager) -> (DbConversationData, [String: Int], Bool) {
        let convId = (file as NSString).deletingPathExtension
        let dbPath = (conversationsDir as NSString).appendingPathComponent(file)
        
        let attrs = try? fm.attributesOfItem(atPath: dbPath)
        let modDate = attrs?[.modificationDate] as? Date ?? Date.distantPast
        let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        
        conversationCacheLock.lock()
        if let cached = conversationCache[file],
           cached.modificationDate == modDate,
           cached.fileSize == fileSize {
            let res = (cached.conversationData, cached.toolCounts, true)
            conversationCacheLock.unlock()
            return res
        }
        conversationCacheLock.unlock()
        
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2("file:\(dbPath)?immutable=1", &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            let emptyData = DbConversationData(conversationId: convId, startTime: nil, generations: [])
            return (emptyData, [:], false)
        }
        defer { sqlite3_close(db) }
        
        // 1. Single pass: Load step timestamps and count tool calls from steps table
        var startTime: Date? = nil
        var stepsTimestamps: [Int: Date] = [:]
        var toolCounts: [String: Int] = [:]
        var stepsStmt: OpaquePointer?
        let stepsQuery = "SELECT idx, metadata, step_payload FROM steps ORDER BY idx ASC"
        if sqlite3_prepare_v2(db, stepsQuery, -1, &stepsStmt, nil) == SQLITE_OK {
            while sqlite3_step(stepsStmt) == SQLITE_ROW {
                let stepIdx = Int(sqlite3_column_int(stepsStmt, 0))
                
                // Timestamp from metadata (col 1)
                if let blob = sqlite3_column_blob(stepsStmt, 1) {
                    let blobSize = sqlite3_column_bytes(stepsStmt, 1)
                    if blobSize > 0 {
                        let data = Data(bytes: blob, count: Int(blobSize))
                        if let msg = ProtobufMessage.parse(data: data),
                           let sub = msg.submessage(for: 1),
                           let seconds = sub.firstVarint(for: 1) {
                            let dt = Date(timeIntervalSince1970: TimeInterval(seconds))
                            stepsTimestamps[stepIdx] = dt
                            if startTime == nil {
                                startTime = dt
                            }
                        }
                    }
                }
                
                // Tool calls from metadata (col 1) and step_payload (col 2)
                var matchedTool: String? = nil
                for col in [Int32(1), Int32(2)] {
                    guard let blobBytes = sqlite3_column_blob(stepsStmt, col) else { continue }
                    let blobSize = sqlite3_column_bytes(stepsStmt, col)
                    guard blobSize > 0 else { continue }
                    let data = Data(bytes: blobBytes, count: Int(blobSize))
                    if let str = String(data: data, encoding: .ascii) {
                        for (tool, pattern) in toolBytePatterns {
                            if str.contains(tool) {
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
                    toolCounts[tool, default: 0] += 1
                }
            }
        }
        sqlite3_finalize(stepsStmt)
        
        // 2. Load generation metadata
        var generations: [DbGeneration] = []
        var genStmt: OpaquePointer?
        let genQuery = "SELECT idx, data, size FROM gen_metadata ORDER BY idx ASC"
        if sqlite3_prepare_v2(db, genQuery, -1, &genStmt, nil) == SQLITE_OK {
            var lastTimestamp: Date? = nil
            while sqlite3_step(genStmt) == SQLITE_ROW {
                let idx = Int(sqlite3_column_int(genStmt, 0))
                let size = Int(sqlite3_column_int(genStmt, 2))
                var modelName: String? = nil
                var timestamp: Date? = nil
                var inputTokens: Int? = nil
                var outputTokens: Int? = nil
                var cachedTokens: Int? = nil
                
                if let blob = sqlite3_column_blob(genStmt, 1) {
                    let blobSize = sqlite3_column_bytes(genStmt, 1)
                    if blobSize > 0 {
                        let data = Data(bytes: blob, count: Int(blobSize))
                        if let msg = ProtobufMessage.parse(data: data) {
                            let f1 = msg.submessage(for: 1)
                            
                            // Model name
                            if let rawModel = f1?.string(for: 19) ?? msg.string(for: 19) {
                                modelName = cleanAndMapModelName(rawModel)
                            }
                            
                            // Tokens from Field 1 -> Field 4
                            if let f4 = f1?.submessage(for: 4) {
                                inputTokens = f4.firstVarint(for: 2)
                                outputTokens = f4.firstVarint(for: 3)
                                cachedTokens = f4.firstVarint(for: 5)
                            }
                            
                            // Step index from Field 1 -> Field 20
                            let f20List = f1?.submessages(for: 20) ?? msg.submessages(for: 20)
                            for kv in f20List {
                                if kv.string(for: 1) == "last_step_index",
                                   let v = kv.string(for: 2),
                                   let sIdx = Int(v) {
                                    timestamp = stepsTimestamps[sIdx]
                                    break
                                }
                            }
                        }
                    }
                }
                
                if timestamp == nil {
                    timestamp = lastTimestamp ?? startTime
                } else {
                    lastTimestamp = timestamp
                }
                
                generations.append(DbGeneration(
                    idx: idx,
                    size: size,
                    timestamp: timestamp,
                    modelName: modelName,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cachedInputTokens: cachedTokens
                ))
            }
        }
        sqlite3_finalize(genStmt)
        
        let convData = DbConversationData(conversationId: convId, startTime: startTime, generations: generations)
        
        conversationCacheLock.lock()
        conversationCache[file] = ConversationCacheEntry(
            modificationDate: modDate,
            fileSize: fileSize,
            conversationData: convData,
            toolCounts: toolCounts
        )
        conversationCacheLock.unlock()
        
        return (convData, toolCounts, false)
    }
    
    private static func loadConversationsAndToolStats(conversationsDir: String) async -> ([String: DbConversationData], [ToolStat], Bool) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: conversationsDir) else {
            return ([:], [], false)
        }
        
        let dbFiles = files.filter { $0.hasSuffix(".db") }
        guard !dbFiles.isEmpty else { return ([:], [], false) }
        
        let results = await withTaskGroup(of: (DbConversationData, [String: Int], Bool).self) { group in
            for file in dbFiles {
                group.addTask {
                    return parseDbConversationAndToolStats(file: file, conversationsDir: conversationsDir, fm: fm)
                }
            }
            var collected: [(DbConversationData, [String: Int], Bool)] = []
            collected.reserveCapacity(dbFiles.count)
            for await res in group {
                collected.append(res)
            }
            return collected
        }
        
        var anyMiss = false
        var conversationsDict: [String: DbConversationData] = [:]
        conversationsDict.reserveCapacity(results.count)
        var aggregatedTools: [String: Int] = [:]
        
        for (convData, toolCounts, hit) in results {
            if !hit { anyMiss = true }
            conversationsDict[convData.conversationId] = convData
            for (tool, count) in toolCounts {
                aggregatedTools[tool, default: 0] += count
            }
        }
        
        let toolStats = aggregatedTools.map { ToolStat(toolName: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            
        return (conversationsDict, toolStats, anyMiss)
    }
    
    private static func cleanAndMapModelName(_ name: String) -> String? {
        let cleaned = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let mappings: [(pattern: String, modelName: String)] = [
            ("opus", "Claude Opus 4.6 (Thinking)"),
            ("sonnet", "Claude Sonnet 4.6 (Thinking)"),
            ("claude-sonnet-4-6", "Claude Sonnet 4.6 (Thinking)"),
            ("gpt-oss", "GPT-OSS-120B"),
            ("oss-120b", "GPT-OSS-120B"),
            ("gemini-3.8-flash-low", "Gemini 3.8 Flash (Low)"),
            ("gemini-3.8-flash-medium", "Gemini 3.8 Flash (Medium)"),
            ("gemini-3.8-flash-high", "Gemini 3.8 Flash (High)"),
            ("gemini-3.8-flash-cyber", "Gemini 3.8 Flash Cyber"),
            ("3.8-flash-cyber", "Gemini 3.8 Flash Cyber"),
            ("gemini-3.8-flash", "Gemini 3.8 Flash (High)"),
            ("gemini-3.8", "Gemini 3.8 Flash (High)"),
            ("3.8-flash", "Gemini 3.8 Flash (High)"),
            ("flash-3.8", "Gemini 3.8 Flash (High)"),
            ("gemini-3.7-flash-low", "Gemini 3.7 Flash (Low)"),
            ("gemini-3.7-flash-medium", "Gemini 3.7 Flash (Medium)"),
            ("gemini-3.7-flash-high", "Gemini 3.7 Flash (High)"),
            ("gemini-3.7-flash", "Gemini 3.7 Flash (High)"),
            ("gemini-3.7", "Gemini 3.7 Flash (High)"),
            ("3.7-flash", "Gemini 3.7 Flash (High)"),
            ("flash-3.7", "Gemini 3.7 Flash (High)"),
            ("gemini-3.6-flash-low", "Gemini 3.6 Flash (Low)"),
            ("gemini-3.6-flash-medium", "Gemini 3.6 Flash (Medium)"),
            ("gemini-3.6-flash-high", "Gemini 3.6 Flash (High)"),
            ("gemini-3.6-flash", "Gemini 3.6 Flash (High)"),
            ("gemini-3.6-pro-low", "Gemini 3.1 Pro (Low)"),
            ("gemini-3.6-pro-high", "Gemini 3.1 Pro (High)"),
            ("gemini-3.6-pro", "Gemini 3.1 Pro (High)"),
            ("gemini-3.6", "Gemini 3.6 Flash (High)"),
            ("3.6-flash", "Gemini 3.6 Flash (High)"),
            ("flash-3.6", "Gemini 3.6 Flash (High)"),
            ("gemini-3-pro-low", "Gemini 3.1 Pro (Low)"),
            ("pro-low", "Gemini 3.1 Pro (Low)"),
            ("gemini-3-pro-high", "Gemini 3.1 Pro (High)"),
            ("pro-high", "Gemini 3.1 Pro (High)"),
            ("gemini-3.1-pro-preview", "Gemini 3.1 Pro (High)"),
            ("gemini-3.1-pro", "Gemini 3.1 Pro (High)"),
            ("gemini-3.1", "Gemini 3.1 Pro (High)"),
            ("gemini-1.5-pro", "Gemini 3.1 Pro (High)"),
            ("flash-extra-low", "Gemini 3.7 Flash (Low)"),
            ("flash-low", "Gemini 3.7 Flash (Low)"),
            ("flash-medium", "Gemini 3.7 Flash (Medium)"),
            ("flash-a", "Gemini 3.7 Flash (High)"),
            ("flash-agent", "Gemini 3.7 Flash (High)"),
            ("flash-high", "Gemini 3.7 Flash (High)"),
            ("gemini-3.5-flash", "Gemini 3.5 Flash (High)"),
            ("gemini-3-flash-preview", "Gemini 3.7 Flash (High)"),
            ("gemini-3-flash", "Gemini 3.7 Flash (High)"),
            ("gemini-2.0-flash", "Gemini 3.7 Flash (High)"),
            ("gemini-5h", "Gemini 3.7 Flash (High)")
        ]
        
        for mapping in mappings {
            if cleaned.contains(mapping.pattern) {
                return mapping.modelName
            }
        }
        
        let knownModelNames = [
            "Gemini 3.8 Flash (Low)",
            "Gemini 3.8 Flash (Medium)",
            "Gemini 3.8 Flash (High)",
            "Gemini 3.8 Flash Cyber",
            "Gemini 3.7 Flash (Low)",
            "Gemini 3.7 Flash (Medium)",
            "Gemini 3.7 Flash (High)",
            "Gemini 3.6 Flash (Low)",
            "Gemini 3.6 Flash (Medium)",
            "Gemini 3.6 Flash (High)",
            "Gemini 3.5 Flash (Low)",
            "Gemini 3.5 Flash (Medium)",
            "Gemini 3.5 Flash (High)",
            "Gemini 3.1 Pro (Low)",
            "Gemini 3.1 Pro (High)",
            "Claude Sonnet 4.6 (Thinking)",
            "Claude Opus 4.6 (Thinking)",
            "GPT-OSS-120B"
        ]
        for knownName in knownModelNames {
            if cleaned.contains(knownName.lowercased()) {
                return knownName
            }
        }
        
        return nil
    }
    
    private static func enforceDateModelValidity(modelName: String, date: Date, aug2026: Date, sep2026: Date) -> String {
        if date < aug2026 {
            if modelName.contains("3.7") || modelName.contains("3.8") {
                return "Gemini 3.6 Flash (High)"
            }
        } else if date < sep2026 {
            if modelName.contains("3.8") {
                return "Gemini 3.7 Flash (High)"
            }
        }
        return modelName
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
