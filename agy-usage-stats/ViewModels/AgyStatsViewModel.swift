//
//  AgyStatsViewModel.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import Foundation
import SwiftUI
import Observation
import AppKit

public enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable {
    case iconOnly = "Icon Only"
    case quotas = "Quotas (G & C)"
    case iconAndQuotas = "Icon & Quotas"
    case queriesToday = "Queries Today"
    case both = "Icon & Queries"
    
    public var id: String { rawValue }
}

public enum IconModelSelection: String, Codable, CaseIterable, Identifiable {
    case active = "Active Model"
    case mostDepleted = "Most Depleted"
    case gemini = "Gemini"
    case argon = "Gemini 4 Argon"
    case claude = "Claude"
    case both = "Both (G & C)"
    case allThree = "All Three (G, A, C)"
    case gcp = "GCP Cloud Spend"
    
    public var id: String { rawValue }

    public static var primaryCases: [IconModelSelection] {
        [.active, .mostDepleted, .gemini, .argon, .claude]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "Active Model", "active": self = .active
        case "Most Depleted", "mostDepleted": self = .mostDepleted
        case "Gemini", "Gemini Only", "gemini": self = .gemini
        case "Gemini 4 Argon", "argon": self = .argon
        case "Claude", "Claude Only", "claude": self = .claude
        case "Both (G & C)", "both": self = .both
        case "All Three (G, A, C)", "allThree": self = .allThree
        case "GCP Cloud Spend", "gcp": self = .gcp
        default: return nil
        }
    }
}

public enum IconQuotaLimitTarget: String, Codable, CaseIterable, Identifiable {
    case fiveHour = "5-Hour Limit"
    case weekly = "Weekly Limit"
    case auto = "Auto"
    
    public var id: String { rawValue }

    public static let minimum: IconQuotaLimitTarget = .auto

    public init?(rawValue: String) {
        switch rawValue {
        case "5-Hour Limit", "fiveHour": self = .fiveHour
        case "Weekly Limit", "weekly": self = .weekly
        case "Auto", "Auto (Active)", "Minimum (Auto)", "minimum", "auto": self = .auto
        default: return nil
        }
    }
}

public enum IconCircleFillMetric: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly Limit"
    case fiveHour = "5-Hour Limit"
    case matchNumber = "Match Percentage"
    
    public var id: String { rawValue }

    public static let usageRemaining: IconCircleFillMetric = .matchNumber
    public static let timeUntilReset: IconCircleFillMetric = .weekly

    public init?(rawValue: String) {
        switch rawValue {
        case "Weekly Limit", "weekly": self = .weekly
        case "5-Hour Limit", "fiveHour": self = .fiveHour
        case "Match Percentage", "Match Number", "matchNumber", "Usage Remaining", "usageRemaining", "timeUntilReset": self = .matchNumber
        default: return nil
        }
    }
}

public enum MenuBarSpendSource: String, Codable, CaseIterable, Identifiable {
    case gcpToday = "GCP Cloud Spend (Today)"
    case apiToday = "Today's API Spend (All)"
    case gcpTotal = "GCP Cloud Spend (Total)"

    public var id: String { rawValue }
}

public struct WeeklyLimitInfo {
    public let remainingFraction: Double?
    public let resetTimeDescription: String?
}

@Observable
public final class AgyStatsViewModel {
    private let userDefaults: UserDefaults

    // Persistent settings using UserDefaults stored properties
    public var cliDir: String {
        didSet {
            userDefaults.set(cliDir, forKey: "agy_cliDir")
            AgyStatsService.clearCaches()
            restartWatcher()
            Task { await refresh() }
        }
    }
    
