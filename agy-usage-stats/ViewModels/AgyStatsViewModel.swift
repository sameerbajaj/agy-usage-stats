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
    
    public var selectedTheme: AppTheme {
        didSet {
            UserDefaults.standard.set(selectedTheme.rawValue, forKey: "agy_selectedTheme")
        }
    }
    
    // UI States
    public var stats: AgyUsageStats = .empty
    public var settings: AgySettings = .default
    public var isRefreshing = false
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
        
        let savedTheme = UserDefaults.standard.string(forKey: "agy_selectedTheme")
        if let savedTheme, let theme = AppTheme(rawValue: savedTheme) {
            self.selectedTheme = theme
        } else {
            self.selectedTheme = .midnight
        }
    }

    private func getActiveGroup() -> AgyQuotaGroup? {
        guard let quota = stats.quotaInfo else { return nil }
        guard let modelName = settings.model?.lowercased() else {
            return quota.groups.first
        }
        
        // Match group names
        for group in quota.groups {
            let groupName = group.displayName.lowercased()
            if modelName.contains(groupName) || groupName.contains(modelName) {
                return group
            }
        }
        
        // Match bucket names
        for group in quota.groups {
            for bucket in group.buckets {
                let bucketName = bucket.displayName.lowercased()
                if modelName.contains(bucketName) || bucketName.contains(modelName) {
                    return group
                }
            }
        }
        
        // Fallback checks for Gemini/Claude/GPT keywords
        if modelName.contains("gemini") {
            for group in quota.groups {
                if group.displayName.lowercased().contains("gemini") {
                    return group
                }
            }
        }
        if modelName.contains("claude") || modelName.contains("gpt") || modelName.contains("sonnet") {
            for group in quota.groups {
                let name = group.displayName.lowercased()
                if name.contains("claude") || name.contains("gpt") || name.contains("openai") || name.contains("anthropic") {
                    return group
                }
            }
        }
        
        return quota.groups.first
    }

    private func getGeminiGroup() -> AgyQuotaGroup? {
        guard let quota = stats.quotaInfo else { return nil }
        return quota.groups.first { $0.displayName.lowercased().contains("gemini") }
    }

    private func getClaudeGroup() -> AgyQuotaGroup? {
        guard let quota = stats.quotaInfo else { return nil }
        return quota.groups.first { group in
            let name = group.displayName.lowercased()
            return name.contains("claude") || name.contains("gpt") || name.contains("openai") || name.contains("anthropic")
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
            
            let formatter = ISO8601DateFormatter()
            guard let resetDate = formatter.date(from: resetTimeStr) else {
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
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: resetDesc) {
            let relFormatter = RelativeDateTimeFormatter()
            relFormatter.unitsStyle = .short
            return relFormatter.localizedString(for: date, relativeTo: Date())
        }
        if resetDesc.count > 15 {
            return String(resetDesc.prefix(12)) + "..."
        }
        return resetDesc
    }
    
    public func setup() {
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
        
        await MainActor.run {
            self.stats = loadedStats
            self.settings = loadedSettings
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
