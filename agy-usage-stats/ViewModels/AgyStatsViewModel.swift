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
    case carbon = "Gemini 4 Carbon"
    case argon = "Gemini 4 Argon"
    case claude = "Claude"
    case both = "Both (G & C)"
    case allThree = "All Three (G, A, C)"
    case gcp = "GCP Cloud Spend"
    
    public var id: String { rawValue }

    public static var primaryCases: [IconModelSelection] {
        [.active, .mostDepleted, .gemini, .carbon, .argon, .claude]
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "Active Model", "active": self = .active
        case "Most Depleted", "mostDepleted": self = .mostDepleted
        case "Gemini", "Gemini Only", "gemini": self = .gemini
        case "Gemini 4 Carbon", "carbon": self = .carbon
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

public enum MuseMenuBarDisplayStyle: String, Codable, CaseIterable, Identifiable {
    case remainingPercent = "Remaining %"
    case usedPercent = "Used %"
    case remainingAndReset = "Remaining + Reset"

    public var id: String { rawValue }
}

public enum MenuBarLayoutStyle: String, Codable, CaseIterable, Identifiable {
    case compactStacked = "Compact Stacked"
    case barsOnly = "Bars Only"
    case classicRings = "Classic Rings"

    public var id: String { rawValue }
}

public enum CompactMenuBarDetail: String, Codable, CaseIterable, Identifiable {
    case barAndPercent = "Bar + %"
    case barPercentAndTime = "Bar + % + Time"
    case percentOnly = "% Only"

    public var id: String { rawValue }
}

public enum MenuBarSlotSource: String, Codable, CaseIterable, Identifiable {
    case agyActiveFiveHour = "AGY Active (5h)"
    case agyActiveWeekly = "AGY Active (Weekly)"
    case agyActiveAuto = "AGY Active (Auto)"
    case geminiFiveHour = "Gemini (5h)"
    case geminiWeekly = "Gemini (Weekly)"
    case claudeFiveHour = "Claude (5h)"
    case claudeWeekly = "Claude (Weekly)"
    case museWeekly = "Muse (Weekly)"
    case none = "Off"

    public var id: String { rawValue }

    public static var topSlotCases: [MenuBarSlotSource] {
        allCases.filter { $0 != .none }
    }

    public static var bottomSlotCases: [MenuBarSlotSource] {
        [.museWeekly, .agyActiveWeekly, .agyActiveFiveHour, .geminiWeekly, .claudeFiveHour, .claudeWeekly, .none]
    }
}

public struct WeeklyLimitInfo {
    public let remainingFraction: Double?
    public let resetTimeDescription: String?
}

public struct SubscriptionAccountSummary: Identifiable, Equatable {
    public let email: String
    public var id: String { email.lowercased() }
    public let isActive: Bool
    public let plan: String?
    public let quotaInfo: AgyQuotaInfo?
    public let todayCost: Double
    public let weeklyCost: Double
    public let totalCost: Double
    public let todayQueries: Int
    public let weeklyQueries: Int
    public let totalQueries: Int
    public let googleOneAiCredits: Int?
    public let googleOneAiCreditsUsed: Int
    public let creditPool: Double
    public let costSinceBaseline: Double
    public let creditRemaining: Double

    public var hasUsedQuotaNow: Bool {
        quotaInfo?.hasUsedAnyQuota ?? false
    }

    public var hasAnyUsageToday: Bool {
        todayCost > 0.0005 || todayQueries > 0 || hasUsedQuotaNow || googleOneAiCreditsUsed > 0
    }

    public var hasAnyHistoricalUsage: Bool {
        totalCost > 0.0005 || totalQueries > 0 || hasAnyUsageToday
    }
}

public enum AccountTabItem: Identifiable, Equatable {
    case subscription(email: String, label: String, tierBadge: String?, isActive: Bool)
    case muse
    case gcp(project: String)
    case all

    public var id: String {
        switch self {
        case .subscription(let email, _, _, _):
            return "sub:\(email.lowercased())"
        case .muse:
            return "muse"
        case .gcp:
            return "gcp"
        case .all:
            return "all"
        }
    }
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

    public var showAllAccountTab: Bool {
        didSet {
            userDefaults.set(showAllAccountTab, forKey: "agy_showAllAccountTab")
        }
    }

    public var showGcpTab: Bool {
        didSet {
            userDefaults.set(showGcpTab, forKey: "agy_showGcpTab")
        }
    }

    public var showMuseTracking: Bool {
        didSet {
            userDefaults.set(showMuseTracking, forKey: "agy_showMuseTracking")
            if showMuseTracking {
                Task { await refreshMuseQuota(forceRefresh: false) }
            }
        }
    }

    public var showMuseInMenuBar: Bool {
        didSet {
            userDefaults.set(showMuseInMenuBar, forKey: "agy_showMuseInMenuBar")
        }
    }

    public var showMenuBarPaceIndicator: Bool {
        didSet {
            userDefaults.set(showMenuBarPaceIndicator, forKey: "agy_showMenuBarPaceIndicator")
        }
    }

    public var colorMenuBarByPacing: Bool {
        didSet {
            userDefaults.set(colorMenuBarByPacing, forKey: "agy_colorMenuBarByPacing")
        }
    }

    public var menuBarLayoutStyle: MenuBarLayoutStyle {
        didSet {
            userDefaults.set(menuBarLayoutStyle.rawValue, forKey: "agy_menuBarLayoutStyle")
        }
    }

    public var compactMenuBarDetail: CompactMenuBarDetail {
        didSet {
            userDefaults.set(compactMenuBarDetail.rawValue, forKey: "agy_compactMenuBarDetail")
        }
    }

    public var compactTopSlot: MenuBarSlotSource {
        didSet {
            userDefaults.set(compactTopSlot.rawValue, forKey: "agy_compactTopSlot")
        }
    }

    public var compactBottomSlot: MenuBarSlotSource {
        didSet {
            userDefaults.set(compactBottomSlot.rawValue, forKey: "agy_compactBottomSlot")
        }
    }

    public var museMenuBarDisplayStyle: MuseMenuBarDisplayStyle {
        didSet {
            userDefaults.set(museMenuBarDisplayStyle.rawValue, forKey: "agy_museMenuBarDisplayStyle")
        }
    }

    public var museManualCookieHeader: String {
        didSet {
            userDefaults.set(museManualCookieHeader, forKey: "agy_museManualCookieHeader")
        }
    }

    public var museQuota: MuseQuotaInfo? = nil
    public var museFetchStatus: MuseFetchStatus = .idle
    public var isRefreshingMuse: Bool = false
    private var lastMuseRefreshAt: Date? = nil
    
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
            guard abs(gcpCreditPool - oldValue) > 0.001 else { return }
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
            let nowTs = Date().timeIntervalSince1970
            let currentTotal: Double
            if !stats.gcpSpendEntries.isEmpty {
                currentTotal = stats.gcpSpendEntries
                    .filter { $0.timestamp <= nowTs }
                    .reduce(0.0) { $0 + $1.cost }
            } else {
                currentTotal = stats.gcpTotalCost
            }
            self.gcpCreditBaselineCost = currentTotal
            self.gcpCreditBaselineTimestamp = nowTs
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
    
    public func reconcileGcpBaseline(with loadedStats: AgyUsageStats) {
        if self.gcpCreditBaselineNeedsMigration && loadedStats.gcpTotalCost > 0.0 {
            self.gcpCreditBaselineCost = loadedStats.gcpTotalCost
            self.gcpCreditBaselineTimestamp = Date().timeIntervalSince1970
            self.userDefaults.set(loadedStats.gcpTotalCost, forKey: "agy_gcpCreditBaselineCost")
            self.userDefaults.set(self.gcpCreditBaselineTimestamp, forKey: "agy_gcpCreditBaselineTimestamp")
            self.gcpCreditBaselineNeedsMigration = false
        } else if self.gcpCreditPool > 0.0 && self.gcpCreditBaselineTimestamp > 0.0 {
            if !loadedStats.gcpSpendEntries.isEmpty {
                let truePreBaselineCost = loadedStats.gcpSpendEntries
                    .filter { $0.timestamp <= self.gcpCreditBaselineTimestamp }
                    .reduce(0.0) { $0 + $1.cost }
                if abs(self.gcpCreditBaselineCost - truePreBaselineCost) > 0.0001 {
                    self.gcpCreditBaselineCost = truePreBaselineCost
                    self.userDefaults.set(truePreBaselineCost, forKey: "agy_gcpCreditBaselineCost")
                }
            } else if loadedStats.gcpTotalCost > 0.0 && (self.gcpCreditBaselineCost == 0.0 || self.gcpCreditBaselineCost > loadedStats.gcpTotalCost) && self.gcpCreditPool != 300.0 {
                self.gcpCreditBaselineCost = loadedStats.gcpTotalCost
                self.userDefaults.set(loadedStats.gcpTotalCost, forKey: "agy_gcpCreditBaselineCost")
            }
        }
    }
    
    // GCP Credit remaining & consumed calculations based on timestamp-anchored baseline snapshot
    public var gcpCostSinceBaseline: Double {
        guard gcpCreditPool > 0.0 else { return 0.0 }
        if !stats.gcpSpendEntries.isEmpty && gcpCreditBaselineTimestamp > 0.0 {
            return stats.gcpSpendEntries
                .filter { $0.timestamp > gcpCreditBaselineTimestamp }
                .reduce(0.0) { $0 + $1.cost }
        }
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

    // Per-account optional credit pool tracking
    private var accountCreditPools: [String: Double] = [:]
    private var accountCreditBaselineTimestamps: [String: Double] = [:]

    // Dismissed/hidden consumer accounts:
    // - dismissedConsumerEmails: legacy auto-dismissed unused accounts (auto-restored if active or accruing new today spend > $0.005)
    // - hiddenConsumerEmails: explicitly hidden accounts from Settings / top bar (stays hidden even with historical/today spend; only auto-restores if user logs back into it)
    public var dismissedConsumerEmails: Set<String> = []
    public var hiddenConsumerEmails: Set<String> = []

    public func dismissAccount(_ email: String) {
        let key = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        if let active = activeConsumerEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           active == key {
            return
        }
        if dismissedConsumerEmails.insert(key).inserted {
            userDefaults.set(Array(dismissedConsumerEmails).sorted(), forKey: "agy_dismissedConsumerEmails")
        }
        AgyQuotaService.removePersistedAccount(key, userDefaults: userDefaults)
    }

    /// Toggles visibility of a non-active subscription account in the top tab bar & Overview without losing its record in Settings.
    public func setAccountHidden(_ hidden: Bool, for email: String) {
        let key = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        if hidden {
            if let active = activeConsumerEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               active == key {
                return
            }
            if hiddenConsumerEmails.insert(key).inserted {
                userDefaults.set(Array(hiddenConsumerEmails).sorted(), forKey: "agy_hiddenConsumerEmails")
            }
        } else {
            if hiddenConsumerEmails.remove(key) != nil {
                userDefaults.set(Array(hiddenConsumerEmails).sorted(), forKey: "agy_hiddenConsumerEmails")
            }
            if dismissedConsumerEmails.remove(key) != nil {
                userDefaults.set(Array(dismissedConsumerEmails).sorted(), forKey: "agy_dismissedConsumerEmails")
            }
        }
    }

    public func isAccountHidden(_ email: String) -> Bool {
        let key = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return false }
        if let active = activeConsumerEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           active == key {
            return false
        }
        return hiddenConsumerEmails.contains(key) || dismissedConsumerEmails.contains(key)
    }

    private func reconcileDismissedConsumerEmails() {
        let activeLower = activeConsumerEmail?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if !dismissedConsumerEmails.isEmpty {
            var updated = dismissedConsumerEmails
            if let active = activeLower, !active.isEmpty {
                updated.remove(active)
            }
            for (account, cost) in stats.accountTodayTotals where cost > 0.005 {
                let key = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                updated.remove(key)
            }
            if updated != dismissedConsumerEmails {
                dismissedConsumerEmails = updated
                userDefaults.set(Array(updated).sorted(), forKey: "agy_dismissedConsumerEmails")
            }
        }

        if !hiddenConsumerEmails.isEmpty, let active = activeLower, !active.isEmpty {
            if hiddenConsumerEmails.remove(active) != nil {
                userDefaults.set(Array(hiddenConsumerEmails).sorted(), forKey: "agy_hiddenConsumerEmails")
            }
        }
    }

    public func accountCreditPool(for email: String) -> Double {
        let key = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return 0.0 }
        return accountCreditPools[key] ?? 0.0
    }

    public func setAccountCreditPool(_ pool: Double, for email: String) {
        let key = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        let sanitized = max(0.0, (pool * 100.0).rounded() / 100.0)
        let old = accountCreditPools[key] ?? 0.0
        if sanitized <= 0.0 {
            accountCreditPools.removeValue(forKey: key)
            accountCreditBaselineTimestamps.removeValue(forKey: key)
        } else {
            accountCreditPools[key] = sanitized
            if abs(sanitized - old) > 0.001 {
                accountCreditBaselineTimestamps[key] = Date().timeIntervalSince1970
            }
        }
        userDefaults.set(accountCreditPools, forKey: "agy_accountCreditPools")
        userDefaults.set(accountCreditBaselineTimestamps, forKey: "agy_accountCreditBaselineTimestamps")
    }

    public func resetAccountCreditBaseline(for email: String) {
        let key = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return }
        if (accountCreditPools[key] ?? 0.0) > 0.0 {
            accountCreditBaselineTimestamps[key] = Date().timeIntervalSince1970
        } else {
            accountCreditBaselineTimestamps.removeValue(forKey: key)
        }
        userDefaults.set(accountCreditBaselineTimestamps, forKey: "agy_accountCreditBaselineTimestamps")
    }

    public func accountCostSinceBaseline(for email: String) -> Double {
        let key = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return 0.0 }
        let pool = accountCreditPools[key] ?? 0.0
        guard pool > 0.0 else { return 0.0 }
        let baselineTs = accountCreditBaselineTimestamps[key] ?? 0.0
        return stats.consumerSpendEntries
            .filter { $0.email.lowercased() == key && $0.timestamp > baselineTs }
            .reduce(0.0) { $0 + $1.cost }
    }

    private func buildSubscriptionAccountSummaries(includeHidden: Bool) -> [SubscriptionAccountSummary] {
        var displayEmailByLower: [String: String] = [:]

        func registerEmail(_ candidate: String?) {
            guard let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  trimmed.contains("@"),
                  !trimmed.hasPrefix("GCP ("),
                  trimmed != "Google Cloud API",
                  trimmed != "Account Quota",
                  !AgyQuotaService.isSyntheticTestEmail(trimmed) else { return }
            let key = trimmed.lowercased()
            if displayEmailByLower[key] == nil {
                displayEmailByLower[key] = trimmed
            }
        }

        let persistedQuotas = AgyQuotaService.allPersistedQuotas(userDefaults: userDefaults)

        for email in stats.discoveredConsumerEmails { registerEmail(email) }
        for account in stats.availableAccounts { registerEmail(account) }
        registerEmail(activeConsumerEmail)
        registerEmail(stats.quotaInfo?.email)
        for key in persistedQuotas.keys { registerEmail(key) }
        if let active = activeConsumerEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
           !active.isEmpty, active.contains("@"),
           !AgyQuotaService.isSyntheticTestEmail(active) {
            displayEmailByLower[active.lowercased()] = active
        }

        let activeKey: String? = {
            if let active = activeConsumerEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
               !active.isEmpty, active.contains("@"),
               !AgyQuotaService.isSyntheticTestEmail(active) {
                return active.lowercased()
            }
            if let quotaEmail = stats.quotaInfo?.email?.trimmingCharacters(in: .whitespacesAndNewlines),
               !quotaEmail.isEmpty, quotaEmail.contains("@"),
               !AgyQuotaService.isSyntheticTestEmail(quotaEmail) {
                return quotaEmail.lowercased()
            }
            return nil
        }()

        func sumDouble(_ dict: [String: Double], key: String) -> Double {
            dict.reduce(0.0) { partial, item in
                item.key.lowercased() == key ? partial + item.value : partial
            }
        }

        func sumInt(_ dict: [String: Int], key: String) -> Int {
            dict.reduce(0) { partial, item in
                item.key.lowercased() == key ? partial + item.value : partial
            }
        }

        let summaries = displayEmailByLower.compactMap { (key, displayEmail) -> SubscriptionAccountSummary? in
            let isActive = (key == activeKey)
            let todayCost = sumDouble(stats.accountTodayTotals, key: key)
            if !includeHidden && !isActive {
                if hiddenConsumerEmails.contains(key) {
                    return nil
                }
                if dismissedConsumerEmails.contains(key) && todayCost <= 0.005 {
                    return nil
                }
            }
            let liveMatchingQuota: AgyQuotaInfo? = {
                guard let q = stats.quotaInfo,
                      q.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == key else {
                    return nil
                }
                return q
            }()
            let quota = isActive ? (liveMatchingQuota ?? persistedQuotas[key]) : (persistedQuotas[key] ?? liveMatchingQuota)
            let weeklyCost = sumDouble(stats.accountWeeklyTotals, key: key)
            let totalCost = sumDouble(stats.accountCostTotals, key: key)
            let todayQueries = sumInt(stats.accountQueryTodayTotals, key: key)
            let weeklyQueries = sumInt(stats.accountQueryWeeklyTotals, key: key)
            let totalQueries = sumInt(stats.accountQueryTotals, key: key)

            let aiCredits = quota?.googleOneAiCredits
            let aiCreditsUsed: Int = {
                guard let current = aiCredits else { return 0 }
                let peak = AgyQuotaService.peakGoogleOneAiCredits(forEmail: key, userDefaults: userDefaults) ?? current
                return max(0, peak - current)
            }()

            let pool = accountCreditPool(for: key)
            let sinceBaseline = accountCostSinceBaseline(for: key)
            let remaining = pool > 0.0 ? max(0.0, pool - sinceBaseline) : 0.0

            return SubscriptionAccountSummary(
                email: displayEmail,
                isActive: isActive,
                plan: quota?.plan,
                quotaInfo: quota,
                todayCost: todayCost,
                weeklyCost: weeklyCost,
                totalCost: totalCost,
                todayQueries: todayQueries,
                weeklyQueries: weeklyQueries,
                totalQueries: totalQueries,
                googleOneAiCredits: aiCredits,
                googleOneAiCreditsUsed: aiCreditsUsed,
                creditPool: pool,
                costSinceBaseline: sinceBaseline,
                creditRemaining: remaining
            )
        }

        return summaries.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive && !rhs.isActive
            }
            if abs(lhs.todayCost - rhs.todayCost) > 0.0001 {
                return lhs.todayCost > rhs.todayCost
            }
            if abs(lhs.totalCost - rhs.totalCost) > 0.0001 {
                return lhs.totalCost > rhs.totalCost
            }
            return lhs.email.lowercased() < rhs.email.lowercased()
        }
    }

    public var subscriptionAccountSummaries: [SubscriptionAccountSummary] {
        buildSubscriptionAccountSummaries(includeHidden: false)
    }

    public var allKnownSubscriptionAccountSummaries: [SubscriptionAccountSummary] {
        buildSubscriptionAccountSummaries(includeHidden: true)
    }

    // MARK: - Option B Smart Account Tab Descriptors

    private static func isPrimaryEligible(_ summary: SubscriptionAccountSummary) -> Bool {
        summary.isActive
            || summary.totalCost > 0.005
            || summary.todayCost > 0.005
            || summary.totalQueries > 0
            || summary.hasUsedQuotaNow
            || summary.googleOneAiCreditsUsed > 0
    }

    public static func shortTierName(for plan: String?) -> String? {
        guard let raw = plan?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        if lower.contains("ultra") { return "Ultra" }
        if lower.contains("pro") { return "Pro" }
        if lower.contains("free") { return "Free" }
        return nil
    }

    private static func shortEmailHandle(for email: String, maxLength: Int = 9) -> String {
        let local = email.split(separator: "@").first.map(String.init) ?? email
        if local.count <= maxLength {
            return local
        }
        let prefixCount = max(1, maxLength - 1)
        return String(local.prefix(prefixCount)) + "…"
    }

    private static func disambiguatedEmailHandles(for summaries: [SubscriptionAccountSummary]) -> [String: String] {
        var handles: [String: String] = [:]
        for s in summaries {
            handles[s.id] = shortEmailHandle(for: s.email)
        }
        let grouped = Dictionary(grouping: summaries) { handles[$0.id] ?? $0.email }
        for (_, colliding) in grouped where colliding.count > 1 {
            for s in colliding {
                let parts = s.email.split(separator: "@", maxSplits: 1).map(String.init)
                let local = parts.first ?? s.email
                let domain = parts.count > 1 ? parts[1] : ""
                let hasSameLocal = colliding.filter {
                    ($0.email.split(separator: "@").first.map(String.init) ?? "").lowercased() == local.lowercased()
                }.count > 1
                if hasSameLocal && !domain.isEmpty {
                    let domPrefix = String(domain.split(separator: ".").first ?? Substring(domain)).prefix(3)
                    let localShort = String(local.prefix(4))
                    handles[s.id] = "\(localShort)@\(domPrefix)"
                } else if local.count > 9 {
                    let head = String(local.prefix(5))
                    let tail = String(local.suffix(3))
                    handles[s.id] = "\(head)…\(tail)"
                }
            }
        }
        return handles
    }

    private var partitionedSubscriptionTabs: (primary: [AccountTabItem], overflow: [SubscriptionAccountSummary]) {
        let summaries = subscriptionAccountSummaries
        let primarySummaries = Array(summaries.filter { Self.isPrimaryEligible($0) }.prefix(3))
        let primaryIds = Set(primarySummaries.map(\.id))
        let overflow = summaries.filter { !primaryIds.contains($0.id) }

        let tierNames = primarySummaries.map { Self.shortTierName(for: $0.plan) }
        let nonNilTiers = tierNames.compactMap { $0 }
        let allHaveTier = nonNilTiers.count == primarySummaries.count
        let allTiersUnique = Set(nonNilTiers).count == nonNilTiers.count
        let useTierLabels = !primarySummaries.isEmpty && allHaveTier && allTiersUnique

        let fallbackHandles = Self.disambiguatedEmailHandles(for: primarySummaries)

        let primaryItems: [AccountTabItem] = zip(primarySummaries, tierNames).map { summary, tierName in
            let label = useTierLabels
                ? (tierName ?? fallbackHandles[summary.id] ?? summary.email)
                : (fallbackHandles[summary.id] ?? summary.email)
            let tierBadge = tierName?.uppercased() ?? {
                let raw = summary.plan?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return raw.isEmpty ? nil : raw.uppercased()
            }()
            return .subscription(
                email: summary.email,
                label: label,
                tierBadge: tierBadge,
                isActive: summary.isActive
            )
        }

        return (primaryItems, overflow)
    }

    public var primaryAccountTabs: [AccountTabItem] {
        var tabs = partitionedSubscriptionTabs.primary
        if showMuseTracking {
            tabs.append(.muse)
        }
        if showGcpTab && (stats.gcpTotalCost > 0 || stats.gcpTodayCost > 0 || gcpCreditPool > 0 || stats.isGcpActive) {
            tabs.append(.gcp(project: stats.gcpProject ?? "clawdbot-485304"))
        }
        if showAllAccountTab || tabs.isEmpty {
            tabs.append(.all)
        }
        return tabs
    }

    public var overflowUnusedSubscriptions: [SubscriptionAccountSummary] {
        partitionedSubscriptionTabs.overflow
    }
    
    // UI States
    public var stats: AgyUsageStats = .empty {
        didSet {
            reconcileDismissedConsumerEmails()
        }
    }
    public var settings: AgySettings = .default
    public var activeConsumerEmail: String? = nil {
        didSet {
            reconcileDismissedConsumerEmails()
        }
    }
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

        if userDefaults.object(forKey: "agy_showAllAccountTab") != nil {
            self.showAllAccountTab = userDefaults.bool(forKey: "agy_showAllAccountTab")
        } else {
            self.showAllAccountTab = true
        }

        if userDefaults.object(forKey: "agy_showGcpTab") != nil {
            self.showGcpTab = userDefaults.bool(forKey: "agy_showGcpTab")
        } else {
            self.showGcpTab = true
        }

        if userDefaults.object(forKey: "agy_showMuseTracking") != nil {
            self.showMuseTracking = userDefaults.bool(forKey: "agy_showMuseTracking")
        } else {
            self.showMuseTracking = true
        }

        if userDefaults.object(forKey: "agy_showMuseInMenuBar") != nil {
            self.showMuseInMenuBar = userDefaults.bool(forKey: "agy_showMuseInMenuBar")
        } else {
            self.showMuseInMenuBar = true
        }

        if userDefaults.object(forKey: "agy_showMenuBarPaceIndicator") != nil {
            self.showMenuBarPaceIndicator = userDefaults.bool(forKey: "agy_showMenuBarPaceIndicator")
        } else {
            self.showMenuBarPaceIndicator = true
        }

        if userDefaults.object(forKey: "agy_colorMenuBarByPacing") != nil {
            self.colorMenuBarByPacing = userDefaults.bool(forKey: "agy_colorMenuBarByPacing")
        } else {
            self.colorMenuBarByPacing = false
        }

        if let savedLayout = userDefaults.string(forKey: "agy_menuBarLayoutStyle"),
           let parsedLayout = MenuBarLayoutStyle(rawValue: savedLayout) {
            self.menuBarLayoutStyle = parsedLayout
        } else {
            self.menuBarLayoutStyle = .compactStacked
        }

        if let savedDetail = userDefaults.string(forKey: "agy_compactMenuBarDetail"),
           let parsedDetail = CompactMenuBarDetail(rawValue: savedDetail) {
            self.compactMenuBarDetail = parsedDetail
        } else {
            self.compactMenuBarDetail = .barAndPercent
        }

        if let savedTop = userDefaults.string(forKey: "agy_compactTopSlot"),
           let parsedTop = MenuBarSlotSource(rawValue: savedTop), parsedTop != .none {
            self.compactTopSlot = parsedTop
        } else {
            self.compactTopSlot = .agyActiveFiveHour
        }

        if let savedBottom = userDefaults.string(forKey: "agy_compactBottomSlot"),
           let parsedBottom = MenuBarSlotSource(rawValue: savedBottom) {
            self.compactBottomSlot = parsedBottom
        } else {
            self.compactBottomSlot = .museWeekly
        }

        if let savedMuseStyle = userDefaults.string(forKey: "agy_museMenuBarDisplayStyle"),
           let parsedMuseStyle = MuseMenuBarDisplayStyle(rawValue: savedMuseStyle) {
            self.museMenuBarDisplayStyle = parsedMuseStyle
        } else {
            self.museMenuBarDisplayStyle = .remainingPercent
        }

        self.museManualCookieHeader = userDefaults.string(forKey: "agy_museManualCookieHeader") ?? ""
        
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
            let rawVal: Double
            if let d = rawPoolObj as? Double {
                rawVal = d
            } else if let num = rawPoolObj as? NSNumber {
                rawVal = num.doubleValue
            } else if let str = rawPoolObj as? String, let parsed = Double(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                rawVal = parsed
            } else {
                rawVal = userDefaults.double(forKey: "agy_gcpCreditPool")
            }
            self.gcpCreditPool = (rawVal * 100.0).rounded() / 100.0
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
        } else if let str = userDefaults.string(forKey: "agy_gcpCreditBaselineTimestamp"), let parsed = Double(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.gcpCreditBaselineTimestamp = parsed
        } else {
            self.gcpCreditBaselineTimestamp = 0.0
        }
        
        if userDefaults.object(forKey: "agy_gcpCreditBaselineCost") == nil && userDefaults.object(forKey: "agy_gcpCreditPool") != nil && self.gcpCreditPool > 0.0 && self.gcpCreditPool != 300.0 {
            self.gcpCreditBaselineNeedsMigration = true
        }

        if let rawPools = userDefaults.dictionary(forKey: "agy_accountCreditPools") {
            var loadedPools: [String: Double] = [:]
            for (k, v) in rawPools {
                let key = k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty else { continue }
                if let d = v as? Double, d > 0 {
                    loadedPools[key] = (d * 100.0).rounded() / 100.0
                } else if let n = v as? NSNumber, n.doubleValue > 0 {
                    loadedPools[key] = (n.doubleValue * 100.0).rounded() / 100.0
                }
            }
            self.accountCreditPools = loadedPools
        }
        if let rawTimestamps = userDefaults.dictionary(forKey: "agy_accountCreditBaselineTimestamps") {
            var loadedTimestamps: [String: Double] = [:]
            for (k, v) in rawTimestamps {
                let key = k.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !key.isEmpty else { continue }
                if let d = v as? Double, d > 0 {
                    loadedTimestamps[key] = d
                } else if let n = v as? NSNumber, n.doubleValue > 0 {
                    loadedTimestamps[key] = n.doubleValue
                }
            }
            self.accountCreditBaselineTimestamps = loadedTimestamps
        }
        
        if let savedDismissed = userDefaults.array(forKey: "agy_dismissedConsumerEmails") as? [String] {
            self.dismissedConsumerEmails = Set(
                savedDismissed
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        }

        if let savedHidden = userDefaults.array(forKey: "agy_hiddenConsumerEmails") as? [String] {
            self.hiddenConsumerEmails = Set(
                savedHidden
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
        }

        let expanded = self.cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let path = (expanded as NSString).appendingPathComponent("history.jsonl")
        self.isConnected = FileManager.default.fileExists(atPath: path)
        // Hydrate immediately from persisted quota in UserDefaults (O(1) in-memory) so launch never blocks main thread scanning logs
        if let persistedQuota = AgyQuotaService.loadPersistedQuota(userDefaults: userDefaults) {
            self.stats.quotaInfo = persistedQuota
            if let email = persistedQuota.email, !email.isEmpty, !AgyQuotaService.isSyntheticTestEmail(email) {
                self.activeConsumerEmail = email
            }
        }
        if let persistedMuse = MuseQuotaService.loadPersistedQuota(userDefaults: userDefaults) {
            self.museQuota = persistedMuse
            self.museFetchStatus = .connected
        }
        reconcileDismissedConsumerEmails()
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
        
        // Keyword checks for Neon (prefer a dedicated model quota when available).
        if rawName.contains("neon") {
            if let neonGroup = quota.groups.first(where: { $0.displayName.lowercased().contains("neon") }) {
                return neonGroup
            }
        }

        // Keyword checks for Hydrogen (prefer a dedicated model quota when available).
        if rawName.contains("hydrogen") {
            if let hydrogenGroup = quota.groups.first(where: { $0.displayName.lowercased().contains("hydrogen") }) {
                return hydrogenGroup
            }
        }

        // Keyword checks for Carbon (prioritize dedicated Carbon group if present, otherwise fall back to Gemini group)
        if rawName.contains("carbon") {
            if let carbonGroup = quota.groups.first(where: { $0.displayName.lowercased().contains("carbon") }) {
                return carbonGroup
            }
        }
        
        // Keyword checks for Argon (prioritize dedicated Argon group if present, otherwise fall back to Gemini group)
        if rawName.contains("argon") {
            if let argonGroup = quota.groups.first(where: { $0.displayName.lowercased().contains("argon") }) {
                return argonGroup
            }
        }
        
        // Keyword checks for Gemini / Neon / Hydrogen / Carbon / Argon fallback
        if rawName.contains("gemini") || rawName.contains("neon") || rawName.contains("hydrogen") || rawName.contains("carbon") || rawName.contains("argon") {
            for group in quota.groups {
                let name = group.displayName.lowercased()
                if name.contains("gemini") || name.contains("neon") || name.contains("hydrogen") || name.contains("carbon") || name.contains("argon") {
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
        // Queries are sorted newest-first; scan lazily without allocating a full filtered copy of thousands of entries.
        // Consumer box queries ONLY (!q.isGcp): GCP credit queries must never hijack subscription model/quota!
        let recentCutoff = Date().addingTimeInterval(-2 * 3600)
        var activeQueries: [QueryEntry] = []
        var fallbackQueries: [QueryEntry] = []
        fallbackQueries.reserveCapacity(15)
        for q in stats.recentQueries where !q.isGcp {
            if q.timestamp >= recentCutoff {
                activeQueries.append(q)
            } else if activeQueries.isEmpty && fallbackQueries.count < 15 {
                fallbackQueries.append(q)
            } else {
                break
            }
        }
        let queriesToInspect = activeQueries.isEmpty ? fallbackQueries : activeQueries

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
        let firstConsumerQuery = stats.recentQueries.first(where: { !$0.isGcp })
        if firstConsumerQuery == nil, let firstQ = stats.recentQueries.first, firstQ.isGcp, let specificName = firstQ.modelName {
            return "\(specificName) (GCP)"
        }

        guard let group = getActiveGroup() else {
            return settings.model ?? (stats.quotaInfo?.plan ?? "Gemini 3.8 Flash")
        }

        let groupName = group.displayName.lowercased()
        let isGeminiFamilyGroup = groupName.contains("gemini") || groupName.contains("neon") || groupName.contains("hydrogen") || groupName.contains("carbon") || groupName.contains("argon")
        let isClaudeFamilyGroup = groupName.contains("claude") || groupName.contains("gpt") || groupName.contains("openai") || groupName.contains("anthropic") || groupName.contains("sonnet") || groupName.contains("opus")

        let matchingQuery = stats.recentQueries.first { q in
            guard !q.isGcp, let m = q.modelName?.lowercased() else { return false }
            return ((m.contains("gemini") || m.contains("neon") || m.contains("hydrogen") || m.contains("carbon") || m.contains("argon")) && isGeminiFamilyGroup) ||
                   ((m.contains("claude") || m.contains("sonnet") || m.contains("opus") || m.contains("gpt")) && isClaudeFamilyGroup)
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
        if let flashGroup = quota.groups.first(where: {
            let name = $0.displayName.lowercased()
            return (name.contains("gemini") || name.contains("flash")) && !name.contains("neon") && !name.contains("hydrogen") && !name.contains("argon") && !name.contains("carbon")
        }) {
            return flashGroup
        }
        return quota.groups.first {
            let name = $0.displayName.lowercased()
            return name.contains("gemini")
        }
    }

    private func getCarbonGroup() -> AgyQuotaGroup? {
        guard let quota = stats.quotaInfo else { return nil }
        return quota.groups.first(where: { $0.displayName.lowercased().contains("carbon") })
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
        case .carbon:
            group = getCarbonGroup()
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

    public var carbonUsageFraction: Double? {
        let group = getCarbonGroup()
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
        case .carbon:
            group = getCarbonGroup()
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

    public var carbonCircleFillFraction: Double? {
        let group = getCarbonGroup()
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

    private func selectedGroupForIcon() -> AgyQuotaGroup? {
        switch selectedModelForIcon {
        case .active: return getActiveGroup()
        case .mostDepleted: return getMostDepletedGroup()
        case .gemini: return getGeminiGroup()
        case .carbon: return getCarbonGroup()
        case .argon: return getArgonGroup()
        case .claude: return getClaudeGroup()
        case .both, .allThree, .gcp: return getActiveGroup()
        }
    }

    public var selectedModelCirclePacing: QuotaPacing? {
        guard selectedModelForIcon != .gcp else { return nil }
        return getBucket(forGroup: selectedGroupForIcon(), target: circleRingTarget)?.pacing()
    }

    public var selectedModelNumberPacing: QuotaPacing? {
        guard selectedModelForIcon != .gcp else { return nil }
        return getBucket(forGroup: selectedGroupForIcon(), target: iconQuotaLimitTarget)?.pacing()
    }

    public var geminiNumberPacing: QuotaPacing? {
        getBucket(forGroup: getGeminiGroup(), target: iconQuotaLimitTarget)?.pacing()
    }

    public var claudeNumberPacing: QuotaPacing? {
        getBucket(forGroup: getClaudeGroup(), target: iconQuotaLimitTarget)?.pacing()
    }

    private func ultraCompactCountdown(for bucket: AgyQuotaBucket, now: Date = Date()) -> String? {
        guard !bucket.isWindowTimerIdle(now: now),
              let resetDate = bucket.parsedResetDate else { return nil }
        let diff = resetDate.timeIntervalSince(now)
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

    public func resolveCompactSlot(_ source: MenuBarSlotSource, now: Date = Date()) -> CompactMenuBarSlotData? {
        switch source {
        case .none:
            return nil

        case .museWeekly:
            guard showMuseTracking, let muse = museQuota?.normalizedForCurrentTime(now: now) else {
                return nil
            }
            let pacing = muse.pacing(now: now)
            return CompactMenuBarSlotData(
                remainingFraction: muse.remainingFraction,
                displayPercent: muse.remainingPercent,
                paceMarkerFraction: showMenuBarPaceIndicator ? pacing?.expectedRemainingFraction : nil,
                pacing: pacing,
                resetShortText: muse.ultraCompactCountdown(now: now),
                accentColor: MenuBarPresentationResolver.museIndigoColor,
                isIdle: false
            )

        case .agyActiveFiveHour, .agyActiveWeekly, .agyActiveAuto,
             .geminiFiveHour, .geminiWeekly, .claudeFiveHour, .claudeWeekly:
            let group: AgyQuotaGroup?
            let target: IconQuotaLimitTarget
            switch source {
            case .agyActiveFiveHour: group = getActiveGroup(); target = .fiveHour
            case .agyActiveWeekly:   group = getActiveGroup(); target = .weekly
            case .agyActiveAuto:     group = getActiveGroup(); target = .auto
            case .geminiFiveHour:    group = getGeminiGroup(); target = .fiveHour
            case .geminiWeekly:      group = getGeminiGroup(); target = .weekly
            case .claudeFiveHour:    group = getClaudeGroup(); target = .fiveHour
            case .claudeWeekly:      group = getClaudeGroup(); target = .weekly
            default:                 return nil
            }
            guard let bucket = getBucket(forGroup: group, target: target),
                  let frac = bucket.remainingFraction else {
                return nil
            }
            let clamped = max(0.0, min(1.0, frac))
            let isIdle = bucket.isWindowTimerIdle(now: now)
            let pacing = bucket.pacing(now: now)
            return CompactMenuBarSlotData(
                remainingFraction: clamped,
                displayPercent: clamped * 100.0,
                paceMarkerFraction: (showMenuBarPaceIndicator && !isIdle) ? pacing?.expectedRemainingFraction : nil,
                pacing: pacing,
                resetShortText: ultraCompactCountdown(for: bucket, now: now),
                accentColor: MenuBarPresentationResolver.healthyGreenColor,
                isIdle: isIdle
            )
        }
    }

    public func makeMenuBarImage(litColor: Color? = nil) -> NSImage {
        let color: Color
        if let litColor {
            color = litColor
        } else {
            var fractions: [Double] = []
            if let gf = geminiUsageFraction { fractions.append(gf) }
            if let carb = carbonUsageFraction { fractions.append(carb) }
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

        if menuBarLayoutStyle == .compactStacked || menuBarLayoutStyle == .barsOnly {
            let slots = [
                resolveCompactSlot(compactTopSlot),
                resolveCompactSlot(compactBottomSlot)
            ].compactMap { $0 }

            if !slots.isEmpty {
                let detail: CompactMenuBarDetail = (menuBarLayoutStyle == .barsOnly)
                    ? .barAndPercent
                    : compactMenuBarDetail
                return AgyMenuBarRenderer.makeCompactStackedImage(
                    slots: slots,
                    barsOnly: menuBarLayoutStyle == .barsOnly,
                    detail: detail,
                    colorByPacing: colorMenuBarByPacing,
                    showMenuBarSpend: showMenuBarSpend,
                    menuBarSpendSource: menuBarSpendSource,
                    spendAmount: menuBarSpendAmount,
                    gcpTodayCost: stats.gcpTodayCost,
                    gcpTotalCost: stats.gcpTotalCost,
                    todayCost: stats.todayCostEstimate
                )
            }
        }

        let activeMuseQuota = (showMuseTracking && showMuseInMenuBar) ? museQuota?.normalizedForCurrentTime() : nil
        let activeAgyRingPacing = selectedModelCirclePacing
        let activeAgyNumPacing = selectedModelNumberPacing
        let activeMusePacing = activeMuseQuota?.pacing()

        return AgyMenuBarRenderer.makeAntigravityImage(
            queriesToday: stats.queriesToday,
            litColor: color,
            showUsage: showModelUsageInIcon,
            selectedModelForIcon: selectedModelForIcon,
            activeUsageFraction: selectedModelUsageFraction,
            geminiUsageFraction: geminiUsageFraction,
            carbonUsageFraction: carbonUsageFraction,
            argonUsageFraction: argonUsageFraction,
            claudeUsageFraction: claudeUsageFraction,
            activeFillFraction: selectedModelCircleFillFraction,
            geminiFillFraction: geminiCircleFillFraction,
            carbonFillFraction: carbonCircleFillFraction,
            argonFillFraction: argonCircleFillFraction,
            claudeFillFraction: claudeCircleFillFraction,
            showMenuBarSpend: showMenuBarSpend,
            menuBarSpendSource: menuBarSpendSource,
            spendAmount: menuBarSpendAmount,
            gcpTodayCost: stats.gcpTodayCost,
            gcpTotalCost: stats.gcpTotalCost,
            todayCost: stats.todayCostEstimate,
            showMuseBadge: activeMuseQuota != nil,
            museRemainingFraction: activeMuseQuota?.remainingFraction,
            musePercentUsed: activeMuseQuota?.percentUsed,
            museResetShortText: activeMuseQuota?.ultraCompactCountdown(),
            museDisplayStyle: museMenuBarDisplayStyle,
            showPaceIndicator: showMenuBarPaceIndicator,
            colorByPacing: colorMenuBarByPacing,
            activePaceMarkerFraction: activeAgyRingPacing?.expectedRemainingFraction,
            activeNumberPacing: activeAgyNumPacing,
            activeRingPacing: activeAgyRingPacing,
            musePacing: activeMusePacing
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
    private var quotaPollingTimer: Timer?
    private var quotaPollingTask: Task<Void, Never>?
    private var lastFileChangedAt: Date?
    
    public var isRecentlyActive: Bool {
        if let lastFile = lastFileChangedAt, Date().timeIntervalSince(lastFile) < 120 {
            return true
        }
        let lastQuery = stats.lastQueryAt ?? stats.recentQueries.first?.timestamp
        guard let last = lastQuery else { return false }
        return Date().timeIntervalSince(last) < 120
    }
    
    public var adaptivePollingInterval: TimeInterval {
        return isRecentlyActive ? 15.0 : 60.0
    }
    
    public func setup() {
        guard !isSetup else { return }
        isSetup = true
        
        // Start watching for file changes with instant response
        watcher.cliDirOverride = cliDir
        watcher.onFileChanged = { [weak self] in
            Task { @MainActor [weak self] in
                self?.lastFileChangedAt = Date()
                self?.scheduleAdaptiveQuotaPolling()
            }
            Task { [weak self] in
                // Do NOT block UI updates waiting on slow network timeouts or clear verified quota.
                // Refresh stats immediately, preserving existing quotaInfo.
                await self?.refresh()
                await MainActor.run { [weak self] in
                    self?.scheduleAdaptiveQuotaPolling()
                }
                // Fast follow-up: language server quota accounting may take 1-2s to settle after streaming
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                await self?.refreshQuotaOnly(forceRefresh: true)
                await MainActor.run { [weak self] in
                    self?.scheduleAdaptiveQuotaPolling()
                }
            }
        }
        watcher.start()
        
        // Start adaptive background quota polling (15s active, 60s idle, 5s tolerance)
        startAdaptiveQuotaPolling()
        
        // Initial load
        Task {
            await refresh()
            if showMuseTracking {
                await refreshMuseQuota(forceRefresh: false)
            }
            await checkForUpdates()
        }
    }
    
    public func startAdaptiveQuotaPolling() {
        scheduleAdaptiveQuotaPolling()
    }
    
    public func stopAdaptiveQuotaPolling() {
        quotaPollingTimer?.invalidate()
        quotaPollingTimer = nil
        quotaPollingTask?.cancel()
        quotaPollingTask = nil
    }
    
    public func scheduleAdaptiveQuotaPolling() {
        quotaPollingTimer?.invalidate()
        let interval = adaptivePollingInterval
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshQuotaOnly()
                if let self, self.showMuseTracking {
                    let shouldPollMuse = self.lastMuseRefreshAt.map { Date().timeIntervalSince($0) >= 300.0 } ?? true
                    if shouldPollMuse {
                        await self.refreshMuseQuota(forceRefresh: false)
                    }
                }
                self?.scheduleAdaptiveQuotaPolling()
            }
        }
        timer.tolerance = 5.0
        RunLoop.main.add(timer, forMode: .common)
        quotaPollingTimer = timer
    }

    public func refreshMuseQuota(forceRefresh: Bool = false) async {
        let (enabled, manualCookie, alreadyRunning) = await MainActor.run { () -> (Bool, String, Bool) in
            guard !isRefreshingMuse else { return (showMuseTracking, museManualCookieHeader, true) }
            if showMuseTracking {
                isRefreshingMuse = true
                if museQuota == nil {
                    museFetchStatus = .loading
                }
            }
            return (showMuseTracking, museManualCookieHeader, false)
        }
        guard enabled, !alreadyRunning else { return }

        let result = await MuseQuotaService.fetchUsage(
            forceRefresh: forceRefresh,
            manualCookieHeader: manualCookie,
            userDefaults: userDefaults
        )

        await MainActor.run {
            self.lastMuseRefreshAt = Date()
            if let q = result.quota {
                self.museQuota = q
            }
            self.museFetchStatus = result.status
            self.isRefreshingMuse = false
        }
    }
    
    private static func emailsDiffer(_ a: String?, _ b: String?) -> Bool {
        let normA = a?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normB = b?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanA = (normA?.isEmpty == false) ? normA : nil
        let cleanB = (normB?.isEmpty == false) ? normB : nil
        return cleanA != cleanB
    }

    /// Fast-path quota refresh without re-reading or parsing history files (<1ms localhost request)
    public func refreshQuotaOnly(forceRefresh: Bool = false) async {
        let dir = await MainActor.run { self.cliDir }
        let resolvedEmail = await Task.detached(priority: .userInitiated) {
            AgyStatsService.resolveActiveConsumerEmail(cliDir: dir)
        }.value
        let (previousEmail, currentQuotaEmail) = await MainActor.run { () -> (String?, String?) in
            let prev = self.activeConsumerEmail
            if prev != resolvedEmail {
                self.activeConsumerEmail = resolvedEmail
            }
            return (prev, self.stats.quotaInfo?.email)
        }

        let emailChanged = Self.emailsDiffer(previousEmail, resolvedEmail)
        let quotaMismatches = resolvedEmail != nil && Self.emailsDiffer(currentQuotaEmail, resolvedEmail)
        let shouldForce = forceRefresh || emailChanged || quotaMismatches

        if emailChanged || quotaMismatches {
            AgyQuotaService.clearCache(clearActivePort: true)
        }

        guard let quota = await AgyQuotaService.fetchQuota(forceRefresh: shouldForce, expectedEmail: resolvedEmail) else { return }
        await MainActor.run {
            if self.activeConsumerEmail != resolvedEmail {
                self.activeConsumerEmail = resolvedEmail
            }
            if self.stats.quotaInfo != quota {
                self.stats.quotaInfo = quota
            }
        }
    }
    
    public func refresh() async {
        let canStart = await MainActor.run { () -> Bool in
            guard !isRefreshing else { return false }
            isRefreshing = true
            return true
        }
        guard canStart else { return }

        let dir = await MainActor.run { self.cliDir }
        let resolvedEmail = await Task.detached(priority: .userInitiated) {
            AgyStatsService.resolveActiveConsumerEmail(cliDir: dir)
        }.value
        let (previousEmail, currentQuota) = await MainActor.run { () -> (String?, AgyQuotaInfo?) in
            let prev = self.activeConsumerEmail
            if prev != resolvedEmail {
                self.activeConsumerEmail = resolvedEmail
            }
            return (prev, self.stats.quotaInfo)
        }

        let emailChanged = Self.emailsDiffer(previousEmail, resolvedEmail)
        let quotaMismatches = resolvedEmail != nil && Self.emailsDiffer(currentQuota?.email, resolvedEmail)
        if emailChanged || quotaMismatches {
            AgyQuotaService.clearCache(clearActivePort: true)
        }
        let safeExistingQuota: AgyQuotaInfo? = (emailChanged || quotaMismatches) ? nil : currentQuota
        
        let (loadedStats, loadedSettings) = await AgyStatsService.loadStats(cliDir: dir, existingQuota: safeExistingQuota)
        let expanded = dir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let path = (expanded as NSString).appendingPathComponent("history.jsonl")
        let connected = FileManager.default.fileExists(atPath: path)
        
        await MainActor.run {
            var updatedStats = loadedStats
            if updatedStats.quotaInfo == nil, let existingQuota = safeExistingQuota {
                updatedStats.quotaInfo = existingQuota
            }
            // Fast structural fingerprint check avoids O(40k) array equality scans on MainActor
            let statsChanged = self.stats.totalQueries != updatedStats.totalQueries
                || self.stats.queriesToday != updatedStats.queriesToday
                || abs(self.stats.totalCostEstimate - updatedStats.totalCostEstimate) > 0.000001
                || abs(self.stats.todayCostEstimate - updatedStats.todayCostEstimate) > 0.000001
                || abs(self.stats.gcpTotalCost - updatedStats.gcpTotalCost) > 0.000001
                || self.stats.quotaInfo != updatedStats.quotaInfo
                || self.stats.lastQueryAt != updatedStats.lastQueryAt
                || self.stats.discoveredConsumerEmails != updatedStats.discoveredConsumerEmails
                || self.stats.dailyUsage.count != updatedStats.dailyUsage.count
            if statsChanged {
                self.stats = updatedStats
            }
            if self.settings != loadedSettings {
                self.settings = loadedSettings
            }
            if self.isConnected != connected {
                self.isConnected = connected
            }
            self.reconcileGcpBaseline(with: loadedStats)
            self.isRefreshing = false
            self.scheduleAdaptiveQuotaPolling()
        }
    }
    
    private func restartWatcher() {
        watcher.stop()
        watcher.cliDirOverride = cliDir
        watcher.start()
    }
    
    deinit {
        watcher.stop()
        quotaPollingTimer?.invalidate()
        quotaPollingTimer = nil
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
            let didInstall = await SelfUpdater.update(
                dmgURL: dmgURL,
                publishedAt: update.publishedAt,
                version: update.version
            ) { [weak self] state in
                Task { @MainActor in
                    self?.selfUpdateState = state
                }
            }
            if didInstall, update.isRolling, let ts = update.publishedAt {
                UpdateChecker.recordInstalledRollingTimestamp(ts, version: update.version)
            }
        }
    }
}
