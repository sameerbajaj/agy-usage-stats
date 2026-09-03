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
            let logDir = (expandedDir as NSString).appendingPathComponent("log")
            
            print("AgyStatsService: --- Loading Stats ---")
            print("AgyStatsService: cliDir = \(cliDir)")
            print("AgyStatsService: NSHomeDirectory = \(NSHomeDirectory())")
            print("AgyStatsService: expandedDir = \(expandedDir)")
            print("AgyStatsService: historyPath = \(historyPath)")
            print("AgyStatsService: settingsPath = \(settingsPath)")
            print("AgyStatsService: conversationsDir = \(conversationsDir)")
            print("AgyStatsService: logDir = \(logDir)")
            
            // Load Settings & Auth Transitions
            let settings = loadSettings(at: settingsPath)
            let currentIsGcp = settings.gcp?.project != nil && !(settings.gcp?.project?.isEmpty ?? true)
            let authTransitions = loadAuthTransitions(logDir: logDir, defaultProject: settings.gcp?.project)
            print("AgyStatsService: Loaded settings: model=\(settings.model ?? "nil"), gcp=\(settings.gcp?.project ?? "none"), transitions=\(authTransitions.count)")
            
            // Load History Lines
            var (loadedQueries, workspaces, lastQuery) = loadHistory(at: historyPath)
            print("AgyStatsService: Loaded history: queries count = \(loadedQueries.count), workspaces count = \(workspaces.count)")
            
            // Date-aware fallback thresholds: Gemini 3.7 Flash on August 1, 2026; Gemini 3.8 Flash on September 2, 2026
            let calendar = Calendar.current
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
            
            // Load all SQLite conversation databases (ground truth for all turns, subagents, and tokens)
            let allDbConversations = loadAllDbConversations(conversationsDir: conversationsDir)
            
            var convStartMap: [Int: String] = [:]
            for (cid, conv) in allDbConversations {
                if let st = conv.startTime {
                    convStartMap[Int(floor(st.timeIntervalSince1970))] = cid
                }
            }
            
            // Load DB metadata and exact model names from SQLite for all available queries
            var queriesWithMeta: [QueryEntry] = []
            
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
                
                let resolvedConvId = q.conversationId ?? findConversationId(for: q.timestamp, in: convStartMap)
                newQ.conversationId = resolvedConvId
                
                if let conversationId = resolvedConvId, let convData = allDbConversations[conversationId] {
                    // Align queries with second-resolution timestamps in gen_metadata
                    let start = Date(timeIntervalSince1970: floor(q.timestamp.timeIntervalSince1970))
                    
                    // Find the next chronological query in the same conversation to establish the time window (max 30 mins)
                    var end = start.addingTimeInterval(1800)
                    for i in (0..<index).reversed() {
                        let nextQ = queries[i]
                        let nextConvId = nextQ.conversationId ?? findConversationId(for: nextQ.timestamp, in: convStartMap)
                        if nextConvId == conversationId {
                            let nextStart = Date(timeIntervalSince1970: floor(nextQ.timestamp.timeIntervalSince1970))
                            if nextStart > start {
                                end = min(end, nextStart)
                                break
                            }
                        }
                    }
                    
                    // Primary conversation generations in this query's time window [start, end)
                    let primaryGens = convData.generations.filter { gen in
                        guard let gTs = gen.timestamp else { return false }
                        return gTs >= start && gTs < end
                    }
                    
                    // Subagent conversations spawned during this query window
                    let subagentGens = allDbConversations.values.filter { other in
                        guard other.conversationId != conversationId,
                              let otherStart = other.startTime else { return false }
                        return otherStart >= start && otherStart < end
                    }.flatMap { $0.generations }
                    
                    let turnGens = primaryGens + subagentGens
                    
                    if !turnGens.isEmpty {
                        let llmCalls = turnGens.count
                        let totalOutputBytes = turnGens.reduce(0) { $0 + $1.size }
                        let totalInTokens = turnGens.compactMap { $0.inputTokens }.reduce(0, +)
                        let totalOutTokens = turnGens.compactMap { $0.outputTokens }.reduce(0, +)
                        let totalCachedTokens = turnGens.compactMap { $0.cachedInputTokens }.reduce(0, +)
                        newQ.conversationMeta = ConversationDbMeta(
                            llmCalls: llmCalls,
                            totalOutputBytes: totalOutputBytes,
                            inputTokens: totalInTokens,
                            outputTokens: totalOutTokens,
                            cachedInputTokens: totalCachedTokens
                        )
                        
                        let turnModels = turnGens.compactMap { $0.modelName }
                        if let model = turnModels.last {
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
                let authState = authAt(
                    date: q.timestamp,
                    transitions: authTransitions,
                    currentIsGcp: currentIsGcp,
                    currentEmail: nil,
                    currentProject: settings.gcp?.project
                )
                newQ.isGcp = authState.isGcp
                newQ.gcpProject = authState.gcpProject
                newQ.accountEmail = authState.email
                queriesWithMeta.append(newQ)
            }
            
            // Count queries today and this week
            let now = Date()
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
            
            let dayKeyFormatter = DateFormatter()
            dayKeyFormatter.dateFormat = "yyyy-MM-dd"
            
            let dayLabelFormatter = DateFormatter()
            dayLabelFormatter.dateFormat = "EEE, MMM d"
            
            let dayShortLabelFormatter = DateFormatter()
            dayShortLabelFormatter.dateFormat = "MMM d"
            
            let monthKeyFormatter = DateFormatter()
            monthKeyFormatter.dateFormat = "yyyy-MM"
            
            let monthLabelFormatter = DateFormatter()
            monthLabelFormatter.dateFormat = "MMMM yyyy"
            
            let monthShortLabelFormatter = DateFormatter()
            monthShortLabelFormatter.dateFormat = "MMM ''yy"
            
            var dailyBuckets: [String: UsageTimeBucket] = [:]
            var monthlyBuckets: [String: UsageTimeBucket] = [:]
            
            // 2. Aggregate all actual LLM generations from all SQLite databases (ground truth for parent + subagents)
            let allGenerations = allDbConversations.values.flatMap { $0.generations }
            var daysWithDbGens = Set<String>()
            for gen in allGenerations {
                if let gTs = gen.timestamp {
                    daysWithDbGens.insert(dayKeyFormatter.string(from: gTs))
                }
            }
            
            // 1. Initialize buckets, query counts, and fallback estimates for older queries lacking SQLite DB files
            for q in queriesWithMeta {
                let authState = authAt(
                    date: q.timestamp,
                    transitions: authTransitions,
                    currentIsGcp: currentIsGcp,
                    currentEmail: quotaInfo?.email,
                    currentProject: settings.gcp?.project
                )
                let accName = authState.accountDisplayName
                
                let dayKey = dayKeyFormatter.string(from: q.timestamp)
                let startOfDay = calendar.startOfDay(for: q.timestamp)
                var dayBucket = dailyBuckets[dayKey] ?? UsageTimeBucket(
                    periodKey: dayKey,
                    label: dayLabelFormatter.string(from: q.timestamp),
                    shortLabel: dayShortLabelFormatter.string(from: q.timestamp),
                    date: startOfDay
                )
                dayBucket.queryCount += 1
                dayBucket.accountQueryBreakdown[accName, default: 0] += 1
                if let mName = q.modelName {
                    dayBucket.modelQueryBreakdown[mName, default: 0] += 1
                }
                
                // Fallback for days with no SQLite DBs (e.g. May/June 2026): estimate tokens & cost from query
                if !daysWithDbGens.contains(dayKey) {
                    let name = q.modelName ?? "Gemini 3.6 Flash (High)"
                    let cleaned = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let model = knownModels.first(where: {
                        let mName = $0.name.lowercased()
                        return cleaned.contains(mName) || mName.contains(cleaned)
                    }) ?? defaultGeminiModel
                    
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
                dailyBuckets[dayKey] = dayBucket
                
                let monthKey = monthKeyFormatter.string(from: q.timestamp)
                let components = calendar.dateComponents([.year, .month], from: q.timestamp)
                let startOfMonth = calendar.date(from: components) ?? q.timestamp
                var monthBucket = monthlyBuckets[monthKey] ?? UsageTimeBucket(
                    periodKey: monthKey,
                    label: monthLabelFormatter.string(from: q.timestamp),
                    shortLabel: monthShortLabelFormatter.string(from: q.timestamp),
                    date: startOfMonth
                )
                monthBucket.queryCount += 1
                monthBucket.accountQueryBreakdown[accName, default: 0] += 1
                if let mName = q.modelName {
                    monthBucket.modelQueryBreakdown[mName, default: 0] += 1
                }
                if !daysWithDbGens.contains(dayKey) {
                    let name = q.modelName ?? "Gemini 3.6 Flash (High)"
                    let cleaned = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    let model = knownModels.first(where: {
                        let mName = $0.name.lowercased()
                        return cleaned.contains(mName) || mName.contains(cleaned)
                    }) ?? defaultGeminiModel
                    
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
                monthlyBuckets[monthKey] = monthBucket
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
                let cleaned = validName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let model = knownModels.first(where: {
                    let mName = $0.name.lowercased()
                    return cleaned.contains(mName) || mName.contains(cleaned)
                }) ?? (genDate >= sep2026 ? defaultGeminiModel : (knownModels.first(where: { $0.name == "Gemini 3.7 Flash (High)" }) ?? defaultGeminiModel))
                
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
                
                let authState = authAt(
                    date: genDate,
                    transitions: authTransitions,
                    currentIsGcp: currentIsGcp,
                    currentEmail: quotaInfo?.email,
                    currentProject: settings.gcp?.project
                )
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
                
                let dayKey = dayKeyFormatter.string(from: genDate)
                let startOfDay = calendar.startOfDay(for: genDate)
                var dayBucket = dailyBuckets[dayKey] ?? UsageTimeBucket(
                    periodKey: dayKey,
                    label: dayLabelFormatter.string(from: genDate),
                    shortLabel: dayShortLabelFormatter.string(from: genDate),
                    date: startOfDay
                )
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
                dailyBuckets[dayKey] = dayBucket
                
                let monthKey = monthKeyFormatter.string(from: genDate)
                let components = calendar.dateComponents([.year, .month], from: genDate)
                let startOfMonth = calendar.date(from: components) ?? genDate
                var monthBucket = monthlyBuckets[monthKey] ?? UsageTimeBucket(
                    periodKey: monthKey,
                    label: monthLabelFormatter.string(from: genDate),
                    shortLabel: monthShortLabelFormatter.string(from: genDate),
                    date: startOfMonth
                )
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
                monthlyBuckets[monthKey] = monthBucket
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
                let key = dayKeyFormatter.string(from: dayCursor)
                if dailyBuckets[key] == nil {
                    dailyBuckets[key] = UsageTimeBucket(
                        periodKey: key,
                        label: dayLabelFormatter.string(from: dayCursor),
                        shortLabel: dayShortLabelFormatter.string(from: dayCursor),
                        date: dayCursor
                    )
                }
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayCursor) else { break }
                dayCursor = nextDay
            }
            
            let sortedDaily = dailyBuckets.values.sorted { $0.date < $1.date }
            let sortedMonthly = monthlyBuckets.values.sorted { $0.date < $1.date }
            
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
        var transitions: [AuthTransition] = []
        var lastIsGcp: Bool? = nil
        var lastEmail: String? = nil
        var lastProject: String? = nil
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        dateFormatter.timeZone = TimeZone.current
        
        let emailRegex = try? NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        
        for file in logFiles {
            let stripped = file.replacingOccurrences(of: "cli-", with: "").replacingOccurrences(of: ".log", with: "")
            guard let date = dateFormatter.date(from: stripped) else { continue }
            
            let fullPath = (logDir as NSString).appendingPathComponent(file)
            guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: fullPath)) else { continue }
            let data = handle.readData(ofLength: 65536)
            try? handle.close()
            
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else { continue }
            let isGcp = text.contains("aiplatform") || text.contains("clawdbot") || text.contains("EnterProject") || text.contains("GCP setup completed")
            let project = isGcp ? (defaultProject ?? "clawdbot-485304") : nil
            
            var email: String? = nil
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
            
            if lastIsGcp != isGcp || (email != nil && email != lastEmail) || project != lastProject {
                transitions.append(AuthTransition(timestamp: date, isGcp: isGcp, email: email, gcpProject: project))
                lastIsGcp = isGcp
                lastEmail = email
                lastProject = project
            }
        }
        
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
    
    private struct DbGeneration {
        let idx: Int
        let size: Int
        let timestamp: Date?
        let modelName: String?
        let inputTokens: Int?
        let outputTokens: Int?
        let cachedInputTokens: Int?
    }
    
    private struct DbConversationData {
        let conversationId: String
        let startTime: Date?
        let generations: [DbGeneration]
    }
    
    private static func loadConversationStartsIndex(conversationsDir: String) -> [Int: String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: conversationsDir) else {
            return [:]
        }
        
        var indexMap: [Int: String] = [:]
        let dbFiles = files.filter { $0.hasSuffix(".db") }
        
        for file in dbFiles {
            let convId = (file as NSString).deletingPathExtension
            let dbPath = (conversationsDir as NSString).appendingPathComponent(file)
            
            var db: OpaquePointer?
            let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
            guard sqlite3_open_v2("file:\(dbPath)?immutable=1", &db, flags, nil) == SQLITE_OK else {
                sqlite3_close(db)
                continue
            }
            
            var stmt: OpaquePointer?
            let query = "SELECT metadata FROM steps ORDER BY idx ASC LIMIT 1"
            if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    if let blob = sqlite3_column_blob(stmt, 0) {
                        let blobSize = sqlite3_column_bytes(stmt, 0)
                        if blobSize > 0 {
                            let data = Data(bytes: blob, count: Int(blobSize))
                            if let msg = ProtobufMessage.parse(data: data),
                               let sub = msg.submessage(for: 1),
                               let seconds = sub.firstVarint(for: 1) {
                                indexMap[seconds] = convId
                            }
                        }
                    }
                }
            }
            sqlite3_finalize(stmt)
            sqlite3_close(db)
        }
        
        return indexMap
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
    
    private static func loadDbConversationData(conversationId: String, cliDir: String) -> DbConversationData {
        let dbPath = (cliDir as NSString).appendingPathComponent("conversations/\(conversationId).db")
        
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2("file:\(dbPath)?immutable=1", &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return DbConversationData(conversationId: conversationId, startTime: nil, generations: [])
        }
        defer { sqlite3_close(db) }
        
        // 1. Load step timestamps from steps table
        var startTime: Date? = nil
        var stepsTimestamps: [Int: Date] = [:]
        var stepsStmt: OpaquePointer?
        let stepsQuery = "SELECT idx, metadata FROM steps ORDER BY idx ASC"
        if sqlite3_prepare_v2(db, stepsQuery, -1, &stepsStmt, nil) == SQLITE_OK {
            while sqlite3_step(stepsStmt) == SQLITE_ROW {
                let stepIdx = Int(sqlite3_column_int(stepsStmt, 0))
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
        
        return DbConversationData(conversationId: conversationId, startTime: startTime, generations: generations)
    }
    
    private static func loadAllDbConversations(conversationsDir: String) -> [String: DbConversationData] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: conversationsDir) else {
            return [:]
        }
        
        var dict: [String: DbConversationData] = [:]
        let dbFiles = files.filter { $0.hasSuffix(".db") }
        let cliDir = (conversationsDir as NSString).deletingLastPathComponent
        
        for file in dbFiles {
            let convId = (file as NSString).deletingPathExtension
            let convData = loadDbConversationData(conversationId: convId, cliDir: cliDir)
            dict[convId] = convData
        }
        return dict
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
