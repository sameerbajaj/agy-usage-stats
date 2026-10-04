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
    case gemini = "Gemini Only"
    case claude = "Claude Only"
    case both = "Both (G & C)"
    
    public var id: String { rawValue }
}

public enum IconQuotaLimitTarget: String, Codable, CaseIterable, Identifiable {
    case minimum = "Minimum (Auto)"
    case weekly = "Weekly Limit"
    case fiveHour = "5-Hour Limit"
    
    public var id: String { rawValue }
}

public enum IconCircleFillMetric: String, Codable, CaseIterable, Identifiable {
    case usageRemaining = "Usage Remaining"
    case timeUntilReset = "Time Until Reset"
    
    public var id: String { rawValue }
}

public struct WeeklyLimitInfo {
    public let remainingFraction: Double?
    public let resetTimeDescription: String?
}

@Observable
public final class AgyStatsViewModel {
    // Persistent settings using UserDefaults stored properties
    public var cliDir: String {
        didSet {
            UserDefaults.standard.set(cliDir, forKey: "agy_cliDir")
            AgyStatsService.clearCaches()
            restartWatcher()
            Task { await refresh() }
        }
    }
    
    public var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: "agy_menuBarDisplayMode")
        }
    }
    
    public var showModelUsageInIcon: Bool {
        didSet {
            UserDefaults.standard.set(showModelUsageInIcon, forKey: "agy_showModelUsageInIcon")
        }
    }
    
    public var selectedModelForIcon: IconModelSelection {
        didSet {
            UserDefaults.standard.set(selectedModelForIcon.rawValue, forKey: "agy_selectedModelForIcon")
        }
    }

    public var iconQuotaLimitTarget: IconQuotaLimitTarget {
        didSet {
            UserDefaults.standard.set(iconQuotaLimitTarget.rawValue, forKey: "agy_iconQuotaLimitTarget")
        }
    }

    public var iconCircleFillMetric: IconCircleFillMetric {
        didSet {
            UserDefaults.standard.set(iconCircleFillMetric.rawValue, forKey: "agy_iconCircleFillMetric")
        }
    }
    
    public var showWeeklyLimitAndReset: Bool {
        didSet {
            UserDefaults.standard.set(showWeeklyLimitAndReset, forKey: "agy_showWeeklyLimitAndReset")
        }
    }
    
    public var showToolBreakdown: Bool {
        didSet {
            UserDefaults.standard.set(showToolBreakdown, forKey: "agy_showToolBreakdown")
        }
    }
    
    public var showCostSummary: Bool {
        didSet {
            UserDefaults.standard.set(showCostSummary, forKey: "agy_showCostSummary")
        }
    }
    
    public var selectedTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "agy_selectedTheme")
        }
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
    
    public init() {
        // Load default values or fallback
        let savedCliDir = UserDefaults.standard.string(forKey: "agy_cliDir")
        self.cliDir = savedCliDir ?? AgyStatsService.getDefaultCliDir()
        
        let savedModeStr = UserDefaults.standard.string(forKey: "agy_menuBarDisplayMode")
        if let savedModeStr, let mode = MenuBarDisplayMode(rawValue: savedModeStr) {
            self.menuBarDisplayMode = mode
        } else {
            self.menuBarDisplayMode = .both
        }
        
        self.showModelUsageInIcon = UserDefaults.standard.bool(forKey: "agy_showModelUsageInIcon")
        
        let savedModelForIcon = UserDefaults.standard.string(forKey: "agy_selectedModelForIcon")
        if let savedModelForIcon, let modelSel = IconModelSelection(rawValue: savedModelForIcon) {
            self.selectedModelForIcon = modelSel
        } else {
            self.selectedModelForIcon = .active
        }

        let savedLimitTarget = UserDefaults.standard.string(forKey: "agy_iconQuotaLimitTarget")
        if let savedLimitTarget, let limitTarget = IconQuotaLimitTarget(rawValue: savedLimitTarget) {
            self.iconQuotaLimitTarget = limitTarget
        } else {
            self.iconQuotaLimitTarget = .minimum
        }

        let savedFillMetric = UserDefaults.standard.string(forKey: "agy_iconCircleFillMetric")
        if let savedFillMetric, let fillMetric = IconCircleFillMetric(rawValue: savedFillMetric) {
            self.iconCircleFillMetric = fillMetric
        } else {
            self.iconCircleFillMetric = .usageRemaining
        }
        
        self.showWeeklyLimitAndReset = UserDefaults.standard.bool(forKey: "agy_showWeeklyLimitAndReset")
        self.showToolBreakdown = UserDefaults.standard.bool(forKey: "agy_showToolBreakdown")
        if UserDefaults.standard.object(forKey: "agy_showCostSummary") != nil {
            self.showCostSummary = UserDefaults.standard.bool(forKey: "agy_showCostSummary")
        } else {
            self.showCostSummary = true
        }
        
        let savedTheme = UserDefaults.standard.string(forKey: "agy_selectedTheme")
        if let savedTheme, let theme = AppTheme(rawValue: savedTheme) {
            self.selectedTheme = theme
        } else {
            self.selectedTheme = .midnight
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
        
        // Keyword checks for Gemini / Argon
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

        // 2. Fallback: If no recent query activity, check if any quota group is noticeably depleted (< 90% remaining).
        let depletedGroups = quota.groups.compactMap { group -> (group: AgyQuotaGroup, fraction: Double)? in
            guard let frac = getBucket(forGroup: group, target: iconQuotaLimitTarget)?.remainingFraction else { return nil }
            return (group, frac)
        }
        if let mostDepleted = depletedGroups.min(by: { $0.fraction < $1.fraction }), mostDepleted.fraction < 0.90 {
            return mostDepleted.group
        }

        // 3. Fallback: Configured model in settings.json
        if let modelName = settings.model, let group = getGroup(matchingModelName: modelName) {
            return group
        }

        // 4. Default: First available group
        return quota.groups.first
    }

    public var activeModelDisplayName: String {
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
            return specificName
        }

        if let settingsModel = settings.model, let match = getGroup(matchingModelName: settingsModel), match.displayName == group.displayName {
            return settingsModel
        }

        return group.displayName
    }

    private func getGeminiGroup() -> AgyQuotaGroup? {
        guard let quota = stats.quotaInfo else { return nil }
        return quota.groups.first {
            let name = $0.displayName.lowercased()
            return name.contains("gemini") || name.contains("argon")
        }
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
        switch target {
        case .weekly:
            return group.buckets.first { bucket in
                let name = bucket.displayName.lowercased()
                let id = bucket.bucketId.lowercased()
                return name.contains("week") || id.contains("week")
            } ?? group.buckets.first
        case .fiveHour:
            return group.buckets.first { bucket in
                let name = bucket.displayName.lowercased()
                let id = bucket.bucketId.lowercased()
                return name.contains("5h") || id.contains("5h") || name.contains("five") || id.contains("five")
            } ?? group.buckets.first
        case .minimum:
            return group.buckets.min(by: { ($0.remainingFraction ?? 1.0) < ($1.remainingFraction ?? 1.0) })
        }
    }

    private func getUsageFraction(for bucket: AgyQuotaBucket?) -> Double? {
        return bucket?.remainingFraction
    }

    private func getCircleFillFraction(for bucket: AgyQuotaBucket?) -> Double? {
        guard let bucket = bucket else { return nil }
        switch iconCircleFillMetric {
        case .usageRemaining:
            return bucket.remainingFraction
        case .timeUntilReset:
            guard let resetTimeStr = bucket.resetTime,
                  let remaining = bucket.remainingFraction,
                  remaining < 1.0 else {
                return 1.0
            }
            
            guard let resetDate = Self.isoFormatter.date(from: resetTimeStr) else {
                return 1.0
            }
            
            let now = Date()
            let timeRemaining = resetDate.timeIntervalSince(now)
            if timeRemaining <= 0 {
                return 1.0
            }
            
            let totalWindow = getWindowDuration(for: bucket)
            let fraction = timeRemaining / totalWindow
            return max(0.0, min(1.0, fraction))
        }
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
        let group = getActiveGroup()
        let bucket = getBucket(forGroup: group, target: iconQuotaLimitTarget)
        return getUsageFraction(for: bucket)
    }

    public var geminiUsageFraction: Double? {
        let group = getGeminiGroup()
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
        let group = getActiveGroup()
        let bucket = getBucket(forGroup: group, target: iconQuotaLimitTarget)
        return getCircleFillFraction(for: bucket)
    }

    public var geminiCircleFillFraction: Double? {
        let group = getGeminiGroup()
        let bucket = getBucket(forGroup: group, target: iconQuotaLimitTarget)
        return getCircleFillFraction(for: bucket)
    }

    public var claudeCircleFillFraction: Double? {
        let group = getClaudeGroup()
        let bucket = getBucket(forGroup: group, target: iconQuotaLimitTarget)
        return getCircleFillFraction(for: bucket)
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
    
    public func setup() {
        guard !isSetup else { return }
        isSetup = true
        
        // Start watching for file changes
        watcher.cliDirOverride = cliDir
        watcher.onFileChanged = { [weak self] in
            Task { [weak self] in
                await self?.refresh()
            }
        }
        watcher.start()
        
        // Initial load
        Task {
            await refresh()
            await checkForUpdates()
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