    public var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            userDefaults.set(menuBarDisplayMode.rawValue, forKey: "agy_menuBarDisplayMode")
        }
    }
    
    public var showModelUsageInIcon: Bool {
        didSet {
            userDefaults.set(showModelUsageInIcon, forKey: "agy_showModelUsageInIcon")
        }
    }
    
    public var selectedModelForIcon: IconModelSelection {
        didSet {
            userDefaults.set(selectedModelForIcon.rawValue, forKey: "agy_selectedModelForIcon")
        }
    }

    public var iconQuotaLimitTarget: IconQuotaLimitTarget {
        didSet {
            userDefaults.set(iconQuotaLimitTarget.rawValue, forKey: "agy_iconQuotaLimitTarget")
        }
    }

    public var iconCircleFillMetric: IconCircleFillMetric {
        didSet {
            userDefaults.set(iconCircleFillMetric.rawValue, forKey: "agy_iconCircleFillMetric")
        }
    }
    
    public var showWeeklyLimitAndReset: Bool {
        didSet {
            userDefaults.set(showWeeklyLimitAndReset, forKey: "agy_showWeeklyLimitAndReset")
        }
    }

    public var showMenuBarSpend: Bool {
        didSet {
            userDefaults.set(showMenuBarSpend, forKey: "agy_showMenuBarSpend")
        }
    }

    public var menuBarSpendSource: MenuBarSpendSource {
        didSet {
            userDefaults.set(menuBarSpendSource.rawValue, forKey: "agy_menuBarSpendSource")
        }
    }
    
    public var showToolBreakdown: Bool {
        didSet {
            userDefaults.set(showToolBreakdown, forKey: "agy_showToolBreakdown")
        }
    }
    
    public var showCostSummary: Bool {
        didSet {
            userDefaults.set(showCostSummary, forKey: "agy_showCostSummary")
        }
    }
    
    public var selectedTheme: AppTheme {
        didSet {
            userDefaults.set(selectedTheme.rawValue, forKey: "agy_selectedTheme")
        }
    }
    
    public var menuBarAccountTarget: MenuBarAccountTarget {
        didSet {
            userDefaults.set(menuBarAccountTarget.rawValue, forKey: "agy_menuBarAccountTarget")
        }
    }
    
    public var gcpCreditPool: Double {
        didSet {
            userDefaults.set(gcpCreditPool, forKey: "agy_gcpCreditPool")
            resetGcpCreditBaseline()
        }
    }
    
    public var gcpCreditBaselineCost: Double {
        didSet {
            userDefaults.set(gcpCreditBaselineCost, forKey: "agy_gcpCreditBaselineCost")
        }
    }
    
    public var gcpCreditBaselineTimestamp: Double {
        didSet {
            userDefaults.set(gcpCreditBaselineTimestamp, forKey: "agy_gcpCreditBaselineTimestamp")
        }
    }
    
    private var gcpCreditBaselineNeedsMigration: Bool = false
    
    public func resetGcpCreditBaseline() {
        if gcpCreditPool > 0.0 {
            let currentTotal = stats.gcpTotalCost
            self.gcpCreditBaselineCost = currentTotal
            self.gcpCreditBaselineTimestamp = Date().timeIntervalSince1970
            userDefaults.set(currentTotal, forKey: "agy_gcpCreditBaselineCost")
            userDefaults.set(self.gcpCreditBaselineTimestamp, forKey: "agy_gcpCreditBaselineTimestamp")
            self.gcpCreditBaselineNeedsMigration = false
        } else {
            self.gcpCreditBaselineCost = 0.0
            self.gcpCreditBaselineTimestamp = 0.0
            userDefaults.removeObject(forKey: "agy_gcpCreditBaselineCost")
            userDefaults.removeObject(forKey: "agy_gcpCreditBaselineTimestamp")
            self.gcpCreditBaselineNeedsMigration = false
        }
    }
    
    // GCP Credit remaining & consumed calculations based on baseline snapshot
    public var gcpCostSinceBaseline: Double {
        guard gcpCreditPool > 0.0 else { return 0.0 }
        return max(0.0, stats.gcpTotalCost - gcpCreditBaselineCost)
    }
    
    public var gcpCreditRemaining: Double {
        guard gcpCreditPool > 0.0 else { return 0.0 }
        return max(0.0, gcpCreditPool - gcpCostSinceBaseline)
    }
    
    public var gcpCreditConsumedFraction: Double {
        guard gcpCreditPool > 0.0 else { return 0.0 }
        return min(1.0, gcpCostSinceBaseline / gcpCreditPool)
    }
    
    // UI States
    public var stats: AgyUsageStats = .empty
    public var settings: AgySettings = .default
    public var isRefreshing = false
    public var isConnected = false
    public var searchQuery = String()
    
    // Auto-update States
    public var availableUpdate: UpdateInfo? = nil
    public var selfUpdateState: SelfUpdateState = .idle
    public var isCheckingForUpdates = false
    public var updateCheckMessage: String? = nil
    
    // File Watcher
    private let watcher = AgyFileWatcher()
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        // Load default values or fallback
        let savedCliDir = userDefaults.string(forKey: "agy_cliDir")
        self.cliDir = savedCliDir ?? AgyStatsService.getDefaultCliDir()
        
        let savedModeStr = userDefaults.string(forKey: "agy_menuBarDisplayMode")
        if let savedModeStr, let mode = MenuBarDisplayMode(rawValue: savedModeStr) {
            self.menuBarDisplayMode = mode
        } else {
            self.menuBarDisplayMode = .iconOnly
        }
        
        self.showModelUsageInIcon = userDefaults.bool(forKey: "agy_showModelUsageInIcon")
        
        let savedModelForIcon = userDefaults.string(forKey: "agy_selectedModelForIcon")
        if let savedModelForIcon, let modelSel = IconModelSelection(rawValue: savedModelForIcon) {
            self.selectedModelForIcon = modelSel
        } else {
            self.selectedModelForIcon = .active
        }

        let savedLimitTarget = userDefaults.string(forKey: "agy_iconQuotaLimitTarget")
        if let savedLimitTarget, let limitTarget = IconQuotaLimitTarget(rawValue: savedLimitTarget) {
            self.iconQuotaLimitTarget = limitTarget
        } else {
            self.iconQuotaLimitTarget = .auto
        }

        let savedFillMetric = userDefaults.string(forKey: "agy_iconCircleFillMetric")
        if let savedFillMetric, let fillMetric = IconCircleFillMetric(rawValue: savedFillMetric) {
            self.iconCircleFillMetric = fillMetric
        } else {
            self.iconCircleFillMetric = .weekly
        }

        if userDefaults.object(forKey: "agy_showMenuBarSpend") != nil {
            self.showMenuBarSpend = userDefaults.bool(forKey: "agy_showMenuBarSpend")
        } else {
            self.showMenuBarSpend = true
        }

        let savedSpendSource = userDefaults.string(forKey: "agy_menuBarSpendSource")
        if let savedSpendSource, let spendSource = MenuBarSpendSource(rawValue: savedSpendSource) {
            self.menuBarSpendSource = spendSource
        } else {
            self.menuBarSpendSource = .gcpToday
        }
        
        self.showWeeklyLimitAndReset = userDefaults.bool(forKey: "agy_showWeeklyLimitAndReset")
        self.showToolBreakdown = userDefaults.bool(forKey: "agy_showToolBreakdown")
        if userDefaults.object(forKey: "agy_showCostSummary") != nil {
            self.showCostSummary = userDefaults.bool(forKey: "agy_showCostSummary")
        } else {
            self.showCostSummary = true
        }
        
        let savedTheme = userDefaults.string(forKey: "agy_selectedTheme")
        if let savedTheme, let theme = AppTheme(rawValue: savedTheme) {
            self.selectedTheme = theme
        } else {
            self.selectedTheme = .midnight
        }
        
        let savedAccountTarget = userDefaults.string(forKey: "agy_menuBarAccountTarget")
        if let savedAccountTarget, let target = MenuBarAccountTarget(rawValue: savedAccountTarget) {
            self.menuBarAccountTarget = target
        } else {
            self.menuBarAccountTarget = .subscription
        }
        
        if let rawPoolObj = userDefaults.object(forKey: "agy_gcpCreditPool") {
            if let d = rawPoolObj as? Double {
                self.gcpCreditPool = d
            } else if let num = rawPoolObj as? NSNumber {
                self.gcpCreditPool = num.doubleValue
            } else if let str = rawPoolObj as? String, let parsed = Double(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                self.gcpCreditPool = parsed
            } else {
                self.gcpCreditPool = userDefaults.double(forKey: "agy_gcpCreditPool")
            }
        } else {
            self.gcpCreditPool = 300.0
        }
        
        if let rawBaselineCost = userDefaults.object(forKey: "agy_gcpCreditBaselineCost") as? Double {
            self.gcpCreditBaselineCost = rawBaselineCost
        } else if let num = userDefaults.object(forKey: "agy_gcpCreditBaselineCost") as? NSNumber {
            self.gcpCreditBaselineCost = num.doubleValue
        } else if let str = userDefaults.string(forKey: "agy_gcpCreditBaselineCost"), let parsed = Double(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.gcpCreditBaselineCost = parsed
        } else {
            self.gcpCreditBaselineCost = 0.0
        }
        
        if let rawBaselineTs = userDefaults.object(forKey: "agy_gcpCreditBaselineTimestamp") as? Double {
            self.gcpCreditBaselineTimestamp = rawBaselineTs
        } else if let num = userDefaults.object(forKey: "agy_gcpCreditBaselineTimestamp") as? NSNumber {
            self.gcpCreditBaselineTimestamp = num.doubleValue
        } else {
            self.gcpCreditBaselineTimestamp = 0.0
        }
        
        if userDefaults.object(forKey: "agy_gcpCreditBaselineCost") == nil && userDefaults.object(forKey: "agy_gcpCreditPool") != nil && self.gcpCreditPool > 0.0 && self.gcpCreditPool != 300.0 {
            self.gcpCreditBaselineNeedsMigration = true
        }
        
        let expanded = self.cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let path = (expanded as NSString).appendingPathComponent("history.jsonl")
        self.isConnected = FileManager.default.fileExists(atPath: path)
    }
    
    private static let isoFormatter = ISO8601DateFormatter()
    private static let relativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    public func getGroup(matchingModelName rawNameOpt: String?) -> AgyQuotaGroup? {
        guard let quota = stats.quotaInfo, let rawName = rawNameOpt?.lowercased(), !rawName.isEmpty else {
            return nil
        }
        
        // Direct group name match
        for group in quota.groups {
            let groupName = group.displayName.lowercased()
            if rawName.contains(groupName) || groupName.contains(rawName) {
                return group
            }
        }
        
        // Bucket name match
        for group in quota.groups {
            for bucket in group.buckets {
                let bucketName = bucket.displayName.lowercased()
                if rawName.contains(bucketName) || bucketName.contains(rawName) {
                    return group
                }
            }
        }
        
        // Keyword checks for Argon (prioritize dedicated Argon group if present, otherwise fall back to Gemini group)
        if rawName.contains("argon") {
            if let argonGroup = quota.groups.first(where: { $0.displayName.lowercased().contains("argon") }) {
                return argonGroup
            }
        }
        
        // Keyword checks for Gemini / Argon fallback
        if rawName.contains("gemini") || rawName.contains("argon") {
            for group in quota.groups {
                let name = group.displayName.lowercased()
                if name.contains("gemini") || name.contains("argon") {
                    return group
                }
            }
        }
        
        // Keyword checks for Claude / Sonnet / Opus / GPT
        if rawName.contains("claude") || rawName.contains("gpt") || rawName.contains("sonnet") || rawName.contains("opus") {
            for group in quota.groups {
                let name = group.displayName.lowercased()
                if name.contains("claude") || name.contains("gpt") || name.contains("openai") || name.contains("anthropic") || name.contains("sonnet") || name.contains("opus") {
                    return group
                }
            }
        }
        
        return nil
    }

    public func getMostDepletedGroup() -> AgyQuotaGroup? {
        guard let quota = stats.quotaInfo, !quota.groups.isEmpty else { return nil }
        return quota.groups.min { a, b in
            let aFrac = getBucket(forGroup: a, target: iconQuotaLimitTarget)?.remainingFraction ?? 1.0
            let bFrac = getBucket(forGroup: b, target: iconQuotaLimitTarget)?.remainingFraction ?? 1.0
            return aFrac < bFrac
        }
    }

    public func getActiveGroup() -> AgyQuotaGroup? {
        guard let quota = stats.quotaInfo, !quota.groups.isEmpty else { return nil }

        if selectedModelForIcon == .mostDepleted {
            return getMostDepletedGroup()
        }

        // 1. Inspect recent query activity across all active terminals and sessions.
        // Queries from the last 2 hours (or the most recent 15 queries) tell us what is actively running.
        let recentCutoff = Date().addingTimeInterval(-2 * 3600)
        let activeQueries = stats.recentQueries.filter { $0.timestamp >= recentCutoff }
        let queriesToInspect = activeQueries.isEmpty ? Array(stats.recentQueries.prefix(15)) : activeQueries

        var activeGroups: [AgyQuotaGroup] = []
        for q in queriesToInspect {
            if let group = getGroup(matchingModelName: q.modelName) {
                if !activeGroups.contains(where: { $0.displayName == group.displayName }) {
                    activeGroups.append(group)
                }
            }
        }

        if activeGroups.count > 1 {
            // When multiple models are actively being queried across different terminals,
            // dynamically switch to the model that is actively getting depleted (lowest remaining quota fraction).
            if let depleted = activeGroups.min(by: { a, b in
                let aFrac = getBucket(forGroup: a, target: iconQuotaLimitTarget)?.remainingFraction ?? 1.0
                let bFrac = getBucket(forGroup: b, target: iconQuotaLimitTarget)?.remainingFraction ?? 1.0
                return aFrac < bFrac
            }) {
                return depleted
            }
        } else if let singleActive = activeGroups.first {
            return singleActive
        }

        // 2. Configured model in settings.json
        if let modelName = settings.model, let group = getGroup(matchingModelName: modelName) {
            return group
        }

        // 3. Fallback: First available group
        return quota.groups.first
    }

    public var activeModelDisplayName: String {
        if let firstQ = stats.recentQueries.first, firstQ.isGcp, let specificName = firstQ.modelName {
            return "\(specificName) (GCP)"
        }

        guard let group = getActiveGroup() else {
            return settings.model ?? (stats.quotaInfo?.plan ?? "Gemini 3.8 Flash")
        }

        let groupName = group.displayName.lowercased()
        let matchingQuery = stats.recentQueries.first { q in
            guard let m = q.modelName?.lowercased() else { return false }
            return ((m.contains("gemini") || m.contains("argon")) && (groupName.contains("gemini") || groupName.contains("argon"))) ||
                   ((m.contains("claude") || m.contains("sonnet") || m.contains("opus") || m.contains("gpt")) && (groupName.contains("claude") || groupName.contains("gpt") || groupName.contains("openai") || groupName.contains("anthropic") || groupName.contains("sonnet") || groupName.contains("opus")))
        }
        if let specificName = matchingQuery?.modelName {
            if matchingQuery?.isGcp == true {
                return "\(specificName) (GCP)"
            }
            return specificName
        }

        if let settingsModel = settings.model, let match = getGroup(matchingModelName: settingsModel), match.displayName == group.displayName {
            return settingsModel
        }

        return group.displayName
    }

    private func getGeminiGroup() -> AgyQuotaGroup? {
        guard let quota = stats.quotaInfo else { return nil }
        if let flashGroup = quota.groups.first(where: {
            let name = $0.displayName.lowercased()
            return (name.contains("gemini") || name.contains("flash")) && !name.contains("argon")
        }) {
            return flashGroup
        }
        return quota.groups.first {
            let name = $0.displayName.lowercased()
            return name.contains("gemini")
        }
    }

    private func getArgonGroup() -> AgyQuotaGroup? {
        guard let quota = stats.quotaInfo else { return nil }
        return quota.groups.first(where: { $0.displayName.lowercased().contains("argon") })
    }

    private func getClaudeGroup() -> AgyQuotaGroup? {
        guard let quota = stats.quotaInfo else { return nil }
        return quota.groups.first { group in
            let name = group.displayName.lowercased()
            return name.contains("claude") || name.contains("gpt") || name.contains("openai") || name.contains("anthropic") || name.contains("sonnet") || name.contains("opus")
        }
    }

    private func getBucket(forGroup group: AgyQuotaGroup?, target: IconQuotaLimitTarget) -> AgyQuotaBucket? {
        guard let group = group else { return nil }

        // If any bucket in the group is at 0.0 remaining (e.g. weekly limit exhausted),
        // the effective remaining quota for this entire model group is 0.0!
        if let exhaustedBucket = group.buckets.first(where: { ($0.remainingFraction ?? 1.0) <= 0.0 }) {
            return exhaustedBucket
        }

        // Filter out disabled buckets (e.g. 5-hour limit when weekly limit is reached)
        let activeBuckets = group.buckets.filter { $0.disabled != true }
        let candidates = activeBuckets.isEmpty ? group.buckets : activeBuckets

        switch target {
        case .weekly:
            return candidates.first { bucket in
                let name = bucket.displayName.lowercased()
                let id = bucket.bucketId.lowercased()
                return name.contains("week") || id.contains("week")
            } ?? candidates.first
        case .fiveHour:
            return candidates.first { bucket in
                let name = bucket.displayName.lowercased()
                let id = bucket.bucketId.lowercased()
                return name.contains("5h") || id.contains("5h") || name.contains("five") || id.contains("five")
            } ?? candidates.first
        case .auto:
            return candidates.min(by: { ($0.remainingFraction ?? 1.0) < ($1.remainingFraction ?? 1.0) })
        }
    }

    public var circleRingTarget: IconQuotaLimitTarget {
        switch iconCircleFillMetric {
        case .weekly:
            return .weekly
        case .fiveHour:
            return .fiveHour
        case .matchNumber:
            return iconQuotaLimitTarget
        }
    }

    public var menuBarSpendAmount: Double {
        switch menuBarSpendSource {
        case .gcpToday:
            return stats.gcpTodayCost
        case .apiToday:
            return stats.todayCostEstimate
        case .gcpTotal:
            return stats.gcpTotalCost
        }
    }

    private func getUsageFraction(for bucket: AgyQuotaBucket?) -> Double? {
        return bucket?.remainingFraction
    }

    private func getCircleFillFraction(for bucket: AgyQuotaBucket?) -> Double? {
        return bucket?.remainingFraction
    }

    private func getWindowDuration(for bucket: AgyQuotaBucket) -> TimeInterval {
        let id = bucket.bucketId.lowercased()
        let name = bucket.displayName.lowercased()
        
        if id.contains("5h") || id.contains("five") || name.contains("5h") || name.contains("five") {
            return 5.0 * 3600.0
        } else if id.contains("week") || name.contains("week") {
            return 7.0 * 24.0 * 3600.0
        }
        return 5.0 * 3600.0
    }

    // The usage remaining fractions (always 0.0 to 1.0) for the models
    public var selectedModelUsageFraction: Double? {
        if selectedModelForIcon == .gcp {
            guard gcpCreditPool > 0.0 else { return nil }
            return max(0.0, gcpCreditRemaining / gcpCreditPool)
        }
        let group: AgyQuotaGroup?
        switch selectedModelForIcon {
        case .active:
            group = getActiveGroup()
        case .mostDepleted:
            group = getMostDepletedGroup()
        case .gemini:
            group = getGeminiGroup()
        case .argon:
            group = getArgonGroup()
        case .claude:
            group = getClaudeGroup()
        case .both, .allThree, .gcp:
            group = getActiveGroup()
        }
        let bucket = getBucket(forGroup: group, target: iconQuotaLimitTarget)
        return getUsageFraction(for: bucket)
    }

    public var geminiUsageFraction: Double? {
        let group = getGeminiGroup()
        let bucket = getBucket(forGroup: group, target: iconQuotaLimitTarget)
        return getUsageFraction(for: bucket)
    }

    public var argonUsageFraction: Double? {
        let group = getArgonGroup()
        let bucket = getBucket(forGroup: group, target: iconQuotaLimitTarget)
        return getUsageFraction(for: bucket)
    }

    public var claudeUsageFraction: Double? {
        let group = getClaudeGroup()
        let bucket = getBucket(forGroup: group, target: iconQuotaLimitTarget)
        return getUsageFraction(for: bucket)
    }

    // The circle fill fractions for the models (respects the circle fill metric setting)
    public var selectedModelCircleFillFraction: Double? {
        if selectedModelForIcon == .gcp {
            guard gcpCreditPool > 0.0 else { return nil }
            return max(0.0, gcpCreditRemaining / gcpCreditPool)
        }
        let group: AgyQuotaGroup?
        switch selectedModelForIcon {
        case .active:
            group = getActiveGroup()
        case .mostDepleted:
            group = getMostDepletedGroup()
        case .gemini:
            group = getGeminiGroup()
        case .argon:
            group = getArgonGroup()
        case .claude:
            group = getClaudeGroup()
        case .both, .allThree, .gcp:
            group = getActiveGroup()
        }
        let bucket = getBucket(forGroup: group, target: circleRingTarget)
        return getCircleFillFraction(for: bucket)
    }

    public var geminiCircleFillFraction: Double? {
        let group = getGeminiGroup()
        let bucket = getBucket(forGroup: group, target: circleRingTarget)
        return getCircleFillFraction(for: bucket)
    }

    public var argonCircleFillFraction: Double? {
        let group = getArgonGroup()
        let bucket = getBucket(forGroup: group, target: circleRingTarget)
        return getCircleFillFraction(for: bucket)
    }

    public var claudeCircleFillFraction: Double? {
        let group = getClaudeGroup()
        let bucket = getBucket(forGroup: group, target: circleRingTarget)
        return getCircleFillFraction(for: bucket)
    }

    public func makeMenuBarImage(litColor: Color? = nil) -> NSImage {
        let color: Color
        if let litColor {
            color = litColor
        } else {
            var fractions: [Double] = []
            if let gf = geminiUsageFraction { fractions.append(gf) }
            if let af = argonUsageFraction { fractions.append(af) }
            if let cf = claudeUsageFraction { fractions.append(cf) }
            if let minFraction = fractions.min() {
                if minFraction > 0.5 {
                    color = Color(red: 0.15, green: 0.85, blue: 0.55)
                } else if minFraction > 0.2 {
                    color = Color(red: 1.0, green: 0.60, blue: 0.15)
                } else {
                    color = Color(red: 1.0, green: 0.35, blue: 0.35)
                }
            } else if stats.queriesToday > 0 {
                color = Color(red: 0.65, green: 0.45, blue: 1.0)
            } else {
                color = .primary.opacity(0.65)
            }
        }

        return AgyMenuBarRenderer.makeAntigravityImage(
            queriesToday: stats.queriesToday,
            litColor: color,
            showUsage: showModelUsageInIcon,
            selectedModelForIcon: selectedModelForIcon,
            activeUsageFraction: selectedModelUsageFraction,
            geminiUsageFraction: geminiUsageFraction,
            argonUsageFraction: argonUsageFraction,
            claudeUsageFraction: claudeUsageFraction,
            activeFillFraction: selectedModelCircleFillFraction,
            geminiFillFraction: geminiCircleFillFraction,
            argonFillFraction: argonCircleFillFraction,
            claudeFillFraction: claudeCircleFillFraction,
            showMenuBarSpend: showMenuBarSpend,
            menuBarSpendSource: menuBarSpendSource,
            spendAmount: menuBarSpendAmount,
            gcpTodayCost: stats.gcpTodayCost,
            gcpTotalCost: stats.gcpTotalCost,
            todayCost: stats.todayCostEstimate
        )
    }

    // Compatibility properties mapped to circle fill fractions
    public var selectedModelRemainingFraction: Double? {
        selectedModelCircleFillFraction
    }

    public var geminiRemainingFraction: Double? {
        geminiCircleFillFraction
    }

    public var claudeRemainingFraction: Double? {
        claudeCircleFillFraction
    }
    
    public var weeklyLimitInfo: WeeklyLimitInfo? {
        guard let quota = stats.quotaInfo else { return nil }
        for group in quota.groups {
            for bucket in group.buckets {
                let name = bucket.displayName.lowercased()
                let id = bucket.bucketId.lowercased()
                if name.contains("week") || id.contains("week") {
                    return WeeklyLimitInfo(
                        remainingFraction: bucket.remainingFraction,
                        resetTimeDescription: bucket.resetTime ?? bucket.resetDescription
                    )
                }
            }
        }
        for group in quota.groups {
            if group.displayName.lowercased().contains("week") {
                if let minBucket = group.buckets.first {
                    return WeeklyLimitInfo(
                        remainingFraction: minBucket.remainingFraction,
                        resetTimeDescription: minBucket.resetTime ?? minBucket.resetDescription
                    )
                }
            }
        }
        return nil
    }
    
    public var formattedWeeklyResetTime: String? {
        guard let info = weeklyLimitInfo, let resetDesc = info.resetTimeDescription else { return nil }
        let lowerDesc = resetDesc.lowercased()
        if lowerDesc.contains("reset") {
            var clean = lowerDesc
                .replacingOccurrences(of: "resets in ", with: "")
                .replacingOccurrences(of: "reset in ", with: "")
                .replacingOccurrences(of: "remaining", with: "")
            clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean
        }
        if let date = Self.isoFormatter.date(from: resetDesc) {
            return Self.relativeDateTimeFormatter.localizedString(for: date, relativeTo: Date())
        }
        if resetDesc.count > 15 {
            return String(resetDesc.prefix(12)) + "..."
        }
        return resetDesc
    }
    
    private var isSetup = false
    private var quotaPollingTask: Task<Void, Never>?
    
    public func setup() {
        guard !isSetup else { return }
        isSetup = true
        
        // Start watching for file changes with instant response
        watcher.cliDirOverride = cliDir
        watcher.onFileChanged = { [weak self] in
            Task { [weak self] in
                AgyQuotaService.clearCache()
                await self?.refresh()
                // Fast follow-up: language server quota accounting may take 1-2s to settle after streaming
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                await self?.refreshQuotaOnly(forceRefresh: true)
            }
        }
        watcher.start()
        
        // Start adaptive background quota polling
        startAdaptiveQuotaPolling()
        
        // Initial load
        Task {
            await refresh()
            await checkForUpdates()
        }
    }
    
    public func startAdaptiveQuotaPolling() {
        quotaPollingTask?.cancel()
        quotaPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                // Adaptive interval: 4s when active session port is known, 25s when idle
                let hasActive = AgyQuotaService.hasActiveSession
                let intervalSeconds: UInt64 = hasActive ? 4 : 25
                try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
                if Task.isCancelled { break }
                await self?.refreshQuotaOnly()
            }
        }
    }
    
    /// Fast-path quota refresh without re-reading or parsing history files (<1ms localhost request)
    public func refreshQuotaOnly(forceRefresh: Bool = false) async {
        guard let quota = await AgyQuotaService.fetchQuota(forceRefresh: forceRefresh) else { return }
        await MainActor.run {
            if self.stats.quotaInfo != quota {
                self.stats.quotaInfo = quota
            }
        }
    }
    
    public func refresh() async {
        guard !isRefreshing else { return }
        
        await MainActor.run {
            isRefreshing = true
        }
        
        let (loadedStats, loadedSettings) = await AgyStatsService.loadStats(cliDir: cliDir)
        let expanded = cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let path = (expanded as NSString).appendingPathComponent("history.jsonl")
        let connected = FileManager.default.fileExists(atPath: path)
        
        await MainActor.run {
            if self.stats != loadedStats {
                self.stats = loadedStats
            }
            if self.settings != loadedSettings {
                self.settings = loadedSettings
            }
            if self.isConnected != connected {
                self.isConnected = connected
            }
            if self.gcpCreditBaselineNeedsMigration && loadedStats.gcpTotalCost > 0.0 {
                self.gcpCreditBaselineCost = loadedStats.gcpTotalCost
                self.gcpCreditBaselineTimestamp = Date().timeIntervalSince1970
                self.userDefaults.set(loadedStats.gcpTotalCost, forKey: "agy_gcpCreditBaselineCost")
                self.userDefaults.set(self.gcpCreditBaselineTimestamp, forKey: "agy_gcpCreditBaselineTimestamp")
                self.gcpCreditBaselineNeedsMigration = false
            } else if self.gcpCreditBaselineTimestamp > 0.0 && self.gcpCreditBaselineCost == 0.0 && loadedStats.gcpTotalCost > 0.0 && self.gcpCreditPool > 0.0 && self.gcpCreditPool != 300.0 {
                self.gcpCreditBaselineCost = loadedStats.gcpTotalCost
                self.userDefaults.set(loadedStats.gcpTotalCost, forKey: "agy_gcpCreditBaselineCost")
            }
            self.isRefreshing = false
        }
    }
    
    private func restartWatcher() {
        watcher.stop()
        watcher.cliDirOverride = cliDir
        watcher.start()
    }
    
    deinit {
        watcher.stop()
        quotaPollingTask?.cancel()
    }
    
    // Helper actions
    public func revealInFinder() {
        let expanded = cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let url = URL(fileURLWithPath: expanded)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
    
    // MARK: - Auto Update Actions
    
    public func checkForUpdates(showUpToDateFeedback: Bool = false) async {
        await MainActor.run {
            isCheckingForUpdates = true
            if showUpToDateFeedback {
                updateCheckMessage = nil
            }
        }
        
        let update = await UpdateChecker.check()
        
        await MainActor.run {
            isCheckingForUpdates = false
            availableUpdate = update
            
            if let update {
                updateCheckMessage = update.isRolling
                    ? "New pre-release build available."
                    : "New version v\(update.version) available."
            } else if showUpToDateFeedback {
                updateCheckMessage = "You’re up to date."
            }
        }
        
        if showUpToDateFeedback {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                if availableUpdate == nil {
                    updateCheckMessage = nil
                }
            }
        }
    }
    
    public func dismissUpdate() {
        availableUpdate = nil
    }
    
    public func installUpdate() {
        guard let update = availableUpdate, let dmgURL = update.downloadURL else { return }
        
        Task {
            let didInstall = await SelfUpdater.update(dmgURL: dmgURL) { [weak self] state in
                Task { @MainActor in
                    self?.selfUpdateState = state
                }
            }
            if didInstall, update.isRolling, let ts = update.publishedAt {
                UpdateChecker.recordInstalledRollingTimestamp(ts)
            }
        }
    }
}
