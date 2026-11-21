//
//  AgyStatsService.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import Foundation
import SQLite3

nonisolated public enum AgyStatsService {
    /// Vertex AI 'us' regional multiplier (1.10x) applied exclusively to GCP direct-billed usage.
    public static let gcpRegionalMultiplier: Double = ModelCostInfo.gcpRegionalMultiplier
    
    private struct HistoryLine: Decodable {
        let display: String
        let timestamp: Int64
        let workspace: String
        let conversationId: String?
        let type: String?
    }
    
    private struct DbGeneration: Codable, Sendable {
        let idx: Int
        let size: Int
        let timestamp: Date?
        let modelName: String?
        let inputTokens: Int?
        let outputTokens: Int?
        let cachedInputTokens: Int?
        let isGcpOrigin: Bool
        let isExplicitConsumer: Bool
        let hasProtobufMetadata: Bool
    }
    
    private struct DbConversationData: Codable, Sendable {
        let conversationId: String
        let startTime: Date?
        let generations: [DbGeneration]
    }
    
    // In-memory + persistent disk caches for fast cold and warm refreshes
    private struct ConversationCacheEntry: Codable, Sendable {
        let modificationDate: Date
        let fileSize: Int64
        let walModificationDate: Date?
        let walFileSize: Int64?
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
        let newestSize: Int64?
        let defaultProject: String?
        let cachedAt: Date
        let transitions: [AuthTransition]
    }
    
    private struct LogFileEntry: Codable, Sendable {
        let modDate: Date
        let size: Int64
        let transitions: [AuthTransition]
    }

    private struct GcpConsumerLogEntry: Codable, Sendable {
        let modDate: Date
        let size: Int64
        let consumerConvIds: [String]
    }
    
    private struct PrecomputedAuthState {
        let timestamp: Date
        let state: AuthStateAtDate
    }
    
    private static var conversationCache: [String: ConversationCacheEntry] = [:]
    private static let conversationCacheLock = NSLock()
    
    private static var historyCache: [String: HistoryCacheEntry] = [:]
    private static let historyCacheLock = NSLock()
    
    private static var authCache: AuthCacheEntry? = nil
    private static let authCacheLock = NSLock()
    
    private static var logFileCache: [String: LogFileEntry] = [:]
    private static let logFileCacheLock = NSLock()

    private static var gcpConsumerLogCache: [String: GcpConsumerLogEntry] = [:]
    private static let gcpConsumerLogCacheLock = NSLock()
    
    public struct ModelTransition: Codable, Sendable {
        public let timestamp: Date
        public let modelName: String
        
        public init(timestamp: Date, modelName: String) {
            self.timestamp = timestamp
            self.modelName = modelName
        }
    }
    
    private struct ModelLogFileEntry: Codable, Sendable {
        let modDate: Date
        let size: Int64
        let transitions: [ModelTransition]
    }
    
    private struct ModelTransitionCacheEntry {
        let fileCount: Int
        let newestName: String
        let newestModDate: Date?
        let cachedAt: Date
        let transitions: [ModelTransition]
    }
    
    private static var modelTransitionCache: ModelTransitionCacheEntry? = nil
    private static let modelTransitionCacheLock = NSLock()
    private static var modelLogFileCache: [String: ModelLogFileEntry] = [:]
    private static let modelLogFileCacheLock = NSLock()

    // MARK: - Persistent Binary Disk Cache (Eliminates Multi-Second Cold Launches)

    private struct PersistentParseCache: Codable {
        let schemaVersion: Int
        let conversations: [String: ConversationCacheEntry]
        let authLogs: [String: LogFileEntry]
        let modelLogs: [String: ModelLogFileEntry]
        let gcpConsumerLogs: [String: GcpConsumerLogEntry]
    }

    private static let parseCacheSchemaVersion = 3
    private static let isRunningTests: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
        || NSClassFromString("XCTestCase") != nil
    private static let diskCacheQueue = DispatchQueue(label: "com.antigravity.agy-usage-stats.diskcache", qos: .utility)
    private static let diskCacheStateLock = NSLock()
    private static var diskCacheLoaded = false
    private static var diskCacheSaveScheduled = false

    private static var diskCacheFileURL: URL? {
        guard !isRunningTests else { return nil }
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return cachesDir
            .appendingPathComponent("com.sameerbajaj.agy-usage-stats", isDirectory: true)
            .appendingPathComponent("parse-cache-v\(parseCacheSchemaVersion).plist")
    }

    private static func ensureDiskCacheLoaded() {
        guard !isRunningTests else { return }
        diskCacheStateLock.lock()
        if diskCacheLoaded {
            diskCacheStateLock.unlock()
            return
        }
        diskCacheLoaded = true
        diskCacheStateLock.unlock()

        guard let url = diskCacheFileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? PropertyListDecoder().decode(PersistentParseCache.self, from: data),
              decoded.schemaVersion == parseCacheSchemaVersion else {
            return
        }

        conversationCacheLock.lock()
        for (k, v) in decoded.conversations where conversationCache[k] == nil {
            conversationCache[k] = v
        }
        conversationCacheLock.unlock()

        logFileCacheLock.lock()
        for (k, v) in decoded.authLogs where logFileCache[k] == nil {
            logFileCache[k] = v
        }
        logFileCacheLock.unlock()

        modelLogFileCacheLock.lock()
        for (k, v) in decoded.modelLogs where modelLogFileCache[k] == nil {
            modelLogFileCache[k] = v
        }
        modelLogFileCacheLock.unlock()

        gcpConsumerLogCacheLock.lock()
        for (k, v) in decoded.gcpConsumerLogs where gcpConsumerLogCache[k] == nil {
            gcpConsumerLogCache[k] = v
        }
        gcpConsumerLogCacheLock.unlock()
    }

    private static func scheduleDiskCacheSave() {
        guard !isRunningTests, let url = diskCacheFileURL else { return }
        diskCacheStateLock.lock()
        if diskCacheSaveScheduled {
            diskCacheStateLock.unlock()
            return
        }
        diskCacheSaveScheduled = true
        diskCacheStateLock.unlock()

        diskCacheQueue.asyncAfter(deadline: .now() + 0.5) {
            diskCacheStateLock.lock()
            diskCacheSaveScheduled = false
            diskCacheStateLock.unlock()

            conversationCacheLock.lock()
            let convs = conversationCache
            conversationCacheLock.unlock()

            logFileCacheLock.lock()
            let authLogs = logFileCache
            logFileCacheLock.unlock()

            modelLogFileCacheLock.lock()
            let modelLogs = modelLogFileCache
            modelLogFileCacheLock.unlock()

            gcpConsumerLogCacheLock.lock()
            let gcpLogs = gcpConsumerLogCache
            gcpConsumerLogCacheLock.unlock()

            let payload = PersistentParseCache(
                schemaVersion: parseCacheSchemaVersion,
                conversations: convs,
                authLogs: authLogs,
                modelLogs: modelLogs,
                gcpConsumerLogs: gcpLogs
            )

            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            guard let data = try? encoder.encode(payload) else { return }
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic])
        }
    }
    
    public struct DirectoryContentSignature: Equatable, Sendable {
        public let latestModDate: Date
        public let totalSize: Int64
        public let fileCount: Int
        
        public init(latestModDate: Date = Date.distantPast, totalSize: Int64 = 0, fileCount: Int = 0) {
            self.latestModDate = latestModDate
            self.totalSize = totalSize
            self.fileCount = fileCount
        }
    }
    
    private struct StatsCacheEntry {
        let cliDir: String
        let gcpCliDir: String
        let settings: AgySettings
        let startOfToday: Date
        let historyModDate: Date
        let historySize: Int64
        let conversationsDirModDate: Date
        let conversationsSig: DirectoryContentSignature
        let gcpHistoryModDate: Date
        let gcpHistorySize: Int64
        let gcpConversationsDirModDate: Date
        let gcpConversationsSig: DirectoryContentSignature
        let activeConsumerEmail: String?
        let oauthTokenModDate: Date
        let stats: AgyUsageStats
    }
    
    private static var statsCache: StatsCacheEntry? = nil
    private static let statsCacheLock = NSLock()

    private struct ConsumerEmailCacheEntry: Sendable {
        let expandedCliDir: String
        let oauthTokenModDate: Date
        let resolvedCliLogPath: String?
        let cliLogModDate: Date
        let cliLogSize: Int64
        let logDirModDate: Date
        let email: String?
    }

    private static var consumerEmailCache: [String: ConsumerEmailCacheEntry] = [:]
    private static let consumerEmailCacheLock = NSLock()
    
    public static func clearCaches() {
        conversationCacheLock.lock()
        conversationCache.removeAll()
        conversationCacheLock.unlock()
        
        historyCacheLock.lock()
        historyCache.removeAll()
        historyCacheLock.unlock()
        
        authCacheLock.lock()
        authCache = nil
        authCacheLock.unlock()
        
        logFileCacheLock.lock()
        logFileCache.removeAll()
        logFileCacheLock.unlock()

        gcpConsumerLogCacheLock.lock()
        gcpConsumerLogCache.removeAll()
        gcpConsumerLogCacheLock.unlock()

        modelTransitionCacheLock.lock()
        modelTransitionCache = nil
        modelTransitionCacheLock.unlock()

        modelLogFileCacheLock.lock()
        modelLogFileCache.removeAll()
        modelLogFileCacheLock.unlock()
        
        statsCacheLock.lock()
        statsCache = nil
        statsCacheLock.unlock()

        consumerEmailCacheLock.lock()
        consumerEmailCache.removeAll()
        consumerEmailCacheLock.unlock()
        
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
    
    public static func directoryContentSignature(atPath dirPath: String) -> DirectoryContentSignature {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: dirPath, isDirectory: true)
        
        guard let urls = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return DirectoryContentSignature(latestModDate: .distantPast, totalSize: 0, fileCount: 0)
        }
        
        var maxModDate = Date.distantPast
        var totalSize: Int64 = 0
        var dbFiles: [(url: URL, modDate: Date)] = []
        var knownSizes: [String: Int64] = [:]
        knownSizes.reserveCapacity(urls.count)
        
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
                continue
            }
            let modDate = values.contentModificationDate ?? Date.distantPast
            if modDate > maxModDate {
                maxModDate = modDate
            }
            let size = Int64(values.fileSize ?? 0)
            totalSize += size
            knownSizes[url.path] = size
            
            if url.pathExtension == "db" {
                dbFiles.append((url: url, modDate: modDate))
            }
        }
        
        // Stat -wal only for the top 5 most recently modified .db files if any exist
        if !dbFiles.isEmpty {
            dbFiles.sort { $0.modDate > $1.modDate }
            let top5 = dbFiles.prefix(5)
            for dbFile in top5 {
                let walPath = dbFile.url.path + "-wal"
                if let walAttrs = try? fm.attributesOfItem(atPath: walPath) {
                    if let walModDate = walAttrs[.modificationDate] as? Date, walModDate > maxModDate {
                        maxModDate = walModDate
                    }
                    if let walSize = (walAttrs[.size] as? NSNumber)?.int64Value {
                        if let oldSize = knownSizes[walPath] {
                            if walSize > oldSize {
                                totalSize += (walSize - oldSize)
                            }
                        } else {
                            totalSize += walSize
                        }
                    }
                }
            }
        }
        
        return DirectoryContentSignature(latestModDate: maxModDate, totalSize: totalSize, fileCount: urls.count)
    }
    
    public static func loadStats(cliDir: String, gcpCliDir: String? = nil, existingQuota: AgyQuotaInfo? = nil) async -> (AgyUsageStats, AgySettings) {
        return await Task.detached(priority: .userInitiated) {
            let expandedDir = cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
            let historyPath = (expandedDir as NSString).appendingPathComponent("history.jsonl")
            let settingsPath = (expandedDir as NSString).appendingPathComponent("settings.json")
            let conversationsDir = (expandedDir as NSString).appendingPathComponent("conversations")
            let logDir = (expandedDir as NSString).appendingPathComponent("log")
            
            let resolvedGcpCliDir = (gcpCliDir ?? "\(NSHomeDirectory())/.agy-gcp-home/.gemini/antigravity-cli").replacingOccurrences(of: "~", with: NSHomeDirectory())
            let gcpHistoryPath = (resolvedGcpCliDir as NSString).appendingPathComponent("history.jsonl")
            let gcpConversationsDir = (resolvedGcpCliDir as NSString).appendingPathComponent("conversations")
            
            let fm = FileManager.default
            let calendar = Calendar.current
            let now = Date()
            let startOfToday = calendar.startOfDay(for: now)
            
            let histAttrs = try? fm.attributesOfItem(atPath: historyPath)
            let histMod = histAttrs?[.modificationDate] as? Date ?? Date.distantPast
            let histSize = (histAttrs?[.size] as? NSNumber)?.int64Value ?? 0
            
            let convDirAttrs = try? fm.attributesOfItem(atPath: conversationsDir)
            let convDirMod = convDirAttrs?[.modificationDate] as? Date ?? Date.distantPast
            let convSig = directoryContentSignature(atPath: conversationsDir)
            
            let gcpHistAttrs = try? fm.attributesOfItem(atPath: gcpHistoryPath)
            let gcpHistMod = gcpHistAttrs?[.modificationDate] as? Date ?? Date.distantPast
            let gcpHistSize = (gcpHistAttrs?[.size] as? NSNumber)?.int64Value ?? 0
            
            let gcpConvDirAttrs = try? fm.attributesOfItem(atPath: gcpConversationsDir)
            let gcpConvDirMod = gcpConvDirAttrs?[.modificationDate] as? Date ?? Date.distantPast
            let gcpConvSig = directoryContentSignature(atPath: gcpConversationsDir)
            
            let settings = loadSettings(at: settingsPath)
            let activeConsumerEmail = resolveActiveConsumerEmail(cliDir: expandedDir)
            
            let oauthTokenPath = (expandedDir as NSString).appendingPathComponent("antigravity-oauth-token")
            let oauthTokenModDate = (try? fm.attributesOfItem(atPath: oauthTokenPath))?[.modificationDate] as? Date ?? Date.distantPast
            
            // Fast cache check: use synchronous withLock so NSLock can NEVER span a Swift async suspension point
            let cachedHit: AgyUsageStats? = statsCacheLock.withLock {
                guard let cached = statsCache,
                      cached.cliDir == expandedDir,
                      cached.gcpCliDir == resolvedGcpCliDir,
                      cached.settings == settings,
                      cached.startOfToday == startOfToday,
                      cached.historyModDate == histMod,
                      cached.historySize == histSize,
                      cached.conversationsDirModDate == convDirMod,
                      cached.conversationsSig == convSig,
                      cached.gcpHistoryModDate == gcpHistMod,
                      cached.gcpHistorySize == gcpHistSize,
                      cached.gcpConversationsDirModDate == gcpConvDirMod,
                      cached.gcpConversationsSig == gcpConvSig,
                      cached.activeConsumerEmail == activeConsumerEmail,
                      cached.oauthTokenModDate == oauthTokenModDate else {
                    return nil
                }
                return cached.stats
            }
            if var cachedStats = cachedHit {
                // Fetch fresh quota without blocking UI if already cached
                if let quota = await AgyQuotaService.fetchQuota(expectedEmail: activeConsumerEmail) {
                    cachedStats.quotaInfo = quota
                } else if cachedStats.quotaInfo == nil {
                    cachedStats.quotaInfo = existingQuota
                }
                return (cachedStats, settings)
            }
            
            let tStart = ContinuousClock.now
            // Hydrate persistent disk parse cache once on cold launch (sub-15ms vs multi-second SQLite/log scan)
            ensureDiskCacheLoaded()
            // Kick off quota fetch in background concurrently
            async let quotaTask = AgyQuotaService.fetchQuota(expectedEmail: activeConsumerEmail)
            
            // Load Settings & Auth Transitions
            let tokenAuth = loadActiveAuthMethod(cliDir: expandedDir)
            let currentIsGcp = !tokenAuth.explicitConsumer && (tokenAuth.isGcp || (settings.gcp?.project != nil && !(settings.gcp?.project?.isEmpty ?? true) && tokenAuth.email == nil))
            let (authTransitions, authHadMiss) = loadAuthTransitionsWithMissFlag(logDir: logDir, defaultProject: settings.gcp?.project)
            let (modelTransitions, modelHadMiss) = loadModelTransitionsWithMissFlag(logDir: logDir)
            
            let tHist = ContinuousClock.now
            // Load History Lines
            let (loadedQueries, workspaces, lastQuery, _) = loadHistory(at: historyPath)
            
            // Ingest GCP box history if available in ~/.agy-gcp-home
            let gcpAuth = loadActiveAuthMethod(cliDir: resolvedGcpCliDir)
            let resolvedGcpProject = gcpAuth.project ?? settings.gcp?.project ?? "clawdbot-485304"
            let (gcpConsumerConvIds, gcpLogHadMiss) = loadGcpBoxConsumerConvIdsWithMissFlag(gcpCliDir: resolvedGcpCliDir)
            
            var combinedLoadedQueries = loadedQueries
            var combinedWorkspaces = workspaces
            var combinedLastQuery = lastQuery
            
            if expandedDir != resolvedGcpCliDir && FileManager.default.fileExists(atPath: gcpHistoryPath) {
                let (gcpLoaded, gcpWs, gcpLast, _) = loadHistory(at: gcpHistoryPath)
                if !gcpLoaded.isEmpty {
                    let gcpMapped = gcpLoaded.map { q -> QueryEntry in
                        var copy = q
                        let isConsumer = q.conversationId != nil && gcpConsumerConvIds.contains(q.conversationId!)
                        if isConsumer {
                            copy.isGcp = false
                            copy.gcpProject = nil
                            copy.accountEmail = activeConsumerEmail ?? "sameerbajaj24@gmail.com"
                        } else {
                            copy.isGcp = true
                            copy.gcpProject = resolvedGcpProject
                            copy.accountEmail = nil
                        }
                        if copy.modelName == nil {
                            copy.modelName = "Gemini 4 Argon (High)"
                        }
                        return copy
                    }
                    combinedLoadedQueries.append(contentsOf: gcpMapped)
                    // Keep newest-first (descending) order consistent with loadHistory()
                    combinedLoadedQueries.sort { $0.timestamp > $1.timestamp }
                    if let gcpLast, combinedLastQuery == nil || gcpLast > combinedLastQuery! {
                        combinedLastQuery = gcpLast
                    }
                    for ws in gcpWs {
                        if let idx = combinedWorkspaces.firstIndex(where: { $0.path == ws.path }) {
                            var existing = combinedWorkspaces[idx]
                            existing.queryCount += ws.queryCount
                            if ws.lastActiveAt > existing.lastActiveAt {
                                existing.lastActiveAt = ws.lastActiveAt
                            }
                            combinedWorkspaces[idx] = existing
                        } else {
                            combinedWorkspaces.append(ws)
                        }
                    }
                }
            }
            
            // Date-aware fallback thresholds: Gemini 3.7 Flash on August 1, 2026; Gemini 3.8 Flash on September 2, 2026
            let aug2026 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1)) ?? Date.distantFuture
            let sep2026 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 2)) ?? Date.distantFuture
            
            let queries = combinedLoadedQueries.map { q -> QueryEntry in
                var copy = q
                if copy.modelName == nil {
                    let fallback: String
                    if q.timestamp >= sep2026 {
                        fallback = settings.model ?? "Gemini 3.8 Flash (High)"
                    } else if q.timestamp >= aug2026 {
                        fallback = "Gemini 3.7 Flash (High)"
                    } else {
                        fallback = "Gemini 3.6 Flash (High)"
                    }
                    copy.modelName = fallback
                }
                return copy
            }
            
            let tDb = ContinuousClock.now
            // Load all SQLite conversation databases in a single bounded-concurrency pass
            let (loadedDbConversations, loadedToolStats, consumerDbMiss) = await loadConversationsAndToolStats(conversationsDir: conversationsDir)
            var allDbConversations = loadedDbConversations
            var toolStats = loadedToolStats
            var gcpDbMiss = false
            
            if expandedDir != resolvedGcpCliDir && FileManager.default.fileExists(atPath: gcpConversationsDir) {
                let (gcpDb, gcpTools, gcpMiss) = await loadConversationsAndToolStats(conversationsDir: gcpConversationsDir, isGcpOrigin: true)
                gcpDbMiss = gcpMiss
                for (cid, conv) in gcpDb {
                    let isConsumer = gcpConsumerConvIds.contains(cid)
                    if isConsumer {
                        let remappedGens = conv.generations.map { g in
                            DbGeneration(
                                idx: g.idx,
                                size: g.size,
                                timestamp: g.timestamp,
                                modelName: g.modelName,
                                inputTokens: g.inputTokens,
                                outputTokens: g.outputTokens,
                                cachedInputTokens: g.cachedInputTokens,
                                isGcpOrigin: false,
                                isExplicitConsumer: true,
                                hasProtobufMetadata: g.hasProtobufMetadata
                            )
                        }
                        allDbConversations[cid] = DbConversationData(
                            conversationId: conv.conversationId,
                            startTime: conv.startTime,
                            generations: remappedGens
                        )
                    } else {
                        allDbConversations[cid] = conv
                    }
                }
                for tool in gcpTools {
                    if let idx = toolStats.firstIndex(where: { $0.toolName == tool.toolName }) {
                        var existing = toolStats[idx]
                        existing.count += tool.count
                        toolStats[idx] = existing
                    } else {
                        toolStats.append(tool)
                    }
                }
            }
            if consumerDbMiss || gcpDbMiss || authHadMiss || modelHadMiss || gcpLogHadMiss {
                scheduleDiskCacheSave()
            }
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
            var queryStartsByConv: [String: [Double]] = [:]
            for (i, cid) in resolvedConvIds.enumerated() {
                if let cid = cid {
                    let s = floor(queries[i].timestamp.timeIntervalSince1970)
                    queryStartsByConv[cid, default: []].append(s)
                }
            }
            for (cid, arr) in queryStartsByConv {
                queryStartsByConv[cid] = arr.sorted()
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
            let precomputedInitialAuthTimestamps: [Double] = precomputedInitialAuthStates.map { $0.timestamp.timeIntervalSince1970 }
            func authForDateInitial(_ date: Date) -> AuthStateAtDate {
                guard !precomputedInitialAuthTimestamps.isEmpty else { return initialDefaultAuthState }
                let target = date.timeIntervalSince1970
                // Find last index where timestamp <= target
                var low = 0
                var high = precomputedInitialAuthTimestamps.count
                while low < high {
                    let mid = (low + high) / 2
                    if precomputedInitialAuthTimestamps[mid] <= target {
                        low = mid + 1
                    } else {
                        high = mid
                    }
                }
                let idx = low - 1
                if idx >= 0 {
                    return precomputedInitialAuthStates[idx].state
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
                    let startSec = floor(q.timestamp.timeIntervalSince1970)
                    let start = Date(timeIntervalSince1970: startSec)
                    
                    // Find the next chronological query in the same conversation via binary search (max 30 mins)
                    var endSec = startSec + 1800.0
                    if let convStarts = queryStartsByConv[conversationId] {
                        let nextIdx = binarySearchLowerBound(convStarts, target: startSec + 0.0001)
                        if nextIdx < convStarts.count {
                            endSec = min(endSec, convStarts[nextIdx])
                        }
                    }
                    let end = Date(timeIntervalSince1970: endSec)
                    
                    // Accumulate primary conversation + subagent generations directly without intermediate array allocations
                    var turnCount = 0
                    var totalOutputBytes = 0
                    var totalInTokens = 0
                    var totalOutTokens = 0
                    var totalCachedTokens = 0
                    var lastTurnModel: String? = nil
                    
                    for gen in convData.generations {
                        guard let gTs = gen.timestamp else { continue }
                        if gTs >= start && gTs < end {
                            turnCount += 1
                            totalOutputBytes += gen.size
                            if let inp = gen.inputTokens { totalInTokens += inp }
                            if let out = gen.outputTokens { totalOutTokens += out }
                            if let c = gen.cachedInputTokens { totalCachedTokens += c }
                            if let m = gen.modelName { lastTurnModel = m }
                        }
                    }
                    
                    // Subagent conversations spawned during this query window via binary search
                    let lowIdx = binarySearchLowerBound(subagentStarts, target: startSec)
                    let highIdx = binarySearchLowerBound(subagentStarts, target: endSec)
                    
                    if lowIdx < highIdx {
                        for k in lowIdx..<highIdx {
                            let cand = subagentCandidates[k]
                            if cand.id != conversationId {
                                for g in cand.gens {
                                    turnCount += 1
                                    totalOutputBytes += g.size
                                    if let inp = g.inputTokens { totalInTokens += inp }
                                    if let out = g.outputTokens { totalOutTokens += out }
                                    if let c = g.cachedInputTokens { totalCachedTokens += c }
                                    if let m = g.modelName { lastTurnModel = m }
                                }
                            }
                        }
                    }
                    
                    if turnCount > 0 {
                        newQ.conversationMeta = ConversationDbMeta(
                            llmCalls: turnCount,
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
                        
                        if let overrideModel = findModelOverride(at: q.timestamp, in: modelTransitions, calendar: calendar) {
                            newQ.modelName = enforceDateModelValidity(modelName: overrideModel, date: q.timestamp, aug2026: aug2026, sep2026: sep2026)
                        } else {
                            // Fallback: Use the latest model used prior to this query
                            var lastPriorModel: String? = nil
                            var firstPostModel: String? = nil
                            for gen in convData.generations {
                                guard let m = gen.modelName else { continue }
                                if firstPostModel == nil { firstPostModel = m }
                                if let gTs = gen.timestamp, gTs < start {
                                    lastPriorModel = m
                                }
                            }
                            if let lastPriorModel {
                                newQ.modelName = enforceDateModelValidity(modelName: lastPriorModel, date: q.timestamp, aug2026: aug2026, sep2026: sep2026)
                            } else if let firstPostModel {
                                newQ.modelName = enforceDateModelValidity(modelName: firstPostModel, date: q.timestamp, aug2026: aug2026, sep2026: sep2026)
                            } else {
                                newQ.modelName = q.modelName ?? queryDefaultModel
                            }
                        }
                    }
                } else {
                    if let overrideModel = findModelOverride(at: q.timestamp, in: modelTransitions, calendar: calendar) {
                        newQ.modelName = enforceDateModelValidity(modelName: overrideModel, date: q.timestamp, aug2026: aug2026, sep2026: sep2026)
                    } else if newQ.modelName == nil {
                        newQ.modelName = queryDefaultModel
                    }
                }
                let authState = authForDateInitial(q.timestamp)
                let isConsumerConv = (resolvedConvId != nil && gcpConsumerConvIds.contains(resolvedConvId!)) || (q.conversationId != nil && gcpConsumerConvIds.contains(q.conversationId!))
                let isGcp = !isConsumerConv && (q.isGcp || authState.isGcp)
                newQ.isGcp = isGcp
                newQ.gcpProject = isGcp ? (q.gcpProject ?? authState.gcpProject ?? "clawdbot-485304") : nil
                newQ.accountEmail = isGcp ? nil : (authState.email ?? activeConsumerEmail ?? "sameerbajaj24@gmail.com")
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
            let fetchedQuota = await quotaTask
            print("TIME: quotaInfo await = \(tQuota.duration(to: .now))")
            
            let previousCachedQuota = statsCacheLock.withLock { statsCache?.stats.quotaInfo }
            let safePreviousQuota: AgyQuotaInfo? = {
                guard let prev = previousCachedQuota else { return nil }
                if let expected = activeConsumerEmail?.lowercased(),
                   let prevEmail = prev.email?.lowercased(),
                   prevEmail != expected {
                    return nil
                }
                return prev
            }()
            let quotaInfo = fetchedQuota ?? existingQuota ?? safePreviousQuota
            
            if let quotaInfo = quotaInfo {
                print("AgyStatsService: Resolved quota: plan = \(quotaInfo.plan ?? "nil"), email = \(quotaInfo.email ?? "nil"), groups count = \(quotaInfo.groups.count)")
            } else {
                print("AgyStatsService: Resolved quota: NONE")
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
            var gcpSpendEntries: [GcpSpendEntry] = []
            var quotaTotalCost = 0.0
            var quotaTodayCost = 0.0
            var quotaWeekCost = 0.0
            
            var accountCostTotals: [String: Double] = [:]
            var accountTodayTotals: [String: Double] = [:]
            var accountWeeklyTotals: [String: Double] = [:]
            var accountQueryTodayTotals: [String: Int] = [:]
            var accountQueryWeeklyTotals: [String: Int] = [:]
            var accountQueryTotals: [String: Int] = [:]
            var consumerSpendEntries: [AccountSpendEntry] = []
            
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
            
            let precomputedAuthTimestamps: [Double] = precomputedAuthStates.map { $0.timestamp.timeIntervalSince1970 }
            func authForDate(_ date: Date) -> AuthStateAtDate {
                guard !precomputedAuthTimestamps.isEmpty else { return defaultAuthState }
                let target = date.timeIntervalSince1970
                var low = 0
                var high = precomputedAuthTimestamps.count
                while low < high {
                    let mid = (low + high) / 2
                    if precomputedAuthTimestamps[mid] <= target {
                        low = mid + 1
                    } else {
                        high = mid
                    }
                }
                let idx = low - 1
                if idx >= 0 {
                    return precomputedAuthStates[idx].state
                }
                return defaultAuthState
            }
            
            let cachedKnownModels = ModelCostInfo.knownModels(at: now)
            let sepFallbackModel = cachedKnownModels.first(where: { $0.name == "Gemini 3.8 Flash (High)" })
                ?? cachedKnownModels.first(where: { $0.name == "Gemini 3.7 Flash (High)" })
                ?? cachedKnownModels[0]
            let preSepFallbackModel = cachedKnownModels.first(where: { $0.name == "Gemini 3.7 Flash (High)" }) ?? sepFallbackModel

            var modelCache: [String: ModelCostInfo] = [:]
            func resolveModel(name: String, fallback: ModelCostInfo, at date: Date? = nil) -> ModelCostInfo {
                if let cached = modelCache[name] {
                    return cached
                }
                let cleaned = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let model = cachedKnownModels.first(where: {
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
                var accountModelBreakdown: [String: [String: Double]] = [:]
                var accountTokenBreakdown: [String: Int] = [:]
                var gcpModelBreakdown: [String: Double] = [:]
                var quotaModelBreakdown: [String: Double] = [:]
                var gcpInputTokens: Int = 0
                var gcpOutputTokens: Int = 0
                var quotaInputTokens: Int = 0
                var quotaOutputTokens: Int = 0
                var gcpQueryCount: Int = 0
                var quotaQueryCount: Int = 0
                
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
                        accountQueryBreakdown: accountQueryBreakdown,
                        accountModelBreakdown: accountModelBreakdown,
                        accountTokenBreakdown: accountTokenBreakdown,
                        gcpModelBreakdown: gcpModelBreakdown,
                        quotaModelBreakdown: quotaModelBreakdown,
                        gcpInputTokens: gcpInputTokens,
                        gcpOutputTokens: gcpOutputTokens,
                        quotaInputTokens: quotaInputTokens,
                        quotaOutputTokens: quotaOutputTokens,
                        gcpQueryCount: gcpQueryCount,
                        quotaQueryCount: quotaQueryCount
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
                let isGcp = q.isGcp
                let accName = isGcp ? (q.gcpProject != nil ? "GCP (\(q.gcpProject!))" : authState.accountDisplayName) : (q.accountEmail ?? authState.accountDisplayName)
                
                accountQueryTotals[accName, default: 0] += 1
                if q.timestamp >= startOfToday {
                    accountQueryTodayTotals[accName, default: 0] += 1
                }
                if q.timestamp >= sevenDaysAgo {
                    accountQueryWeeklyTotals[accName, default: 0] += 1
                }

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
                if isGcp {
                    dayBucket.gcpQueryCount += 1
                } else {
                    dayBucket.quotaQueryCount += 1
                }
                if let mName = q.modelName {
                    dayBucket.modelQueryBreakdown[mName, default: 0] += 1
                }
                
                // Fallback only for historical days with no SQLite DB files (e.g. May/June 2026 prior to SQLite storage)
                var fallbackResult: (modelName: String, inTokens: Int, outTokens: Int, cost: Double)? = nil
                if !daysWithDbGens.contains(dayKey) {
                    let name = q.modelName ?? "Gemini 3.6 Flash (High)"
                    let model = resolveModel(name: name, fallback: sepFallbackModel, at: q.timestamp)
                    
                    let (inTokens, outTokens, cost) = model.estimateTokensAndCost(
                        for: q,
                        regionalMultiplier: isGcp ? Self.gcpRegionalMultiplier : 1.0
                    )
                    if cost > 0 {
                        fallbackResult = (model.name, inTokens, outTokens, cost)
                        dayBucket.totalCost += cost
                        dayBucket.inputTokens += inTokens
                        dayBucket.outputTokens += outTokens
                        dayBucket.modelBreakdown[model.name, default: 0.0] += cost
                        dayBucket.accountCostBreakdown[accName, default: 0.0] += cost
                        dayBucket.accountModelBreakdown[accName, default: [:]][model.name, default: 0.0] += cost
                        dayBucket.accountTokenBreakdown[accName, default: 0] += (inTokens + outTokens)
                        totalCost += cost
                        accountCostTotals[accName, default: 0.0] += cost
                        if isGcp {
                            dayBucket.gcpCost += cost
                            dayBucket.gcpInputTokens += inTokens
                            dayBucket.gcpOutputTokens += outTokens
                            dayBucket.gcpModelBreakdown[model.name, default: 0.0] += cost
                            gcpTotalCost += cost
                            gcpSpendEntries.append(GcpSpendEntry(timestamp: q.timestamp.timeIntervalSince1970, cost: cost))
                            if q.timestamp >= startOfToday { gcpTodayCost += cost }
                            if q.timestamp >= sevenDaysAgo { gcpWeekCost += cost }
                        } else {
                            dayBucket.quotaCost += cost
                            dayBucket.quotaInputTokens += inTokens
                            dayBucket.quotaOutputTokens += outTokens
                            dayBucket.quotaModelBreakdown[model.name, default: 0.0] += cost
                            quotaTotalCost += cost
                            consumerSpendEntries.append(AccountSpendEntry(email: accName.lowercased(), timestamp: q.timestamp.timeIntervalSince1970, cost: cost))
                            if q.timestamp >= startOfToday { quotaTodayCost += cost }
                            if q.timestamp >= sevenDaysAgo { quotaWeekCost += cost }
                        }
                        if q.timestamp >= startOfToday {
                            todayCost += cost
                            accountTodayTotals[accName, default: 0.0] += cost
                        }
                        if q.timestamp >= sevenDaysAgo {
                            weekCost += cost
                            accountWeeklyTotals[accName, default: 0.0] += cost
                        }
                        modelDist[model.name, default: 0] += 1
                    }
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
                if let fb = fallbackResult {
                    monthBucket.totalCost += fb.cost
                    monthBucket.inputTokens += fb.inTokens
                    monthBucket.outputTokens += fb.outTokens
                    monthBucket.modelBreakdown[fb.modelName, default: 0.0] += fb.cost
                    monthBucket.accountCostBreakdown[accName, default: 0.0] += fb.cost
                    if isGcp {
                        monthBucket.gcpCost += fb.cost
                    } else {
                        monthBucket.quotaCost += fb.cost
                    }
                }
            }
            
            for gen in allGenerations {
                let genDate = gen.timestamp ?? startOfToday
                
                let defaultModelForDate: String
                if genDate >= sep2026 {
                    defaultModelForDate = gen.isGcpOrigin ? "Gemini 4 Argon (High)" : (settings.model ?? "Gemini 3.8 Flash (High)")
                } else if genDate >= aug2026 {
                    defaultModelForDate = "Gemini 3.7 Flash (High)"
                } else {
                    defaultModelForDate = "Gemini 3.6 Flash (High)"
                }
                
                let rawName = gen.modelName ?? defaultModelForDate
                let validName = enforceDateModelValidity(modelName: rawName, date: genDate, aug2026: aug2026, sep2026: sep2026)
                let fallbackModel = genDate >= sep2026 ? sepFallbackModel : preSepFallbackModel
                let model = resolveModel(name: validName, fallback: fallbackModel, at: genDate)
                
                let authState = authForDate(genDate)
                let isGcp = !gen.isExplicitConsumer && (gen.isGcpOrigin || authState.isGcp)
                let accName = isGcp ? (gen.isGcpOrigin ? "GCP (\(resolvedGcpProject))" : authState.accountDisplayName) : (authState.email ?? activeConsumerEmail ?? quotaInfo?.email ?? "sameerbajaj24@gmail.com")
                let regionalMultiplier = isGcp ? Self.gcpRegionalMultiplier : 1.0

                let pTokens = gen.inputTokens ?? 0
                let cTokens = gen.cachedInputTokens ?? 0
                let oTokens = gen.outputTokens ?? 0
                
                let baseCost: Double
                let inTokens: Int
                let outTokens: Int
                
                if pTokens > 0 || cTokens > 0 || oTokens > 0 {
                    let promptCost = (Double(pTokens) / 1_000_000.0) * model.inputPricePerMillion
                    let cachedCost = (Double(cTokens) / 1_000_000.0) * model.cachedInputPricePerMillion
                    let outputCost = (Double(oTokens) / 1_000_000.0) * model.outputPricePerMillion
                    baseCost = promptCost + cachedCost + outputCost
                    inTokens = pTokens + cTokens
                    outTokens = oTokens
                } else if !gen.hasProtobufMetadata && gen.size > 0 {
                    outTokens = max(80, gen.size / 4)
                    inTokens = Int(model.tier.inputTokens * 0.35)
                    baseCost = (Double(inTokens) / 1_000_000.0) * model.inputPricePerMillion + (Double(outTokens) / 1_000_000.0) * model.outputPricePerMillion
                } else {
                    continue
                }

                let cost = baseCost * regionalMultiplier
                
                totalCost += cost
                accountCostTotals[accName, default: 0.0] += cost
                if isGcp {
                    gcpTotalCost += cost
                    gcpSpendEntries.append(GcpSpendEntry(timestamp: genDate.timeIntervalSince1970, cost: cost))
                } else {
                    quotaTotalCost += cost
                    consumerSpendEntries.append(AccountSpendEntry(email: accName.lowercased(), timestamp: genDate.timeIntervalSince1970, cost: cost))
                }
                
                if genDate >= startOfToday {
                    todayCost += cost
                    accountTodayTotals[accName, default: 0.0] += cost
                    if isGcp {
                        gcpTodayCost += cost
                    } else {
                        quotaTodayCost += cost
                    }
                }
                if genDate >= sevenDaysAgo {
                    weekCost += cost
                    accountWeeklyTotals[accName, default: 0.0] += cost
                    if isGcp {
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
                dayBucket.accountModelBreakdown[accName, default: [:]][model.name, default: 0.0] += cost
                dayBucket.accountTokenBreakdown[accName, default: 0] += (inTokens + outTokens)
                if isGcp {
                    dayBucket.gcpCost += cost
                    dayBucket.gcpInputTokens += inTokens
                    dayBucket.gcpOutputTokens += outTokens
                    dayBucket.gcpModelBreakdown[model.name, default: 0.0] += cost
                } else {
                    dayBucket.quotaCost += cost
                    dayBucket.quotaInputTokens += inTokens
                    dayBucket.quotaOutputTokens += outTokens
                    dayBucket.quotaModelBreakdown[model.name, default: 0.0] += cost
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
                if isGcp {
                    monthBucket.gcpCost += cost
                    monthBucket.gcpInputTokens += inTokens
                    monthBucket.gcpOutputTokens += outTokens
                    monthBucket.gcpModelBreakdown[model.name, default: 0.0] += cost
                } else {
                    monthBucket.quotaCost += cost
                    monthBucket.quotaInputTokens += inTokens
                    monthBucket.quotaOutputTokens += outTokens
                    monthBucket.quotaModelBreakdown[model.name, default: 0.0] += cost
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

            var discoveredByLower: [String: String] = [:]
            func registerConsumerEmail(_ candidate: String?) {
                guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !trimmed.isEmpty,
                      trimmed.contains("@"),
                      !trimmed.hasPrefix("GCP ("),
                      trimmed != "Google Cloud API",
                      trimmed != "Account Quota",
                      !AgyQuotaService.isSyntheticTestEmail(trimmed) else { return }
                let key = trimmed.lowercased()
                if discoveredByLower[key] == nil {
                    discoveredByLower[key] = trimmed
                }
            }
            for transition in authTransitions {
                registerConsumerEmail(transition.email)
            }
            registerConsumerEmail(activeConsumerEmail)
            registerConsumerEmail(quotaInfo?.email)
            for key in accountCostTotals.keys {
                registerConsumerEmail(key)
            }
            for key in accountQueryTotals.keys {
                registerConsumerEmail(key)
            }
            let discoveredConsumerEmails = discoveredByLower.values.sorted { $0.lowercased() < $1.lowercased() }
            
            let stats = AgyUsageStats(
                totalQueries: queries.count,
                queriesToday: queriesToday,
                queriesThisWeek: queriesThisWeek,
                lastQueryAt: combinedLastQuery ?? lastQuery,
                workspaces: combinedWorkspaces,
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
                gcpProject: currentIsGcp ? resolvedGcpProject : nil,
                gcpLocation: settings.gcp?.location ?? "us",
                gcpTotalCost: gcpTotalCost,
                gcpTodayCost: gcpTodayCost,
                gcpWeeklyCost: gcpWeekCost,
                gcpSpendEntries: gcpSpendEntries,
                quotaTotalCost: quotaTotalCost,
                quotaTodayCost: quotaTodayCost,
                quotaWeeklyCost: quotaWeekCost,
                availableAccounts: Array(accountCostTotals.keys).sorted(),
                accountCostTotals: accountCostTotals,
                accountTodayTotals: accountTodayTotals,
                accountWeeklyTotals: accountWeeklyTotals,
                accountQueryTodayTotals: accountQueryTodayTotals,
                accountQueryWeeklyTotals: accountQueryWeeklyTotals,
                accountQueryTotals: accountQueryTotals,
                consumerSpendEntries: consumerSpendEntries,
                discoveredConsumerEmails: discoveredConsumerEmails
            )
            
            let newStatsCacheEntry = StatsCacheEntry(
                cliDir: expandedDir,
                gcpCliDir: resolvedGcpCliDir,
                settings: settings,
                startOfToday: startOfToday,
                historyModDate: histMod,
                historySize: histSize,
                conversationsDirModDate: convDirMod,
                conversationsSig: convSig,
                gcpHistoryModDate: gcpHistMod,
                gcpHistorySize: gcpHistSize,
                gcpConversationsDirModDate: gcpConvDirMod,
                gcpConversationsSig: gcpConvSig,
                activeConsumerEmail: activeConsumerEmail,
                oauthTokenModDate: oauthTokenModDate,
                stats: stats
            )
            statsCacheLock.withLock {
                statsCache = newStatsCacheEntry
            }
            
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
    
    public struct AuthTransition: Codable, Sendable {
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
    
    private static let applyAuthRegex = try? NSRegularExpression(
        pattern: #"applyAuthResult:\s*email=([^,\s]+),\s*authMethod=(consumer|gcp)(?:,\s*quotaProject=([^\s,]*))?"#
    )
    private static let consumerOAuthRegex = try? NSRegularExpression(
        pattern: #"consumerOAuth:\s*authenticated successfully as ([^\s]+)"#
    )
    private static let oauthSuccessRegex = try? NSRegularExpression(
        pattern: #"(?:^|\]|\s)OAuth:\s*authenticated successfully as ([^\s]+)"#
    )
    private static let genericEmailRegex = try? NSRegularExpression(
        pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
    )

    private struct ParsedLogAuthEvent {
        let timestamp: Date?
        let isGcp: Bool
        let email: String?
        let project: String?
        let isConsumerOAuth: Bool
    }

    private static func cleanExtractedEmail(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:\"'()[]<>"))
        )
        guard !trimmed.isEmpty, let regex = genericEmailRegex else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              let r = Range(match.range, in: trimmed) else {
            return nil
        }
        return String(trimmed[r])
    }

    private static func extractFirstValidEmail(in line: String) -> String? {
        guard let regex = genericEmailRegex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let r = Range(match.range, in: line) else {
            return nil
        }
        return String(line[r])
    }

    private static func parseGlogTimestamp(line: String, year: Int, calendar: Calendar) -> Date? {
        guard line.count >= 14 else { return nil }
        let prefix = Array(line.prefix(21))
        guard let level = prefix.first, "IWEF".contains(level),
              prefix[5] == " ", prefix[8] == ":", prefix[11] == ":" else {
            return nil
        }
        guard let month = Int(String(prefix[1...2])), (1...12).contains(month),
              let day = Int(String(prefix[3...4])), (1...31).contains(day),
              let hour = Int(String(prefix[6...7])), (0...23).contains(hour),
              let minute = Int(String(prefix[9...10])), (0...59).contains(minute),
              let second = Int(String(prefix[12...13])), (0...60).contains(second) else {
            return nil
        }
        var nanosecond = 0
        if prefix.count > 15 && prefix[14] == "." {
            var fracDigits = ""
            for ch in prefix[15...] {
                if ch.isNumber {
                    fracDigits.append(ch)
                } else {
                    break
                }
            }
            if !fracDigits.isEmpty {
                let padded = String(fracDigits.prefix(9)).padding(toLength: 9, withPad: "0", startingAt: 0)
                nanosecond = Int(padded) ?? 0
            }
        }
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        comps.nanosecond = nanosecond
        return calendar.date(from: comps)
    }

    private static func readTailText(atPath path: String, maxBytes: Int = 262_144) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        let offset: UInt64 = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: offset)
        var data = handle.readDataToEndOfFile()
        if offset > 0, let newlineIdx = data.firstIndex(of: 0x0A) {
            let nextIdx = data.index(after: newlineIdx)
            if nextIdx <= data.endIndex {
                data = data.subdata(in: nextIdx..<data.endIndex)
            }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }

    private static func readHeadAndTailText(atPath path: String, headBytes: Int = 32_768, tailBytes: Int = 262_144) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        let fileSize = (try? handle.seekToEnd()) ?? 0
        if fileSize <= UInt64(tailBytes) {
            try? handle.seek(toOffset: 0)
            let data = handle.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        }

        try? handle.seek(toOffset: 0)
        var headData = handle.readData(ofLength: headBytes)
        if headData.count == headBytes, let lastNewline = headData.lastIndex(of: 0x0A) {
            headData = headData.subdata(in: headData.startIndex..<lastNewline)
        }
        let headText = String(data: headData, encoding: .utf8) ?? String(data: headData, encoding: .isoLatin1) ?? ""
        let headEndOffset = UInt64(headData.count)

        let desiredTailOffset = fileSize - UInt64(tailBytes)
        let tailOffset = max(headEndOffset, desiredTailOffset)
        try? handle.seek(toOffset: tailOffset)
        var tailData = handle.readDataToEndOfFile()
        if tailOffset > headEndOffset, let firstNewline = tailData.firstIndex(of: 0x0A) {
            let nextIdx = tailData.index(after: firstNewline)
            if nextIdx <= tailData.endIndex {
                tailData = tailData.subdata(in: nextIdx..<tailData.endIndex)
            }
        }
        let tailText = String(data: tailData, encoding: .utf8) ?? String(data: tailData, encoding: .isoLatin1) ?? ""

        if headText.isEmpty { return tailText }
        if tailText.isEmpty { return headText }
        return headText + "\n" + tailText
    }

    // MARK: - Fast C-Level Byte Log Scanning (Avoids 5M+ Unicode String.contains Calls)

    private static let authPrimaryNeedles: [[UInt8]] = [
        Array("applyAuthResult:".utf8),
        Array("OAuth:".utf8)
    ]

    private static let authAllNeedles: [[UInt8]] = [
        Array("applyAuthResult:".utf8),
        Array("OAuth:".utf8),
        Array("authMethod=".utf8),
        Array("gcp_setup.go".utf8),
        Array("[Auth State Transition]".utf8),
        Array("GCP setup completed".utf8),
        Array("aiplatform.".utf8)
    ]

    private static let legacyConsumerEndpointNeedle: [UInt8] = Array("daily-cloudcode-pa.googleapis.com".utf8)

    private static let modelOverrideNeedle: [UInt8] = Array("Propagating selected model override".utf8)

    private static func containsAnyNeedle(_ buf: UnsafeRawBufferPointer, needles: [[UInt8]]) -> Bool {
        guard let base = buf.baseAddress, buf.count > 0 else { return false }
        for needle in needles {
            if needle.withUnsafeBufferPointer({ nPtr -> Bool in
                guard let nBase = nPtr.baseAddress else { return false }
                return memmem(base, buf.count, nBase, nPtr.count) != nil
            }) {
                return true
            }
        }
        return false
    }

    /// Reads the relevant bytes of a log file (full up to 2MB, else 64KB head + 512KB tail) and extracts ONLY lines
    /// matching `needles` (plus up to 3 trailing lines after any match to preserve `linesSinceGcpApplyAuth` pairing).
    private static func extractMatchingLogLines(
        atPath path: String,
        fileSize: Int64,
        needles: [[UInt8]],
        includeContextLinesAfterMatch: Int = 0
    ) -> [String]? {
        let data: Data
        let maxFullRead: Int64 = 2_097_152
        if fileSize <= maxFullRead {
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else { return nil }
            data = d
        } else {
            guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
            defer { try? handle.close() }
            var combined = handle.readData(ofLength: 65_536)
            combined.append(0x0A)
            let tailOffset: UInt64 = UInt64(max(0, fileSize - 524_288))
            try? handle.seek(toOffset: tailOffset)
            var tailData = handle.readDataToEndOfFile()
            if tailOffset > 0, let nl = tailData.firstIndex(of: 0x0A) {
                let nextIdx = tailData.index(after: nl)
                if nextIdx <= tailData.endIndex {
                    tailData = tailData.subdata(in: nextIdx..<tailData.endIndex)
                }
            }
            combined.append(tailData)
            data = combined
        }

        return data.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) -> [String] in
            guard let base = rawBuf.baseAddress, rawBuf.count > 0 else { return [] }
            guard containsAnyNeedle(rawBuf, needles: needles) else { return [] }

            // Collect byte offsets of matching line starts via fast C memmem
            let bytePtr = base.assumingMemoryBound(to: UInt8.self)
            let totalLen = rawBuf.count
            let baseAddr = Int(bitPattern: base)
            var matchLineStarts = Set<Int>()

            for needle in needles {
                let nLen = needle.count
                needle.withUnsafeBufferPointer { nPtr in
                    guard let nBase = nPtr.baseAddress else { return }
                    var searchOffset = 0
                    while searchOffset < totalLen {
                        guard let found = memmem(base.advanced(by: searchOffset), totalLen - searchOffset, nBase, nLen) else {
                            break
                        }
                        let foundOffset = Int(bitPattern: found) - baseAddr
                        // Walk backwards to start of line
                        var lineStart = foundOffset
                        while lineStart > 0 && bytePtr[lineStart - 1] != 0x0A {
                            lineStart -= 1
                        }
                        matchLineStarts.insert(lineStart)
                        // Advance past end of this line
                        var lineEnd = foundOffset + nLen
                        while lineEnd < totalLen && bytePtr[lineEnd] != 0x0A {
                            lineEnd += 1
                        }
                        searchOffset = lineEnd + 1
                    }
                }
            }

            guard !matchLineStarts.isEmpty else { return [] }
            let sortedStarts = matchLineStarts.sorted()
            var lines: [String] = []
            lines.reserveCapacity(sortedStarts.count * (1 + includeContextLinesAfterMatch))
            var lastEmittedStart = -1

            for start in sortedStarts {
                var curStart = start
                var remaining = 1 + includeContextLinesAfterMatch
                while remaining > 0 && curStart < totalLen {
                    var curEnd = curStart
                    while curEnd < totalLen && bytePtr[curEnd] != 0x0A {
                        curEnd += 1
                    }
                    if curStart > lastEmittedStart {
                        let trimEnd = (curEnd > curStart && bytePtr[curEnd - 1] == 0x0D) ? (curEnd - 1) : curEnd
                        let len = trimEnd - curStart
                        if len > 0 {
                            let str = String(decoding: UnsafeBufferPointer(start: bytePtr.advanced(by: curStart), count: len), as: UTF8.self)
                            lines.append(str)
                        }
                        lastEmittedStart = curStart
                    }
                    curStart = curEnd + 1
                    remaining -= 1
                }
            }
            return lines
        }
    }

    private static func readLogTextForTransitions(atPath path: String, fileSize: Int64) -> String? {
        let data: Data
        let maxFullRead: Int64 = 2_097_152
        if fileSize <= maxFullRead {
            guard let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else { return nil }
            data = d
        } else {
            guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
            defer { try? handle.close() }
            var combined = handle.readData(ofLength: 65_536)
            combined.append(0x0A)
            let tailOffset: UInt64 = UInt64(max(0, fileSize - 524_288))
            try? handle.seek(toOffset: tailOffset)
            var tailData = handle.readDataToEndOfFile()
            if tailOffset > 0, let nl = tailData.firstIndex(of: 0x0A) {
                let nextIdx = tailData.index(after: nl)
                if nextIdx <= tailData.endIndex {
                    tailData = tailData.subdata(in: nextIdx..<tailData.endIndex)
                }
            }
            combined.append(tailData)
            data = combined
        }

        return data.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) -> String in
            guard let base = rawBuf.baseAddress, rawBuf.count > 0 else { return "" }
            let bytePtr = base.assumingMemoryBound(to: UInt8.self)
            let totalLen = rawBuf.count
            let baseAddr = Int(bitPattern: base)

            // 1. Extract all explicit auth transition lines via C memmem
            var matchLineStarts = Set<Int>()
            for needle in authAllNeedles {
                let nLen = needle.count
                needle.withUnsafeBufferPointer { nPtr in
                    guard let nBase = nPtr.baseAddress else { return }
                    var searchOffset = 0
                    while searchOffset < totalLen {
                        guard let found = memmem(base.advanced(by: searchOffset), totalLen - searchOffset, nBase, nLen) else {
                            break
                        }
                        let foundOffset = Int(bitPattern: found) - baseAddr
                        var lineStart = foundOffset
                        while lineStart > 0 && bytePtr[lineStart - 1] != 0x0A {
                            lineStart -= 1
                        }
                        matchLineStarts.insert(lineStart)
                        var lineEnd = foundOffset + nLen
                        while lineEnd < totalLen && bytePtr[lineEnd] != 0x0A {
                            lineEnd += 1
                        }
                        searchOffset = lineEnd + 1
                    }
                }
            }

            // 2. Only if no explicit auth transition exists in this log, grab the FIRST legacy consumer endpoint line
            // (avoids parsing 29,000+ redundant daily-cloudcode-pa.googleapis.com HTTP lines across historical logs)
            if matchLineStarts.isEmpty {
                legacyConsumerEndpointNeedle.withUnsafeBufferPointer { nPtr in
                    guard let nBase = nPtr.baseAddress,
                          let found = memmem(base, totalLen, nBase, nPtr.count) else { return }
                    let foundOffset = Int(bitPattern: found) - baseAddr
                    var lineStart = foundOffset
                    while lineStart > 0 && bytePtr[lineStart - 1] != 0x0A {
                        lineStart -= 1
                    }
                    matchLineStarts.insert(lineStart)
                }
            }

            guard !matchLineStarts.isEmpty else { return "" }
            var lines: [String] = []
            lines.reserveCapacity(matchLineStarts.count)
            for start in matchLineStarts.sorted() {
                var curEnd = start
                while curEnd < totalLen && bytePtr[curEnd] != 0x0A {
                    curEnd += 1
                }
                let trimEnd = (curEnd > start && bytePtr[curEnd - 1] == 0x0D) ? (curEnd - 1) : curEnd
                let len = trimEnd - start
                if len > 0 {
                    lines.append(String(decoding: UnsafeBufferPointer(start: bytePtr.advanced(by: start), count: len), as: UTF8.self))
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    private static func extractLogYear(fileName: String, fallbackDate: Date, calendar: Calendar) -> Int {
        if fileName.hasPrefix("cli-") && fileName.count >= 12 {
            let startIdx = fileName.index(fileName.startIndex, offsetBy: 4)
            let endIdx = fileName.index(startIdx, offsetBy: 4)
            if let y = Int(fileName[startIdx..<endIdx]) {
                return y
            }
        }
        return calendar.component(.year, from: fallbackDate)
    }

    private static func parseAuthEvents(
        in text: String,
        year: Int,
        defaultProject: String?,
        calendar: Calendar,
        includeLegacyMarkers: Bool
    ) -> [ParsedLogAuthEvent] {
        var events: [ParsedLogAuthEvent] = []
        var linesSinceGcpApplyAuth = 0

        for line in text.components(separatedBy: .newlines) {
            if line.isEmpty || line.contains("HandleUserInput") {
                if linesSinceGcpApplyAuth > 0 { linesSinceGcpApplyAuth -= 1 }
                continue
            }

            // Fast substring pre-filter: skip 99%+ of non-auth log lines BEFORE timestamp & regex parsing
            let hasApplyAuth = line.contains("applyAuthResult:")
            let hasOAuth = line.contains("OAuth:")
            let hasLegacy = includeLegacyMarkers && (
                line.contains("authMethod=")
                || line.contains("gcp_setup.go")
                || line.contains("[Auth State Transition]")
                || line.contains("GCP setup completed")
                || line.contains("aiplatform.googleapis.com")
                || line.contains("aiplatform.us.rep.googleapis.com")
                || line.contains("daily-cloudcode-pa.googleapis.com")
            )
            if !hasApplyAuth && !hasOAuth && !hasLegacy {
                if linesSinceGcpApplyAuth > 0 { linesSinceGcpApplyAuth -= 1 }
                continue
            }

            // Anchor auth events to genuine Go glog headers (e.g. `I1117 19:13:16.341234 ...`)
            // so agent tool outputs, code snippets, and diffs inside logs are never parsed as auth events.
            guard let lineTs = parseGlogTimestamp(line: line, year: year, calendar: calendar) else {
                if linesSinceGcpApplyAuth > 0 { linesSinceGcpApplyAuth -= 1 }
                continue
            }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)

            if hasApplyAuth, let regex = applyAuthRegex,
               let match = regex.firstMatch(in: line, range: range),
               let emailRange = Range(match.range(at: 1), in: line),
               let methodRange = Range(match.range(at: 2), in: line) {
                let email = cleanExtractedEmail(String(line[emailRange]))
                if let email, AgyQuotaService.isSyntheticTestEmail(email) {
                    if linesSinceGcpApplyAuth > 0 { linesSinceGcpApplyAuth -= 1 }
                    continue
                }
                let method = String(line[methodRange])
                var project: String? = nil
                if match.range(at: 3).location != NSNotFound,
                   let projRange = Range(match.range(at: 3), in: line) {
                    let rawProj = String(line[projRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !rawProj.isEmpty {
                        project = rawProj
                    }
                }
                if method == "gcp" {
                    linesSinceGcpApplyAuth = 3
                    events.append(ParsedLogAuthEvent(
                        timestamp: lineTs,
                        isGcp: true,
                        email: email,
                        project: project ?? defaultProject ?? "clawdbot-485304",
                        isConsumerOAuth: false
                    ))
                } else {
                    linesSinceGcpApplyAuth = 0
                    events.append(ParsedLogAuthEvent(
                        timestamp: lineTs,
                        isGcp: false,
                        email: email,
                        project: nil,
                        isConsumerOAuth: true
                    ))
                }
                continue
            }

            if let regex = consumerOAuthRegex,
               let match = regex.firstMatch(in: line, range: range),
               let emailRange = Range(match.range(at: 1), in: line) {
                linesSinceGcpApplyAuth = 0
                if let email = cleanExtractedEmail(String(line[emailRange])),
                   !AgyQuotaService.isSyntheticTestEmail(email) {
                    events.append(ParsedLogAuthEvent(
                        timestamp: lineTs,
                        isGcp: false,
                        email: email,
                        project: nil,
                        isConsumerOAuth: true
                    ))
                }
                continue
            }

            if let regex = oauthSuccessRegex,
               let match = regex.firstMatch(in: line, range: range),
               let emailRange = Range(match.range(at: 1), in: line) {
                if line.contains("authMethod=gcp") || linesSinceGcpApplyAuth > 0 {
                    if linesSinceGcpApplyAuth > 0 { linesSinceGcpApplyAuth -= 1 }
                    continue
                }
                if let email = cleanExtractedEmail(String(line[emailRange])),
                   !AgyQuotaService.isSyntheticTestEmail(email) {
                    events.append(ParsedLogAuthEvent(
                        timestamp: lineTs,
                        isGcp: false,
                        email: email,
                        project: nil,
                        isConsumerOAuth: true
                    ))
                }
                continue
            }

            if includeLegacyMarkers {
                if line.contains("authMethod=gcp") || line.contains("gcp_setup.go") || line.contains("[Auth State Transition]") || line.contains("GCP setup completed") || line.contains("aiplatform.googleapis.com") || line.contains("aiplatform.us.rep.googleapis.com") {
                    let extracted = extractFirstValidEmail(in: line)
                    if let extracted, AgyQuotaService.isSyntheticTestEmail(extracted) {
                        continue
                    }
                    linesSinceGcpApplyAuth = 3
                    events.append(ParsedLogAuthEvent(
                        timestamp: lineTs,
                        isGcp: true,
                        email: extracted,
                        project: defaultProject ?? "clawdbot-485304",
                        isConsumerOAuth: false
                    ))
                    continue
                }
                if line.contains("authMethod=consumer") || line.contains("daily-cloudcode-pa.googleapis.com") {
                    let extracted = extractFirstValidEmail(in: line)
                    if let extracted, AgyQuotaService.isSyntheticTestEmail(extracted) {
                        continue
                    }
                    linesSinceGcpApplyAuth = 0
                    events.append(ParsedLogAuthEvent(
                        timestamp: lineTs,
                        isGcp: false,
                        email: extracted,
                        project: nil,
                        isConsumerOAuth: false
                    ))
                    continue
                }
            }

            if linesSinceGcpApplyAuth > 0 {
                linesSinceGcpApplyAuth -= 1
            }
        }

        return events
    }

    public static func resolveActiveConsumerEmail(cliDir: String? = nil) -> String? {
        let expandedCliDir = (cliDir ?? getDefaultCliDir()).replacingOccurrences(of: "~", with: NSHomeDirectory())
        let fm = FileManager.default

        let tokenPath = (expandedCliDir as NSString).appendingPathComponent("antigravity-oauth-token")
        let oauthTokenModDate = (try? fm.attributesOfItem(atPath: tokenPath))?[.modificationDate] as? Date ?? Date.distantPast

        let cliLogPath = (expandedCliDir as NSString).appendingPathComponent("cli.log")
        let cliLogExists = fm.fileExists(atPath: cliLogPath)
        let resolvedCliLogPath = cliLogExists ? URL(fileURLWithPath: cliLogPath).resolvingSymlinksInPath().path : nil
        let cliLogAttrs = resolvedCliLogPath.flatMap { try? fm.attributesOfItem(atPath: $0) }
        let cliLogModDate = cliLogAttrs?[.modificationDate] as? Date ?? Date.distantPast
        let cliLogSize = (cliLogAttrs?[.size] as? NSNumber)?.int64Value ?? 0

        let logDir = (expandedCliDir as NSString).appendingPathComponent("log")
        let logDirModDate = (try? fm.attributesOfItem(atPath: logDir))?[.modificationDate] as? Date ?? Date.distantPast

        consumerEmailCacheLock.lock()
        if let cached = consumerEmailCache[expandedCliDir],
           cached.oauthTokenModDate == oauthTokenModDate,
           cached.resolvedCliLogPath == resolvedCliLogPath,
           cached.cliLogModDate == cliLogModDate,
           cached.cliLogSize == cliLogSize,
           cached.logDirModDate == logDirModDate {
            let cachedEmail = cached.email
            consumerEmailCacheLock.unlock()
            return cachedEmail
        }
        consumerEmailCacheLock.unlock()

        func cacheAndReturn(_ email: String?) -> String? {
            let entry = ConsumerEmailCacheEntry(
                expandedCliDir: expandedCliDir,
                oauthTokenModDate: oauthTokenModDate,
                resolvedCliLogPath: resolvedCliLogPath,
                cliLogModDate: cliLogModDate,
                cliLogSize: cliLogSize,
                logDirModDate: logDirModDate,
                email: email
            )
            consumerEmailCacheLock.lock()
            consumerEmailCache[expandedCliDir] = entry
            consumerEmailCacheLock.unlock()
            return email
        }

        // 1. Check antigravity-oauth-token JSON first
        if let data = try? Data(contentsOf: URL(fileURLWithPath: tokenPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let authMethod = json["auth_method"] as? String,
           authMethod == "consumer" {
            let rawEmail = (json["id_token_email"] as? String) ?? (json["email"] as? String)
            if let email = rawEmail.flatMap({ cleanExtractedEmail($0) }),
               !email.isEmpty,
               !AgyQuotaService.isSyntheticTestEmail(email) {
                return cacheAndReturn(email)
            }
        }

        // 2. Inspect <expandedCliDir>/cli.log and up to 3 newest cli-*.log files in <expandedCliDir>/log/
        // Pre-sort lexicographically descending and stat only the top 8 to avoid O(N) stat across 1,500+ logs.
        struct CandidateLogFile {
            let resolvedPath: String
            let fileName: String
            let modDate: Date
            let rank: Int
        }

        var candidates: [CandidateLogFile] = []
        var seenPaths = Set<String>()

        if let resolved = resolvedCliLogPath {
            seenPaths.insert(resolved)
            candidates.append(CandidateLogFile(
                resolvedPath: resolved,
                fileName: (resolved as NSString).lastPathComponent,
                modDate: cliLogModDate,
                rank: 0
            ))
        }

        if let files = try? fm.contentsOfDirectory(atPath: logDir) {
            let topFilenames = files
                .filter { $0.hasPrefix("cli-") && $0.hasSuffix(".log") }
                .sorted(by: >)
                .prefix(8)

            let logFilesWithMod: [(path: String, fileName: String, modDate: Date)] = topFilenames
                .map { file in
                    let fullPath = (logDir as NSString).appendingPathComponent(file)
                    let mod = (try? fm.attributesOfItem(atPath: fullPath))?[.modificationDate] as? Date ?? Date.distantPast
                    return (path: fullPath, fileName: file, modDate: mod)
                }
                .sorted { lhs, rhs in
                    if lhs.modDate != rhs.modDate {
                        return lhs.modDate > rhs.modDate
                    }
                    return lhs.fileName > rhs.fileName
                }

            for entry in logFilesWithMod.prefix(3) {
                let resolved = URL(fileURLWithPath: entry.path).resolvingSymlinksInPath().path
                if seenPaths.insert(resolved).inserted {
                    candidates.append(CandidateLogFile(
                        resolvedPath: resolved,
                        fileName: entry.fileName,
                        modDate: entry.modDate,
                        rank: candidates.count
                    ))
                }
            }
        }

        guard !candidates.isEmpty else { return cacheAndReturn(nil) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        struct ConsumerMatch {
            let email: String
            let timestamp: Date?
            let modDate: Date
            let fileRank: Int
            let occurrenceIndex: Int
        }

        var matches: [ConsumerMatch] = []
        for candidate in candidates {
            guard let logText = readHeadAndTailText(atPath: candidate.resolvedPath, headBytes: 32_768, tailBytes: 262_144) else { continue }
            let year = extractLogYear(fileName: candidate.fileName, fallbackDate: candidate.modDate, calendar: calendar)
            let events = parseAuthEvents(
                in: logText,
                year: year,
                defaultProject: nil,
                calendar: calendar,
                includeLegacyMarkers: false
            )
            for (idx, event) in events.enumerated() where event.isConsumerOAuth && !event.isGcp {
                if let email = event.email, !email.isEmpty {
                    matches.append(ConsumerMatch(
                        email: email,
                        timestamp: event.timestamp,
                        modDate: candidate.modDate,
                        fileRank: candidate.rank,
                        occurrenceIndex: idx
                    ))
                }
            }
        }

        guard !matches.isEmpty else { return cacheAndReturn(nil) }

        let latest = matches.max { lhs, rhs in
            if let lTs = lhs.timestamp, let rTs = rhs.timestamp, lTs != rTs {
                return lTs < rTs
            }
            if lhs.modDate != rhs.modDate {
                return lhs.modDate < rhs.modDate
            }
            if lhs.fileRank != rhs.fileRank {
                return lhs.fileRank > rhs.fileRank
            }
            return lhs.occurrenceIndex < rhs.occurrenceIndex
        }
        return cacheAndReturn(latest?.email)
    }

    public static func loadAuthTransitions(logDir: String, defaultProject: String? = nil) -> [AuthTransition] {
        return loadAuthTransitionsWithMissFlag(logDir: logDir, defaultProject: defaultProject).transitions
    }

    private static func loadAuthTransitionsWithMissFlag(logDir: String, defaultProject: String? = nil) -> (transitions: [AuthTransition], hadMiss: Bool) {
        let historicalTransitions: [AuthTransition] = [
            AuthTransition(timestamp: Date.distantPast, isGcp: false, email: "sameerbajaj24@gmail.com", gcpProject: nil),
            AuthTransition(timestamp: Date(timeIntervalSince1970: 1788408335), isGcp: true, email: "sameerbajaj24@gmail.com", gcpProject: defaultProject ?? "clawdbot-485304"),
            AuthTransition(timestamp: Date(timeIntervalSince1970: 1788445773), isGcp: false, email: "sameerbajaj24@gmail.com", gcpProject: nil),
            AuthTransition(timestamp: Date(timeIntervalSince1970: 1789525449), isGcp: true, email: "sameerbajaj24@gmail.com", gcpProject: defaultProject ?? "clawdbot-485304"),
            AuthTransition(timestamp: Date(timeIntervalSince1970: 1789527897), isGcp: false, email: "sameerbajaj24@gmail.com", gcpProject: nil)
        ]

        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: logDir, isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (historicalTransitions, false)
        }
        
        struct LogFileMeta {
            let name: String
            let path: String
            let modDate: Date
            let size: Int64
        }
        var logFiles: [LogFileMeta] = []
        logFiles.reserveCapacity(urls.count)
        for url in urls {
            let name = url.lastPathComponent
            guard name.hasPrefix("cli-") && name.hasSuffix(".log") else { continue }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            logFiles.append(LogFileMeta(
                name: name,
                path: url.path,
                modDate: vals?.contentModificationDate ?? Date.distantPast,
                size: Int64(vals?.fileSize ?? 0)
            ))
        }
        guard !logFiles.isEmpty else { return (historicalTransitions, false) }
        logFiles.sort { $0.name < $1.name }
        let newest = logFiles.last!
        
        let now = Date()
        authCacheLock.lock()
        if let cached = authCache,
           cached.defaultProject == defaultProject,
           cached.fileCount == logFiles.count,
           cached.newestName == newest.name,
           cached.newestModDate == newest.modDate,
           cached.newestSize == newest.size {
            if now.timeIntervalSince(cached.cachedAt) < 30.0 {
                let res = cached.transitions
                authCacheLock.unlock()
                return (res, false)
            }
            authCache = AuthCacheEntry(
                fileCount: cached.fileCount,
                newestName: cached.newestName,
                newestModDate: cached.newestModDate,
                newestSize: cached.newestSize,
                defaultProject: defaultProject,
                cachedAt: now,
                transitions: cached.transitions
            )
            let res = cached.transitions
            authCacheLock.unlock()
            return (res, false)
        }
        authCacheLock.unlock()
        
        var transitions: [AuthTransition] = historicalTransitions
        var lastIsGcp: Bool? = historicalTransitions.last?.isGcp
        var lastEmail: String? = historicalTransitions.last?.email
        var lastProject: String? = historicalTransitions.last?.gcpProject
        
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        logFileCacheLock.lock()
        let cacheSnapshot = logFileCache
        logFileCacheLock.unlock()

        var newCacheEntries: [String: LogFileEntry] = [:]
        var hadMiss = false
        
        for meta in logFiles {
            let file = meta.name
            let stripped = file.replacingOccurrences(of: "cli-", with: "").replacingOccurrences(of: ".log", with: "")
            guard let date = Self.logDateFormatter.date(from: stripped) else { continue }
            
            let fileTransitions: [AuthTransition]
            if let cachedLog = cacheSnapshot[meta.path],
               cachedLog.modDate == meta.modDate,
               cachedLog.size == meta.size {
                fileTransitions = cachedLog.transitions
            } else {
                hadMiss = true
                guard let text = readLogTextForTransitions(atPath: meta.path, fileSize: meta.size) else { continue }
                let year = extractLogYear(fileName: file, fallbackDate: date, calendar: calendar)
                let events = parseAuthEvents(
                    in: text,
                    year: year,
                    defaultProject: defaultProject,
                    calendar: calendar,
                    includeLegacyMarkers: true
                )

                var parsedTransitions: [AuthTransition] = []
                parsedTransitions.reserveCapacity(events.count)
                for event in events {
                    parsedTransitions.append(AuthTransition(
                        timestamp: event.timestamp ?? date,
                        isGcp: event.isGcp,
                        email: event.email,
                        gcpProject: event.project
                    ))
                }
                fileTransitions = parsedTransitions
                newCacheEntries[meta.path] = LogFileEntry(
                    modDate: meta.modDate,
                    size: meta.size,
                    transitions: fileTransitions
                )
            }
            
            for t in fileTransitions {
                let resolvedEmail = t.email ?? lastEmail
                if lastIsGcp != t.isGcp || (resolvedEmail != nil && resolvedEmail != lastEmail) || t.gcpProject != lastProject {
                    transitions.append(AuthTransition(
                        timestamp: t.timestamp,
                        isGcp: t.isGcp,
                        email: resolvedEmail,
                        gcpProject: t.gcpProject
                    ))
                    lastIsGcp = t.isGcp
                    lastEmail = resolvedEmail
                    lastProject = t.gcpProject
                }
            }
        }
        if !newCacheEntries.isEmpty {
            logFileCacheLock.lock()
            for (k, v) in newCacheEntries {
                logFileCache[k] = v
            }
            logFileCacheLock.unlock()
        }
        transitions.sort { $0.timestamp < $1.timestamp }
        
        authCacheLock.lock()
        authCache = AuthCacheEntry(
            fileCount: logFiles.count,
            newestName: newest.name,
            newestModDate: newest.modDate,
            newestSize: newest.size,
            defaultProject: defaultProject,
            cachedAt: now,
            transitions: transitions
        )
        authCacheLock.unlock()
        
        return (transitions, hadMiss)
    }

    private static let modelOverrideMarkerData = Data("Propagating selected model override".utf8)
    
    private static func loadModelTransitions(logDir: String) -> [ModelTransition] {
        return loadModelTransitionsWithMissFlag(logDir: logDir).transitions
    }

    private static func loadModelTransitionsWithMissFlag(logDir: String) -> (transitions: [ModelTransition], hadMiss: Bool) {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: logDir, isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([], false)
        }
        
        struct LogFileMeta {
            let name: String
            let path: String
            let modDate: Date
            let size: Int64
        }
        var logFiles: [LogFileMeta] = []
        logFiles.reserveCapacity(urls.count)
        for url in urls {
            let name = url.lastPathComponent
            guard name.hasPrefix("cli-") && name.hasSuffix(".log") else { continue }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            logFiles.append(LogFileMeta(
                name: name,
                path: url.path,
                modDate: vals?.contentModificationDate ?? Date.distantPast,
                size: Int64(vals?.fileSize ?? 0)
            ))
        }
        guard !logFiles.isEmpty else { return ([], false) }
        logFiles.sort { $0.name < $1.name }
        let newest = logFiles.last!
        
        let now = Date()
        modelTransitionCacheLock.lock()
        if let cached = modelTransitionCache {
            if now.timeIntervalSince(cached.cachedAt) < 30.0 {
                let res = cached.transitions
                modelTransitionCacheLock.unlock()
                return (res, false)
            }
            if cached.fileCount == logFiles.count,
               cached.newestName == newest.name,
               cached.newestModDate == newest.modDate {
                modelTransitionCache = ModelTransitionCacheEntry(
                    fileCount: cached.fileCount,
                    newestName: cached.newestName,
                    newestModDate: cached.newestModDate,
                    cachedAt: now,
                    transitions: cached.transitions
                )
                let res = cached.transitions
                modelTransitionCacheLock.unlock()
                return (res, false)
            }
        }
        modelTransitionCacheLock.unlock()
        
        var allTransitions: [ModelTransition] = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        modelLogFileCacheLock.lock()
        let cacheSnapshot = modelLogFileCache
        modelLogFileCacheLock.unlock()

        var newCacheEntries: [String: ModelLogFileEntry] = [:]
        var hadMiss = false
        
        for meta in logFiles {
            let file = meta.name
            let year: Int
            if file.hasPrefix("cli-") && file.count >= 12 {
                let startIdx = file.index(file.startIndex, offsetBy: 4)
                let endIdx = file.index(startIdx, offsetBy: 4)
                let yearStr = String(file[startIdx..<endIdx])
                year = Int(yearStr) ?? 2026
            } else {
                year = 2026
            }
            
            var fileTransitions: [ModelTransition] = []
            
            if let cachedLog = cacheSnapshot[meta.path],
               cachedLog.modDate == meta.modDate,
               cachedLog.size == meta.size {
                fileTransitions = cachedLog.transitions
            } else {
                hadMiss = true
                if let matchingLines = extractMatchingLogLines(
                    atPath: meta.path,
                    fileSize: meta.size,
                    needles: [modelOverrideNeedle],
                    includeContextLinesAfterMatch: 0
                ) {
                    for line in matchingLines {
                        guard let labelRange = line.range(of: "label=\"") else { continue }
                        let afterLabel = line[labelRange.upperBound...]
                        guard let quoteEnd = afterLabel.firstIndex(of: "\"") else { continue }
                        let modelName = String(afterLabel[..<quoteEnd])
                        
                        if line.count >= 14 {
                            let lineChars = Array(line.prefix(14))
                            if let month = Int(String(lineChars[1...2])),
                               let day = Int(String(lineChars[3...4])),
                               let hour = Int(String(lineChars[6...7])),
                               let minute = Int(String(lineChars[9...10])),
                               let second = Int(String(lineChars[12...13])) {
                                var comps = DateComponents()
                                comps.year = year
                                comps.month = month
                                comps.day = day
                                comps.hour = hour
                                comps.minute = minute
                                comps.second = second
                                if let dt = calendar.date(from: comps) {
                                    fileTransitions.append(ModelTransition(timestamp: dt, modelName: modelName))
                                }
                            }
                        }
                    }
                }
                
                newCacheEntries[meta.path] = ModelLogFileEntry(
                    modDate: meta.modDate,
                    size: meta.size,
                    transitions: fileTransitions
                )
            }
            
            allTransitions.append(contentsOf: fileTransitions)
        }
        if !newCacheEntries.isEmpty {
            modelLogFileCacheLock.lock()
            for (k, v) in newCacheEntries {
                modelLogFileCache[k] = v
            }
            modelLogFileCacheLock.unlock()
        }
        
        allTransitions.sort { $0.timestamp < $1.timestamp }
        
        modelTransitionCacheLock.lock()
        modelTransitionCache = ModelTransitionCacheEntry(
            fileCount: logFiles.count,
            newestName: newest.name,
            newestModDate: newest.modDate,
            cachedAt: now,
            transitions: allTransitions
        )
        modelTransitionCacheLock.unlock()
        
        return (allTransitions, hadMiss)
    }
    
    private static func findModelOverride(at date: Date, in transitions: [ModelTransition], calendar: Calendar) -> String? {
        guard !transitions.isEmpty else { return nil }
        // Binary search for last transition with timestamp <= date
        var low = 0
        var high = transitions.count
        while low < high {
            let mid = (low + high) / 2
            if transitions[mid].timestamp <= date {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let idx = low - 1
        guard idx >= 0 else { return nil }
        let trans = transitions[idx]
        let diff = date.timeIntervalSince(trans.timestamp)
        if diff >= 0 && diff < 8 * 3600 && calendar.isDate(trans.timestamp, inSameDayAs: date) {
            return trans.modelName
        }
        return nil
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
    
    private static func loadActiveAuthMethod(cliDir: String) -> (isGcp: Bool, email: String?, project: String?, explicitConsumer: Bool) {
        let tokenPath = (cliDir as NSString).appendingPathComponent("antigravity-oauth-token")
        if let data = try? Data(contentsOf: URL(fileURLWithPath: tokenPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let authMethod = json["auth_method"] as? String
            let rawEmail = (json["id_token_email"] as? String) ?? (json["email"] as? String)
            let email = rawEmail.flatMap { cleanExtractedEmail($0) }
            let project = (json["project_id"] as? String) ?? (json["quota_project"] as? String)
            if authMethod == "gcp" {
                return (true, email, project, false)
            } else if authMethod == "consumer" {
                return (false, email ?? resolveActiveConsumerEmail(cliDir: cliDir), nil, true)
            }
        }

        let fm = FileManager.default
        let cliLogPath = (cliDir as NSString).appendingPathComponent("cli.log")
        let logDir = (cliDir as NSString).appendingPathComponent("log")
        var candidatePath: String? = nil
        var candidateName = "cli.log"

        if fm.fileExists(atPath: cliLogPath) {
            let resolved = URL(fileURLWithPath: cliLogPath).resolvingSymlinksInPath().path
            candidatePath = resolved
            candidateName = (resolved as NSString).lastPathComponent
        } else if let files = try? fm.contentsOfDirectory(atPath: logDir) {
            let logFiles = files.filter { $0.hasPrefix("cli-") && $0.hasSuffix(".log") }.sorted()
            if let newest = logFiles.last {
                candidatePath = (logDir as NSString).appendingPathComponent(newest)
                candidateName = newest
            }
        }

        if let path = candidatePath, let tailText = readTailText(atPath: path, maxBytes: 262_144) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone.current
            let modDate = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? Date()
            let year = extractLogYear(fileName: candidateName, fallbackDate: modDate, calendar: calendar)
            let events = parseAuthEvents(
                in: tailText,
                year: year,
                defaultProject: nil,
                calendar: calendar,
                includeLegacyMarkers: true
            )
            if let lastEvent = events.last {
                if lastEvent.isGcp {
                    return (true, lastEvent.email, lastEvent.project, false)
                } else {
                    return (false, lastEvent.email ?? resolveActiveConsumerEmail(cliDir: cliDir), nil, true)
                }
            }
        }

        if let consumerEmail = resolveActiveConsumerEmail(cliDir: cliDir) {
            return (false, consumerEmail, nil, true)
        }

        return (false, nil, nil, false)
    }

    private static let uuidRegex = try? NSRegularExpression(pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

    private static func loadGcpBoxConsumerConvIdsWithMissFlag(gcpCliDir: String) -> (Set<String>, Bool) {
        let logDir = (gcpCliDir as NSString).appendingPathComponent("log")
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: logDir, isDirectory: true),
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return ([], false) }
        
        gcpConsumerLogCacheLock.lock()
        let cacheSnapshot = gcpConsumerLogCache
        gcpConsumerLogCacheLock.unlock()

        var consumerConvs = Set<String>()
        var newEntries: [String: GcpConsumerLogEntry] = [:]
        var hadMiss = false
        
        for url in urls {
            let file = url.lastPathComponent
            guard file.hasPrefix("cli-") && file.hasSuffix(".log") else { continue }
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modDate = vals?.contentModificationDate ?? Date.distantPast
            let fileSize = Int64(vals?.fileSize ?? 0)
            let fullPath = url.path

            if let cached = cacheSnapshot[fullPath],
               cached.modDate == modDate,
               cached.size == fileSize {
                consumerConvs.formUnion(cached.consumerConvIds)
                continue
            }

            hadMiss = true
            var fileConvIds: [String] = []
            if let text = try? String(contentsOfFile: fullPath, encoding: .utf8) ?? String(contentsOfFile: fullPath, encoding: .ascii) {
                let isConsumer = text.contains("authMethod=consumer") || text.contains("daily-cloudcode-pa.googleapis.com")
                let isGcp = text.contains("authMethod=gcp") || text.contains("aiplatform")
                if isConsumer && !isGcp, let regex = uuidRegex {
                    var seen = Set<String>()
                    let range = NSRange(text.startIndex..., in: text)
                    let matches = regex.matches(in: text, range: range)
                    for match in matches {
                        if let r = Range(match.range, in: text) {
                            let id = String(text[r])
                            if seen.insert(id).inserted {
                                fileConvIds.append(id)
                                consumerConvs.insert(id)
                            }
                        }
                    }
                }
            }
            newEntries[fullPath] = GcpConsumerLogEntry(modDate: modDate, size: fileSize, consumerConvIds: fileConvIds)
        }

        if !newEntries.isEmpty {
            gcpConsumerLogCacheLock.lock()
            for (k, v) in newEntries {
                gcpConsumerLogCache[k] = v
            }
            gcpConsumerLogCacheLock.unlock()
        }
        return (consumerConvs, hadMiss)
    }
    
    private static func loadHistory(at path: String) -> ([QueryEntry], [WorkspaceStats], Date?, Bool) {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: path)
        let modDate = attrs?[.modificationDate] as? Date ?? Date.distantPast
        let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        
        historyCacheLock.lock()
        if let cached = historyCache[path],
           cached.modificationDate == modDate,
           cached.fileSize == fileSize {
            let res = (cached.queries, cached.workspaces, cached.lastQuery, true)
            historyCacheLock.unlock()
            return res
        }
        historyCacheLock.unlock()
        
        guard let rawData = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else {
            return ([], [], nil, false)
        }
        
        var queries: [QueryEntry] = []
        queries.reserveCapacity(Int(fileSize / 160))
        var workspaceMap: [String: (count: Int, lastActive: Date)] = [:]
        let decoder = JSONDecoder()

        // Split raw UTF-8 Data directly on newline (0x0A) without intermediate String/UTF-8 round-trip copies
        var lineStart = rawData.startIndex
        let end = rawData.endIndex
        while lineStart < end {
            let lineEnd = rawData[lineStart..<end].firstIndex(of: 0x0A) ?? end
            var sliceStart = lineStart
            var sliceEnd = lineEnd
            while sliceStart < sliceEnd && (rawData[sliceStart] == 0x20 || rawData[sliceStart] == 0x09 || rawData[sliceStart] == 0x0D) {
                sliceStart += 1
            }
            while sliceEnd > sliceStart && (rawData[sliceEnd - 1] == 0x20 || rawData[sliceEnd - 1] == 0x09 || rawData[sliceEnd - 1] == 0x0D) {
                sliceEnd -= 1
            }
            if sliceStart < sliceEnd {
                let slice = rawData[sliceStart..<sliceEnd]
                if let raw = try? decoder.decode(HistoryLine.self, from: slice) {
                    let date = Date(timeIntervalSince1970: TimeInterval(raw.timestamp) / 1000.0)
                    let entry = QueryEntry(
                        display: raw.display,
                        timestamp: date,
                        workspace: raw.workspace,
                        conversationId: raw.conversationId,
                        type: raw.type
                    )
                    queries.append(entry)
                    
                    let current = workspaceMap[raw.workspace] ?? (count: 0, lastActive: date)
                    workspaceMap[raw.workspace] = (
                        count: current.count + 1,
                        lastActive: max(current.lastActive, date)
                    )
                }
            }
            lineStart = lineEnd < end ? rawData.index(after: lineEnd) : end
        }
        
        // Sort queries newest first
        queries.sort { $0.timestamp > $1.timestamp }
        let lastQuery = queries.first?.timestamp
        
        // Convert workspaces map to array and sort by query count descending
        let workspaces = workspaceMap.map { path, info in
            WorkspaceStats(path: path, queryCount: info.count, lastActiveAt: info.lastActive)
        }.sorted { $0.queryCount > $1.queryCount }
        
        historyCacheLock.lock()
        historyCache[path] = HistoryCacheEntry(
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
    
    // MARK: - Zero-Copy Fast Protobuf Walkers (Skips 78%+ Unused Payload Fields in O(1))

    @inline(__always)
    private static func readVarint(_ buf: UnsafeRawBufferPointer, index: inout Int, end: Int) -> Int? {
        var val = 0
        var shift = 0
        while index < end {
            let b = buf[index]
            index += 1
            val |= Int(b & 0x7F) << shift
            if (b & 0x80) == 0 {
                return val
            }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    @inline(__always)
    private static func skipField(wireType: Int, _ buf: UnsafeRawBufferPointer, index: inout Int, end: Int) -> Bool {
        switch wireType {
        case 0:
            return readVarint(buf, index: &index, end: end) != nil
        case 1:
            guard index + 8 <= end else { return false }
            index += 8
            return true
        case 2:
            guard let len = readVarint(buf, index: &index, end: end), len >= 0, index + len <= end else { return false }
            index += len
            return true
        case 5:
            guard index + 4 <= end else { return false }
            index += 4
            return true
        default:
            return false
        }
    }

    private static func parseStepTimestampFast(_ buf: UnsafeRawBufferPointer) -> Int? {
        var index = 0
        let end = buf.count
        while index < end {
            guard let tag = readVarint(buf, index: &index, end: end), tag > 0 else { break }
            let wireType = tag & 0x07
            let fieldNumber = tag >> 3
            if fieldNumber == 1 && wireType == 2 {
                guard let len = readVarint(buf, index: &index, end: end), len >= 0, index + len <= end else { break }
                var subIdx = index
                let subEnd = index + len
                while subIdx < subEnd {
                    guard let sTag = readVarint(buf, index: &subIdx, end: subEnd), sTag > 0 else { break }
                    let sWire = sTag & 0x07
                    let sField = sTag >> 3
                    if sField == 1 && sWire == 0 {
                        return readVarint(buf, index: &subIdx, end: subEnd)
                    }
                    if !skipField(wireType: sWire, buf, index: &subIdx, end: subEnd) { break }
                }
                return nil
            }
            if !skipField(wireType: wireType, buf, index: &index, end: end) { break }
        }
        return nil
    }

    private struct ParsedGenMetaFast {
        var hasProtobufMetadata = false
        var rawModel: String? = nil
        var modelEnumId: Int? = nil
        var inputTokens: Int? = nil
        var outputTokens: Int? = nil
        var cachedTokens: Int? = nil
        var lastStepIndex: Int? = nil
        var modelEnumStr: String? = nil
    }

    private static func decodeUtf8Slice(_ buf: UnsafeRawBufferPointer, start: Int, length: Int) -> String? {
        guard length > 0, let base = buf.baseAddress else { return nil }
        let ptr = base.advanced(by: start).assumingMemoryBound(to: UInt8.self)
        return String(decoding: UnsafeBufferPointer(start: ptr, count: length), as: UTF8.self)
    }

    private static func parseKvPairFast(_ buf: UnsafeRawBufferPointer, start: Int, end: Int, into result: inout ParsedGenMetaFast) {
        var idx = start
        var keyStart = -1
        var keyLen = 0
        var valStart = -1
        var valLen = 0
        while idx < end {
            guard let tag = readVarint(buf, index: &idx, end: end), tag > 0 else { break }
            let wire = tag & 0x07
            let field = tag >> 3
            if wire == 2 {
                guard let len = readVarint(buf, index: &idx, end: end), len >= 0, idx + len <= end else { break }
                if field == 1 && keyStart < 0 {
                    keyStart = idx
                    keyLen = len
                } else if field == 2 && valStart < 0 {
                    valStart = idx
                    valLen = len
                }
                idx += len
            } else {
                if !skipField(wireType: wire, buf, index: &idx, end: end) { break }
            }
        }
        guard keyStart >= 0, valStart >= 0 else { return }
        // Fast length check before allocating String: "last_step_index" = 15 bytes, "model_enum" = 10 bytes
        if keyLen == 15 {
            if decodeUtf8Slice(buf, start: keyStart, length: keyLen) == "last_step_index",
               let valStr = decodeUtf8Slice(buf, start: valStart, length: valLen),
               let sIdx = Int(valStr) {
                result.lastStepIndex = sIdx
            }
        } else if keyLen == 10 {
            if decodeUtf8Slice(buf, start: keyStart, length: keyLen) == "model_enum" {
                result.modelEnumStr = decodeUtf8Slice(buf, start: valStart, length: valLen)
            }
        }
    }

    private static func parseGenMetadataFast(_ buf: UnsafeRawBufferPointer) -> ParsedGenMetaFast {
        var res = ParsedGenMetaFast()
        var idx = 0
        let end = buf.count
        var topRawModel: String? = nil
        var f1Found = false

        while idx < end {
            guard let tag = readVarint(buf, index: &idx, end: end), tag > 0 else { break }
            let wire = tag & 0x07
            let field = tag >> 3

            if field == 1 && wire == 2 && !f1Found {
                guard let len = readVarint(buf, index: &idx, end: end), len >= 0, idx + len <= end else { break }
                f1Found = true
                res.hasProtobufMetadata = true
                var f1Idx = idx
                let f1End = idx + len
                while f1Idx < f1End {
                    guard let sTag = readVarint(buf, index: &f1Idx, end: f1End), sTag > 0 else { break }
                    let sWire = sTag & 0x07
                    let sField = sTag >> 3
                    if sWire == 2 {
                        guard let sLen = readVarint(buf, index: &f1Idx, end: f1End), sLen >= 0, f1Idx + sLen <= f1End else { break }
                        if sField == 19 && res.rawModel == nil {
                            res.rawModel = decodeUtf8Slice(buf, start: f1Idx, length: sLen)
                        } else if sField == 4 && res.modelEnumId == nil && res.inputTokens == nil {
                            var f4Idx = f1Idx
                            let f4End = f1Idx + sLen
                            while f4Idx < f4End {
                                guard let uTag = readVarint(buf, index: &f4Idx, end: f4End), uTag > 0 else { break }
                                let uWire = uTag & 0x07
                                let uField = uTag >> 3
                                if uWire == 0 {
                                    guard let v = readVarint(buf, index: &f4Idx, end: f4End) else { break }
                                    switch uField {
                                    case 1: if res.modelEnumId == nil { res.modelEnumId = v }
                                    case 2: if res.inputTokens == nil { res.inputTokens = v }
                                    case 3: if res.outputTokens == nil { res.outputTokens = v }
                                    case 5: if res.cachedTokens == nil { res.cachedTokens = v }
                                    default: break
                                    }
                                } else {
                                    if !skipField(wireType: uWire, buf, index: &f4Idx, end: f4End) { break }
                                }
                            }
                        } else if sField == 20 {
                            parseKvPairFast(buf, start: f1Idx, end: f1Idx + sLen, into: &res)
                        }
                        f1Idx += sLen
                    } else {
                        if !skipField(wireType: sWire, buf, index: &f1Idx, end: f1End) { break }
                    }
                }
                idx += len
            } else if field == 19 && wire == 2 && topRawModel == nil {
                guard let len = readVarint(buf, index: &idx, end: end), len >= 0, idx + len <= end else { break }
                topRawModel = decodeUtf8Slice(buf, start: idx, length: len)
                idx += len
            } else if field == 20 && wire == 2 && !f1Found {
                guard let len = readVarint(buf, index: &idx, end: end), len >= 0, idx + len <= end else { break }
                parseKvPairFast(buf, start: idx, end: idx + len, into: &res)
                idx += len
            } else {
                if !skipField(wireType: wire, buf, index: &idx, end: end) { break }
            }
        }

        if res.rawModel == nil {
            res.rawModel = topRawModel
        }
        return res
    }

    private struct DbFileJob: Sendable {
        let file: String
        let dbPath: String
        let modDate: Date
        let fileSize: Int64
        let walModDate: Date?
        let walFileSize: Int64?
        let walExists: Bool
    }

    private static func mapModelEnumId(_ enumId: Int) -> String? {
        switch enumId {
        // Gemini 4 Neon
        case 1532: return "Gemini 4 Neon (High)"
        case 1533: return "Gemini 4 Neon (Medium)"
        case 1534: return "Gemini 4 Neon (Low)"
        case 1535: return "Gemini 4 Neon (XHigh)"
        case 1537: return "Orchestrator (Neon)"
        // Gemini 4 Hydrogen
        case 1525, 1461, 1462: return "Gemini 4 Hydrogen (High)"
        case 1526: return "Gemini 4 Hydrogen (Medium)"
        case 1527: return "Gemini 4 Hydrogen (Low)"
        case 1528: return "Gemini 4 Hydrogen (XHigh)"
        // Gemini 4 Carbon
        case 1437, 1670: return "Gemini 4 Carbon (High)"
        // Gemini 4 Argon
        case 1417, 1418: return "Gemini 4 Argon (High)"
        case 1419: return "Gemini 4 Argon (Low)"
        case 1668: return "Orchestrator (Argon)"
        // Claude 5.5 (Opus & Sonnet)
        case 1400: return "Claude Opus 5.5 (Low)"
        case 1401: return "Claude Opus 5.5 (Medium)"
        case 1402: return "Claude Opus 5.5 (High)"
        case 1403: return "Claude Sonnet 5.5 (Low)"
        case 1404: return "Claude Sonnet 5.5 (Medium)"
        case 1405: return "Claude Sonnet 5.5 (High)"
        // Gemini 3.8 & 3.7 Flash
        case 1318, 1319: return "Gemini 3.8 Flash (High)"
        case 1320: return "Gemini 3.8 Flash (Low)"
        case 1299: return "Gemini 3.7 Flash (High)"
        default: return nil
        }
    }

    private static func parseDbConversationUncached(
        job: DbFileJob,
        isGcpOrigin: Bool = false,
        includeToolStats: Bool = false
    ) -> ConversationCacheEntry {
        let convId = (job.file as NSString).deletingPathExtension
        let uri = job.walExists ? "file:\(job.dbPath)?mode=ro" : "file:\(job.dbPath)?immutable=1"
        
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            let emptyData = DbConversationData(conversationId: convId, startTime: nil, generations: [])
            return ConversationCacheEntry(
                modificationDate: job.modDate,
                fileSize: job.fileSize,
                walModificationDate: job.walModDate,
                walFileSize: job.walFileSize,
                conversationData: emptyData,
                toolCounts: [:]
            )
        }
        defer { sqlite3_close(db) }
        
        // 1. Load step timestamps (skip massive step_payload blobs unless tool stats are explicitly requested)
        var startTime: Date? = nil
        var stepsTimestamps: [Int: Date] = [:]
        var toolCounts: [String: Int] = [:]
        var stepsStmt: OpaquePointer?
        let stepsQuery = includeToolStats
            ? "SELECT idx, metadata, step_payload FROM steps ORDER BY idx ASC"
            : "SELECT idx, metadata FROM steps ORDER BY idx ASC"
        if sqlite3_prepare_v2(db, stepsQuery, -1, &stepsStmt, nil) == SQLITE_OK {
            while sqlite3_step(stepsStmt) == SQLITE_ROW {
                let stepIdx = Int(sqlite3_column_int(stepsStmt, 0))
                
                // Timestamp from metadata (col 1) via zero-copy protobuf walker
                if let blob = sqlite3_column_blob(stepsStmt, 1) {
                    let blobSize = Int(sqlite3_column_bytes(stepsStmt, 1))
                    if blobSize > 0 {
                        let rawBuf = UnsafeRawBufferPointer(start: blob, count: blobSize)
                        if let seconds = parseStepTimestampFast(rawBuf) {
                            let dt = Date(timeIntervalSince1970: TimeInterval(seconds))
                            stepsTimestamps[stepIdx] = dt
                            if startTime == nil {
                                startTime = dt
                            }
                        }
                    }
                }
                
                if includeToolStats {
                    var matchedTool: String? = nil
                    for col in [Int32(1), Int32(2)] {
                        guard let blobBytes = sqlite3_column_blob(stepsStmt, col) else { continue }
                        let blobSize = Int(sqlite3_column_bytes(stepsStmt, col))
                        guard blobSize > 0 else { continue }
                        let data = Data(bytes: blobBytes, count: blobSize)
                        if let str = String(data: data, encoding: .ascii) {
                            for (tool, pattern) in toolBytePatterns {
                                if str.contains(tool), searchPattern(pattern, in: data) {
                                    matchedTool = tool
                                    break
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
        }
        sqlite3_finalize(stepsStmt)
        
        // 2. Load generation metadata via zero-copy targeted protobuf walker
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
                var hasProtobufMetadata = false
                
                if let blob = sqlite3_column_blob(genStmt, 1) {
                    let blobSize = Int(sqlite3_column_bytes(genStmt, 1))
                    if blobSize > 0 {
                        let rawBuf = UnsafeRawBufferPointer(start: blob, count: blobSize)
                        let parsed = parseGenMetadataFast(rawBuf)
                        hasProtobufMetadata = parsed.hasProtobufMetadata
                        inputTokens = parsed.inputTokens
                        outputTokens = parsed.outputTokens
                        cachedTokens = parsed.cachedTokens
                        if let sIdx = parsed.lastStepIndex {
                            timestamp = stepsTimestamps[sIdx]
                        }
                        if let rawModel = parsed.rawModel {
                            modelName = cleanAndMapModelName(rawModel)
                        }
                        if modelName == nil {
                            if let enumStr = parsed.modelEnumStr, let mapped = cleanAndMapModelName(enumStr) {
                                modelName = mapped
                            } else if let enumId = parsed.modelEnumId {
                                modelName = mapModelEnumId(enumId)
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
                    cachedInputTokens: cachedTokens,
                    isGcpOrigin: isGcpOrigin,
                    isExplicitConsumer: false,
                    hasProtobufMetadata: hasProtobufMetadata
                ))
            }
        }
        sqlite3_finalize(genStmt)
        
        let convData = DbConversationData(conversationId: convId, startTime: startTime, generations: generations)
        return ConversationCacheEntry(
            modificationDate: job.modDate,
            fileSize: job.fileSize,
            walModificationDate: job.walModDate,
            walFileSize: job.walFileSize,
            conversationData: convData,
            toolCounts: toolCounts
        )
    }
    
    private static func loadConversationsAndToolStats(
        conversationsDir: String,
        isGcpOrigin: Bool = false,
        includeToolStats: Bool = false
    ) async -> ([String: DbConversationData], [ToolStat], Bool) {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: conversationsDir, isDirectory: true)
        guard let urls = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ([:], [], false)
        }

        // Single bulk pass to collect .db and .db-wal metadata (eliminates hundreds of per-file stat syscalls)
        var walInfo: [String: (modDate: Date, size: Int64)] = [:]
        var dbURLs: [(url: URL, modDate: Date, size: Int64)] = []
        dbURLs.reserveCapacity(urls.count)

        for url in urls {
            let name = url.lastPathComponent
            let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modDate = vals?.contentModificationDate ?? Date.distantPast
            let size = Int64(vals?.fileSize ?? 0)
            if name.hasSuffix(".db-wal") {
                walInfo[url.path] = (modDate, size)
            } else if name.hasSuffix(".db") {
                dbURLs.append((url: url, modDate: modDate, size: size))
            }
        }
        guard !dbURLs.isEmpty else { return ([:], [], false) }

        // Single lock acquisition to partition cache hits from misses
        let cacheSnapshot = conversationCacheLock.withLock { conversationCache }

        var conversationsDict: [String: DbConversationData] = [:]
        conversationsDict.reserveCapacity(dbURLs.count)
        var aggregatedTools: [String: Int] = [:]
        var missJobs: [DbFileJob] = []

        for item in dbURLs {
            let dbPath = item.url.path
            let walPath = dbPath + "-wal"
            let wal = walInfo[walPath]
            if let cached = cacheSnapshot[dbPath],
               cached.modificationDate == item.modDate,
               cached.fileSize == item.size,
               cached.walModificationDate == wal?.modDate,
               cached.walFileSize == wal?.size {
                conversationsDict[cached.conversationData.conversationId] = cached.conversationData
                for (tool, count) in cached.toolCounts {
                    aggregatedTools[tool, default: 0] += count
                }
            } else {
                missJobs.append(DbFileJob(
                    file: item.url.lastPathComponent,
                    dbPath: dbPath,
                    modDate: item.modDate,
                    fileSize: item.size,
                    walModDate: wal?.modDate,
                    walFileSize: wal?.size,
                    walExists: wal != nil
                ))
            }
        }

        let anyMiss = !missJobs.isEmpty
        if anyMiss {
            // Bounded worker pool (avoids opening 500+ SQLite connections & thrashing locks simultaneously)
            let maxConcurrency = min(8, max(2, ProcessInfo.processInfo.activeProcessorCount))
            let parsedEntries: [(String, ConversationCacheEntry)] = await withTaskGroup(of: (String, ConversationCacheEntry).self) { group in
                var nextIdx = 0
                let initialBatch = min(maxConcurrency, missJobs.count)
                while nextIdx < initialBatch {
                    let job = missJobs[nextIdx]
                    nextIdx += 1
                    group.addTask {
                        let entry = parseDbConversationUncached(job: job, isGcpOrigin: isGcpOrigin, includeToolStats: includeToolStats)
                        return (job.dbPath, entry)
                    }
                }
                var collected: [(String, ConversationCacheEntry)] = []
                collected.reserveCapacity(missJobs.count)
                while let result = await group.next() {
                    collected.append(result)
                    if nextIdx < missJobs.count {
                        let job = missJobs[nextIdx]
                        nextIdx += 1
                        group.addTask {
                            let entry = parseDbConversationUncached(job: job, isGcpOrigin: isGcpOrigin, includeToolStats: includeToolStats)
                            return (job.dbPath, entry)
                        }
                    }
                }
                return collected
            }

            conversationCacheLock.withLock {
                for (dbPath, entry) in parsedEntries {
                    conversationCache[dbPath] = entry
                }
            }

            for (_, entry) in parsedEntries {
                conversationsDict[entry.conversationData.conversationId] = entry.conversationData
                for (tool, count) in entry.toolCounts {
                    aggregatedTools[tool, default: 0] += count
                }
            }
        }
        
        let toolStats = aggregatedTools.map { ToolStat(toolName: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
            
        return (conversationsDict, toolStats, anyMiss)
    }
    
    static func cleanAndMapModelName(_ name: String) -> String? {
        let cleaned = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let mappings: [(pattern: String, modelName: String)] = [
            // Orchestrator variants
            ("orchestrator (neon)", "Orchestrator (Neon)"),
            ("orchestrator-neon", "Orchestrator (Neon)"),
            ("orchestrator (argon)", "Orchestrator (Argon)"),
            ("orchestrator-argon", "Orchestrator (Argon)"),

            // Gemini 4 Neon (Standard API pricing: $3.00 / $15.00 / $0.15)
            ("gemini-4-neon-xhigh", "Gemini 4 Neon (XHigh)"),
            ("gemini-4-neon-low", "Gemini 4 Neon (Low)"),
            ("gemini-4-neon-medium", "Gemini 4 Neon (Medium)"),
            ("gemini-4-neon-high", "Gemini 4 Neon (High)"),
            ("gemini-4-neon", "Gemini 4 Neon (High)"),
            ("gemini4neon-xhigh", "Gemini 4 Neon (XHigh)"),
            ("gemini4neon-low", "Gemini 4 Neon (Low)"),
            ("gemini4neon-medium", "Gemini 4 Neon (Medium)"),
            ("gemini4neon-high", "Gemini 4 Neon (High)"),
            ("gemini4neon", "Gemini 4 Neon (High)"),
            ("gemini 4 neon (xhigh)", "Gemini 4 Neon (XHigh)"),
            ("gemini 4 neon (low)", "Gemini 4 Neon (Low)"),
            ("gemini 4 neon (medium)", "Gemini 4 Neon (Medium)"),
            ("gemini 4 neon (high)", "Gemini 4 Neon (High)"),
            ("gemini 4 neon", "Gemini 4 Neon (High)"),
            ("gemini neon", "Gemini 4 Neon (High)"),
            ("neon-xhigh", "Gemini 4 Neon (XHigh)"),
            ("neon-low", "Gemini 4 Neon (Low)"),
            ("neon-medium", "Gemini 4 Neon (Medium)"),
            ("neon-high", "Gemini 4 Neon (High)"),
            ("neon", "Gemini 4 Neon (High)"),

            // Gemini 4 Hydrogen (Standard API pricing: $1.50 / $7.50 / $0.075)
            ("gemini-4-hydrogen-xhigh", "Gemini 4 Hydrogen (XHigh)"),
            ("gemini-4-hydrogen-low", "Gemini 4 Hydrogen (Low)"),
            ("gemini-4-hydrogen-medium", "Gemini 4 Hydrogen (Medium)"),
            ("gemini-4-hydrogen-high", "Gemini 4 Hydrogen (High)"),
            ("gemini-4-hydrogen", "Gemini 4 Hydrogen (High)"),
            ("gemini4hydrogen-xhigh", "Gemini 4 Hydrogen (XHigh)"),
            ("gemini4hydrogen-low", "Gemini 4 Hydrogen (Low)"),
            ("gemini4hydrogen-medium", "Gemini 4 Hydrogen (Medium)"),
            ("gemini4hydrogen-high", "Gemini 4 Hydrogen (High)"),
            ("gemini4hydrogen", "Gemini 4 Hydrogen (High)"),
            ("gemini 4 hydrogen (xhigh)", "Gemini 4 Hydrogen (XHigh)"),
            ("gemini 4 hydrogen (low)", "Gemini 4 Hydrogen (Low)"),
            ("gemini 4 hydrogen (medium)", "Gemini 4 Hydrogen (Medium)"),
            ("gemini 4 hydrogen (high)", "Gemini 4 Hydrogen (High)"),
            ("gemini 4 hydrogen", "Gemini 4 Hydrogen (High)"),
            ("gemini hydrogen", "Gemini 4 Hydrogen (High)"),
            ("hydrogen-xhigh", "Gemini 4 Hydrogen (XHigh)"),
            ("hydrogen-low", "Gemini 4 Hydrogen (Low)"),
            ("hydrogen-medium", "Gemini 4 Hydrogen (Medium)"),
            ("hydrogen-high", "Gemini 4 Hydrogen (High)"),
            ("hydrogen", "Gemini 4 Hydrogen (High)"),

            // Gemini 4 / Carbon (Frontier Reasoning)
            ("gemini-4-carbon-low", "Gemini 4 Carbon (Low)"),
            ("gemini-4-carbon-medium", "Gemini 4 Carbon (Medium)"),
            ("gemini-4-carbon-high", "Gemini 4 Carbon (High)"),
            ("gemini-4-carbon", "Gemini 4 Carbon (High)"),
            ("gemini4carbon-low", "Gemini 4 Carbon (Low)"),
            ("gemini4carbon-medium", "Gemini 4 Carbon (Medium)"),
            ("gemini4carbon-high", "Gemini 4 Carbon (High)"),
            ("gemini4carbon", "Gemini 4 Carbon (High)"),
            ("gemini-carbon-low", "Gemini 4 Carbon (Low)"),
            ("gemini-carbon-medium", "Gemini 4 Carbon (Medium)"),
            ("gemini-carbon-high", "Gemini 4 Carbon (High)"),
            ("gemini-carbon", "Gemini 4 Carbon (High)"),
            ("gemini 4 carbon (low)", "Gemini 4 Carbon (Low)"),
            ("gemini 4 carbon (medium)", "Gemini 4 Carbon (Medium)"),
            ("gemini 4 carbon (high)", "Gemini 4 Carbon (High)"),
            ("gemini 4 carbon", "Gemini 4 Carbon (High)"),
            ("gemini carbon (low)", "Gemini 4 Carbon (Low)"),
            ("gemini carbon (medium)", "Gemini 4 Carbon (Medium)"),
            ("gemini carbon (high)", "Gemini 4 Carbon (High)"),
            ("gemini carbon", "Gemini 4 Carbon (High)"),
            ("carbon-low", "Gemini 4 Carbon (Low)"),
            ("carbon-medium", "Gemini 4 Carbon (Medium)"),
            ("carbon-high", "Gemini 4 Carbon (High)"),
            ("carbon", "Gemini 4 Carbon (High)"),

            // Gemini 4 / Argon (Frontier)
            ("gemini-4-argon-low", "Gemini 4 Argon (Low)"),
            ("gemini-4-argon-medium", "Gemini 4 Argon (Medium)"),
            ("gemini-4-argon-high", "Gemini 4 Argon (High)"),
            ("gemini-4-argon", "Gemini 4 Argon (High)"),
            ("gemini-argon-low", "Gemini 4 Argon (Low)"),
            ("gemini-argon-medium", "Gemini 4 Argon (Medium)"),
            ("gemini-argon-high", "Gemini 4 Argon (High)"),
            ("gemini-argon", "Gemini 4 Argon (High)"),
            ("argon-low", "Gemini 4 Argon (Low)"),
            ("argon-medium", "Gemini 4 Argon (Medium)"),
            ("argon-high", "Gemini 4 Argon (High)"),
            ("argon", "Gemini 4 Argon (High)"),
            ("gemini-4", "Gemini 4 Argon (High)"),

            // Claude 5.5 Series (Sonnet & Opus)
            ("claude-opus-5-5-low", "Claude Opus 5.5 (Low)"),
            ("claude-opus-5.5-low", "Claude Opus 5.5 (Low)"),
            ("opus-5-5-low", "Claude Opus 5.5 (Low)"),
            ("opus-5.5-low", "Claude Opus 5.5 (Low)"),
            ("claude-opus-5-5-medium", "Claude Opus 5.5 (Medium)"),
            ("claude-opus-5.5-medium", "Claude Opus 5.5 (Medium)"),
            ("opus-5-5-medium", "Claude Opus 5.5 (Medium)"),
            ("opus-5.5-medium", "Claude Opus 5.5 (Medium)"),
            ("claude-opus-5-5-high", "Claude Opus 5.5 (High)"),
            ("claude-opus-5.5-high", "Claude Opus 5.5 (High)"),
            ("opus-5-5-high", "Claude Opus 5.5 (High)"),
            ("opus-5.5-high", "Claude Opus 5.5 (High)"),
            ("claude-opus-5-5", "Claude Opus 5.5 (High)"),
            ("claude-opus-5.5", "Claude Opus 5.5 (High)"),
            ("opus-5.5", "Claude Opus 5.5 (High)"),
            ("opus-5-5", "Claude Opus 5.5 (High)"),
            ("opus-5", "Claude Opus 5.5 (High)"),

            ("claude-sonnet-5-5-low", "Claude Sonnet 5.5 (Low)"),
            ("claude-sonnet-5.5-low", "Claude Sonnet 5.5 (Low)"),
            ("sonnet-5-5-low", "Claude Sonnet 5.5 (Low)"),
            ("sonnet-5.5-low", "Claude Sonnet 5.5 (Low)"),
            ("claude-sonnet-5-5-medium", "Claude Sonnet 5.5 (Medium)"),
            ("claude-sonnet-5.5-medium", "Claude Sonnet 5.5 (Medium)"),
            ("sonnet-5-5-medium", "Claude Sonnet 5.5 (Medium)"),
            ("sonnet-5.5-medium", "Claude Sonnet 5.5 (Medium)"),
            ("claude-sonnet-5-5-high", "Claude Sonnet 5.5 (High)"),
            ("claude-sonnet-5.5-high", "Claude Sonnet 5.5 (High)"),
            ("sonnet-5-5-high", "Claude Sonnet 5.5 (High)"),
            ("sonnet-5.5-high", "Claude Sonnet 5.5 (High)"),
            ("claude-sonnet-5-5", "Claude Sonnet 5.5 (High)"),
            ("claude-sonnet-5.5", "Claude Sonnet 5.5 (High)"),
            ("sonnet-5.5", "Claude Sonnet 5.5 (High)"),
            ("sonnet-5-5", "Claude Sonnet 5.5 (High)"),
            ("sonnet-5", "Claude Sonnet 5.5 (High)"),

            // Legacy Claude 4.6 (Historical)
            ("claude-sonnet-4-6", "Claude Sonnet 4.6 (Thinking)"),
            ("claude-sonnet-4.6", "Claude Sonnet 4.6 (Thinking)"),
            ("sonnet-4-6", "Claude Sonnet 4.6 (Thinking)"),
            ("sonnet-4.6", "Claude Sonnet 4.6 (Thinking)"),
            ("sonnet-4", "Claude Sonnet 4.6 (Thinking)"),
            ("claude-opus-4-6", "Claude Opus 4.6 (Thinking)"),
            ("claude-opus-4.6", "Claude Opus 4.6 (Thinking)"),
            ("opus-4-6", "Claude Opus 4.6 (Thinking)"),
            ("opus-4.6", "Claude Opus 4.6 (Thinking)"),
            ("opus-4", "Claude Opus 4.6 (Thinking)"),

            // Generic fallbacks
            ("opus", "Claude Opus 5.5 (High)"),
            ("sonnet", "Claude Sonnet 5.5 (High)"),

            // Open Source
            ("gpt-oss-120b", "GPT-OSS 120B (Medium)"),
            ("gpt-oss", "GPT-OSS 120B (Medium)"),
            ("oss-120b", "GPT-OSS 120B (Medium)"),

            // Gemini 3.8 Series
            ("gemini-3.8-flash-low", "Gemini 3.8 Flash (Low)"),
            ("gemini-3.8-flash-medium", "Gemini 3.8 Flash (Medium)"),
            ("gemini-3.8-flash-high", "Gemini 3.8 Flash (High)"),
            ("gemini-3.8-flash-cyber", "Gemini 3.8 Flash Cyber"),
            ("3.8-flash-cyber", "Gemini 3.8 Flash Cyber"),
            ("gemini-3.8-flash", "Gemini 3.8 Flash (High)"),
            ("gemini-3.8", "Gemini 3.8 Flash (High)"),
            ("3.8-flash", "Gemini 3.8 Flash (High)"),
            ("flash-3.8", "Gemini 3.8 Flash (High)"),

            // Gemini 3.7 Series
            ("gemini-3.7-flash-low", "Gemini 3.7 Flash (Low)"),
            ("gemini-3.7-flash-medium", "Gemini 3.7 Flash (Medium)"),
            ("gemini-3.7-flash-high", "Gemini 3.7 Flash (High)"),
            ("gemini-3.7-flash", "Gemini 3.7 Flash (High)"),
            ("gemini-3.7", "Gemini 3.7 Flash (High)"),
            ("3.7-flash", "Gemini 3.7 Flash (High)"),
            ("flash-3.7", "Gemini 3.7 Flash (High)"),

            // Gemini 3.6 Series
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

            // Gemini 3.1 Pro Series
            ("gemini-3-pro-low", "Gemini 3.1 Pro (Low)"),
            ("pro-low", "Gemini 3.1 Pro (Low)"),
            ("gemini-3-pro-high", "Gemini 3.1 Pro (High)"),
            ("pro-high", "Gemini 3.1 Pro (High)"),
            ("gemini-3.1-pro-preview", "Gemini 3.1 Pro (High)"),
            ("gemini-3.1-pro", "Gemini 3.1 Pro (High)"),
            ("gemini-3.1", "Gemini 3.1 Pro (High)"),
            ("gemini-1.5-pro", "Gemini 3.1 Pro (High)"),

            // Official AGY MODEL_PLACEHOLDER_* mappings (verified against GetUserStatus & SQLite DBs)
            ("model_placeholder_m532", "Gemini 4 Neon (High)"),
            ("model_placeholder_m533", "Gemini 4 Neon (Medium)"),
            ("model_placeholder_m534", "Gemini 4 Neon (Low)"),
            ("model_placeholder_m535", "Gemini 4 Neon (XHigh)"),
            ("model_placeholder_m537", "Orchestrator (Neon)"),
            ("model_placeholder_m525", "Gemini 4 Hydrogen (High)"),
            ("model_placeholder_m526", "Gemini 4 Hydrogen (Medium)"),
            ("model_placeholder_m527", "Gemini 4 Hydrogen (Low)"),
            ("model_placeholder_m528", "Gemini 4 Hydrogen (XHigh)"),
            ("model_placeholder_m461", "Gemini 4 Hydrogen (High)"),
            ("model_placeholder_m462", "Gemini 4 Hydrogen (High)"),
            ("model_placeholder_m437", "Gemini 4 Carbon (High)"),
            ("model_placeholder_m670", "Gemini 4 Carbon (High)"),
            ("model_placeholder_m417", "Gemini 4 Argon (High)"),
            ("model_placeholder_m418", "Gemini 4 Argon (High)"),
            ("model_placeholder_m419", "Gemini 4 Argon (Low)"),
            ("model_placeholder_m668", "Orchestrator (Argon)"),
            ("model_placeholder_m400", "Claude Opus 5.5 (Low)"),
            ("model_placeholder_m401", "Claude Opus 5.5 (Medium)"),
            ("model_placeholder_m402", "Claude Opus 5.5 (High)"),
            ("model_placeholder_m403", "Claude Sonnet 5.5 (Low)"),
            ("model_placeholder_m404", "Claude Sonnet 5.5 (Medium)"),
            ("model_placeholder_m405", "Claude Sonnet 5.5 (High)"),
            ("model_placeholder_m318", "Gemini 3.8 Flash (High)"),
            ("model_placeholder_m319", "Gemini 3.8 Flash (High)"),
            ("model_placeholder_m320", "Gemini 3.8 Flash (Low)"),
            ("model_placeholder_m299", "Gemini 3.7 Flash (High)"),

            // Shorthands
            ("gemini-3.5-flash-lite", "Gemini 3.5 Flash Lite"),
            ("3.5-flash-lite", "Gemini 3.5 Flash Lite"),
            ("flash-lite", "Gemini 3.5 Flash Lite"),
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
            "Gemini 4 Neon (Low)",
            "Gemini 4 Neon (Medium)",
            "Gemini 4 Neon (High)",
            "Gemini 4 Neon (XHigh)",
            "Orchestrator (Neon)",
            "Gemini 4 Hydrogen (Low)",
            "Gemini 4 Hydrogen (Medium)",
            "Gemini 4 Hydrogen (High)",
            "Gemini 4 Hydrogen (XHigh)",
            "Gemini 4 Carbon (Low)",
            "Gemini 4 Carbon (Medium)",
            "Gemini 4 Carbon (High)",
            "Gemini 4 Argon (Low)",
            "Gemini 4 Argon (Medium)",
            "Gemini 4 Argon (High)",
            "Orchestrator (Argon)",
            "Claude Sonnet 5.5 (Low)",
            "Claude Sonnet 5.5 (Medium)",
            "Claude Sonnet 5.5 (High)",
            "Claude Opus 5.5 (Low)",
            "Claude Opus 5.5 (Medium)",
            "Claude Opus 5.5 (High)",
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
            "Gemini 3.5 Flash Lite",
            "Gemini 3.5 Flash (Low)",
            "Gemini 3.5 Flash (Medium)",
            "Gemini 3.5 Flash (High)",
            "Gemini 3.1 Pro (Low)",
            "Gemini 3.1 Pro (High)",
            "Claude Sonnet 4.6 (Thinking)",
            "Claude Opus 4.6 (Thinking)",
            "GPT-OSS 120B (Medium)",
            "GPT-OSS-120B"
        ]
        for knownName in knownModelNames {
            if cleaned.contains(knownName.lowercased()) {
                return knownName
            }
        }
        
        return nil
    }
    
    static func enforceDateModelValidity(modelName: String, date: Date, aug2026: Date, sep2026: Date) -> String {
        if date < aug2026 {
            if modelName.contains("3.7") || modelName.contains("3.8") || modelName.contains("Argon") || modelName.contains("Carbon") || modelName.contains("Hydrogen") || modelName.contains("Neon") {
                return "Gemini 3.6 Flash (High)"
            }
            if modelName.contains("5.5") {
                return modelName.contains("Opus") ? "Claude Opus 4.6 (Thinking)" : "Claude Sonnet 4.6 (Thinking)"
            }
        } else if date < sep2026 {
            if modelName.contains("3.8") || modelName.contains("Argon") || modelName.contains("Carbon") || modelName.contains("Hydrogen") || modelName.contains("Neon") {
                return "Gemini 3.7 Flash (High)"
            }
            if modelName.contains("5.5") {
                return modelName.contains("Opus") ? "Claude Opus 4.6 (Thinking)" : "Claude Sonnet 4.6 (Thinking)"
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
