//
//  AgyQuotaService.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import Foundation

public actor AgyQuotaService {

    // JSON response structures for RetrieveUserQuotaSummary
    private struct QuotaSummaryResponse: Decodable {
        let code: CodeValue?
        let response: QuotaSummaryPayload?
        let summary: QuotaSummaryPayload?
        let description: String?
        let groups: [QuotaSummaryGroupPayload]?

        var rootPayload: QuotaSummaryPayload? {
            if let groups = groups {
                return QuotaSummaryPayload(description: description, groups: groups)
            }
            return nil
        }
    }

    private struct QuotaSummaryPayload: Decodable {
        let description: String?
        let groups: [QuotaSummaryGroupPayload]
    }

    private struct QuotaSummaryGroupPayload: Decodable {
        let displayName: String?
        let description: String?
        let buckets: [QuotaSummaryBucketPayload]?
    }

    private struct QuotaSummaryBucketPayload: Decodable {
        let bucketId: String?
        let displayName: String?
        let description: String?
        let disabled: Bool?
        let remainingFraction: Double?
        let remaining: QuotaSummaryRemainingPayload?
        let resetTime: String?

        var resolvedRemainingFraction: Double? {
            remainingFraction ?? remaining?.remainingFraction
        }
    }

    private struct QuotaSummaryRemainingPayload: Decodable {
        let remainingFraction: Double?

        private enum CodingKeys: String, CodingKey {
            case remainingFraction
            case oneofCase = "case"
            case value
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let remainingFraction = try container.decodeIfPresent(Double.self, forKey: .remainingFraction) {
                self.remainingFraction = remainingFraction
                return
            }
            let oneofCase = try container.decodeIfPresent(String.self, forKey: .oneofCase)
            if oneofCase == "remainingFraction" {
                self.remainingFraction = try container.decodeIfPresent(Double.self, forKey: .value)
            } else {
                self.remainingFraction = nil
            }
        }
    }

    private enum CodeValue: Decodable {
        case int(Int)
        case string(String)

        var isOK: Bool {
            switch self {
            case let .int(val): return val == 0
            case let .string(val): return val.lowercased() == "ok" || val.lowercased() == "success" || val == "0"
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let val = try? container.decode(Int.self) {
                self = .int(val)
                return
            }
            if let val = try? container.decode(String.self) {
                self = .string(val)
                return
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported code type")
        }
    }

    public struct AvailableCreditPayload: Decodable, Sendable {
        public let creditType: String?
        public let creditAmount: Int?
        public let minimumCreditAmountForUsage: Int?

        private enum CodingKeys: String, CodingKey {
            case creditType
            case creditAmount
            case minimumCreditAmountForUsage
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.creditType = try container.decodeIfPresent(String.self, forKey: .creditType)
            self.creditAmount = Self.decodeFlexibleInt(from: container, forKey: .creditAmount)
            self.minimumCreditAmountForUsage = Self.decodeFlexibleInt(from: container, forKey: .minimumCreditAmountForUsage)
        }

        private static func decodeFlexibleInt(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> Int? {
            if let intVal = try? container.decodeIfPresent(Int.self, forKey: key) {
                return intVal
            }
            if let strVal = try? container.decodeIfPresent(String.self, forKey: key) {
                return Int(strVal.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: key) {
                return Int(doubleVal)
            }
            return nil
        }
    }

    public struct DecodedUserStatus: Equatable, Sendable {
        public let email: String?
        public let plan: String?
        public let googleOneAiCredits: Int?
        public let minimumCreditAmountForUsage: Int?
    }

    private struct UserStatusResponse: Decodable {
        let userStatus: UserStatus?
    }

    private struct UserStatus: Decodable {
        let email: String?
        let userTier: UserTier?
    }

    private struct UserTier: Decodable {
        let name: String?
        let availableCredits: [AvailableCreditPayload]?
    }

    public static func decodeUserStatus(from data: Data) -> DecodedUserStatus? {
        guard let statusResp = try? JSONDecoder().decode(UserStatusResponse.self, from: data),
              let status = statusResp.userStatus else {
            return nil
        }
        let creditsList = status.userTier?.availableCredits ?? []
        let googleOneEntries = creditsList.filter {
            $0.creditType?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "GOOGLE_ONE_AI"
        }
        let googleOneAiCredits: Int?
        let minCreditAmount: Int?
        if googleOneEntries.isEmpty {
            googleOneAiCredits = nil
            minCreditAmount = creditsList.compactMap(\.minimumCreditAmountForUsage).first
        } else {
            googleOneAiCredits = googleOneEntries.reduce(0) { $0 + ($1.creditAmount ?? 0) }
            minCreditAmount = googleOneEntries.compactMap(\.minimumCreditAmountForUsage).first
                ?? creditsList.compactMap(\.minimumCreditAmountForUsage).first
        }
        return DecodedUserStatus(
            email: status.email,
            plan: status.userTier?.name,
            googleOneAiCredits: googleOneAiCredits,
            minimumCreditAmountForUsage: minCreditAmount
        )
    }

    private struct CachedQuota {
        let info: AgyQuotaInfo?
        let timestamp: Date
    }

    private struct CachedPorts {
        let ports: [Int]
        let portToCsrf: [Int: String]
        let timestamp: Date
    }

    private static let isRunningTests: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    private static let testHostDefaults = UserDefaults(suiteName: "com.agy-usage-stats.xctest-host-isolated")!
    private static var defaultStore: UserDefaults { isRunningTests ? testHostDefaults : .standard }

    private static let persistedQuotaKey = "agy.lastKnownSubscriptionQuota"
    private static let persistedQuotasByEmailKey = "agy.persistedQuotasByEmail"
    private static let peakGoogleOneAiCreditsKey = "agy.peakGoogleOneAiCreditsByEmail"
    private static var _lastKnownSubscriptionQuota: AgyQuotaInfo? = {
        if let data = defaultStore.data(forKey: persistedQuotaKey),
           let decoded = try? JSONDecoder().decode(AgyQuotaInfo.self, from: data) {
            if let email = decoded.email, isSyntheticTestEmail(email) {
                if !isRunningTests {
                    defaultStore.removeObject(forKey: persistedQuotaKey)
                }
                return nil
            }
            return decoded
        }
        return nil
    }()
    private static var _peakGoogleOneAiCreditsByEmail: [String: Int] = {
        loadPeakGoogleOneAiCreditsDict(from: defaultStore)
    }()

    private static var _persistedQuotasByEmail: [String: AgyQuotaInfo] = {
        _ = _peakGoogleOneAiCreditsByEmail
        if let data = defaultStore.data(forKey: persistedQuotasByEmailKey),
           let decoded = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: data) {
            return sanitizePersistedQuotasDict(decoded, persistingTo: isRunningTests ? nil : defaultStore)
        }
        return [:]
    }()

    public static var lastKnownSubscriptionQuota: AgyQuotaInfo? {
        get {
            quotaLock.lock()
            defer { quotaLock.unlock() }
            return _lastKnownSubscriptionQuota
        }
        set {
            quotaLock.lock()
            _lastKnownSubscriptionQuota = newValue
            quotaLock.unlock()
        }
    }

    private struct ResetTimeObservation {
        let resetDate: Date
        let observedAt: Date
        let lastDetectedStarted: Bool?
    }

    private static var lastActivePort: Int? = nil
    private static var cachedQuota: CachedQuota? = nil
    private static var cachedDetectedPorts: CachedPorts? = nil
    private static var bucketResetObservations: [String: ResetTimeObservation] = [:]
    private static let cacheTTL: TimeInterval = 4.0
    private static let nilCacheTTL: TimeInterval = 15.0
    private static let portsCacheTTL: TimeInterval = 5.0
    private static let quotaLock = NSLock()

    public static var hasActiveSession: Bool {
        quotaLock.lock()
        defer { quotaLock.unlock() }
        return lastActivePort != nil
    }

    public static var activePort: Int? {
        quotaLock.lock()
        defer { quotaLock.unlock() }
        return lastActivePort
    }

    private static let sharedLocalhostSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.5
        config.timeoutIntervalForResource = 0.5
        config.httpShouldUsePipelining = true
        let delegate = LocalhostSessionDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    private static func normalizeEmailKey(_ email: String?) -> String? {
        guard let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    public static func isSyntheticTestEmail(_ email: String) -> Bool {
        let lower = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let atIndex = lower.lastIndex(of: "@") else { return false }
        let domain = String(lower[lower.index(after: atIndex)...])
        guard !domain.isEmpty else { return false }
        if domain == "test.com" || domain == "example.com" || domain == "example.org" {
            return true
        }
        let reservedSuffixes = [".internal", ".invalid", ".localhost", ".test", ".example.com", ".example.org", ".test.com"]
        if reservedSuffixes.contains(where: { domain.hasSuffix($0) })
            || domain == "localhost" || domain == "internal" || domain == "invalid" || domain == "test" {
            return true
        }
        return false
    }

    private static func sanitizePersistedQuotasDict(
        _ dict: [String: AgyQuotaInfo],
        persistingTo store: UserDefaults?
    ) -> [String: AgyQuotaInfo] {
        var cleaned: [String: AgyQuotaInfo] = [:]
        var removedAny = false
        for (key, value) in dict {
            let emailToCheck = value.email ?? key
            if isSyntheticTestEmail(key) || isSyntheticTestEmail(emailToCheck) {
                removedAny = true
                continue
            }
            cleaned[key] = value
        }
        if removedAny, let store,
           let encoded = try? JSONEncoder().encode(cleaned) {
            store.set(encoded, forKey: persistedQuotasByEmailKey)
        }
        return cleaned
    }

    private static func loadPersistedQuotaUnlocked(
        expectedEmail: String? = nil,
        now: Date = Date()
    ) -> AgyQuotaInfo? {
        if let targetEmail = normalizeEmailKey(expectedEmail) {
            guard !isSyntheticTestEmail(targetEmail) else { return nil }
            if let emailMatch = _persistedQuotasByEmail[targetEmail] {
                return emailMatch.normalizedForCurrentTime(now: now)
            }
            if let last = _lastKnownSubscriptionQuota,
               normalizeEmailKey(last.email) == targetEmail {
                return last.normalizedForCurrentTime(now: now)
            }
            return nil
        }

        return _lastKnownSubscriptionQuota?.normalizedForCurrentTime(now: now)
    }

    public static func loadPersistedQuota(
        expectedEmail: String? = nil,
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) -> AgyQuotaInfo? {
        let resolvedStore = (userDefaults === UserDefaults.standard) ? defaultStore : userDefaults
        if resolvedStore === defaultStore {
            quotaLock.lock()
            defer { quotaLock.unlock() }
            return loadPersistedQuotaUnlocked(expectedEmail: expectedEmail, now: now)
        }

        var dict: [String: AgyQuotaInfo] = [:]
        if let dictData = resolvedStore.data(forKey: persistedQuotasByEmailKey),
           let decodedDict = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: dictData) {
            dict = sanitizePersistedQuotasDict(decodedDict, persistingTo: resolvedStore)
        }
        var lastKnown: AgyQuotaInfo? = nil
        if let data = resolvedStore.data(forKey: persistedQuotaKey),
           let decoded = try? JSONDecoder().decode(AgyQuotaInfo.self, from: data) {
            if let email = decoded.email, isSyntheticTestEmail(email) {
                resolvedStore.removeObject(forKey: persistedQuotaKey)
            } else {
                lastKnown = decoded
            }
        }
        _ = loadPeakGoogleOneAiCreditsDict(from: resolvedStore)

        if let targetEmail = normalizeEmailKey(expectedEmail) {
            guard !isSyntheticTestEmail(targetEmail) else { return nil }
            if let emailMatch = dict[targetEmail] {
                return emailMatch.normalizedForCurrentTime(now: now)
            }
            if let last = lastKnown, normalizeEmailKey(last.email) == targetEmail {
                return last.normalizedForCurrentTime(now: now)
            }
            return nil
        }

        return lastKnown?.normalizedForCurrentTime(now: now)
    }

    private static func loadPeakGoogleOneAiCreditsDict(from userDefaults: UserDefaults) -> [String: Int] {
        guard let raw = userDefaults.dictionary(forKey: peakGoogleOneAiCreditsKey) else {
            return [:]
        }
        var result: [String: Int] = [:]
        var removedAny = false
        for (key, value) in raw {
            if isSyntheticTestEmail(key) {
                removedAny = true
                continue
            }
            if let intVal = value as? Int {
                result[key] = intVal
            } else if let numVal = value as? NSNumber {
                result[key] = numVal.intValue
            }
        }
        if removedAny {
            userDefaults.set(result, forKey: peakGoogleOneAiCreditsKey)
        }
        return result
    }

    private static func updatePeakGoogleOneAiCreditsUnlocked(
        emailKey: String,
        credits: Int,
        userDefaults: UserDefaults
    ) -> [String: Int]? {
        guard !isSyntheticTestEmail(emailKey) else { return nil }
        if userDefaults === defaultStore {
            let existing = _peakGoogleOneAiCreditsByEmail[emailKey]
            let newPeak = existing.map { max($0, credits) } ?? credits
            if existing != newPeak {
                _peakGoogleOneAiCreditsByEmail[emailKey] = newPeak
                return _peakGoogleOneAiCreditsByEmail
            }
            return nil
        }
        var peaks = loadPeakGoogleOneAiCreditsDict(from: userDefaults)
        let existing = peaks[emailKey]
        let newPeak = existing.map { max($0, credits) } ?? credits
        if existing != newPeak {
            peaks[emailKey] = newPeak
            userDefaults.set(peaks, forKey: peakGoogleOneAiCreditsKey)
        }
        return nil
    }

    public static func peakGoogleOneAiCredits(
        forEmail: String,
        userDefaults: UserDefaults = .standard
    ) -> Int? {
        guard let emailKey = normalizeEmailKey(forEmail),
              !isSyntheticTestEmail(emailKey) else { return nil }
        let resolvedStore = (userDefaults === UserDefaults.standard) ? defaultStore : userDefaults
        if resolvedStore === defaultStore {
            return quotaLock.withLock { _peakGoogleOneAiCreditsByEmail[emailKey] }
        }
        return loadPeakGoogleOneAiCreditsDict(from: resolvedStore)[emailKey]
    }

    public static func allPersistedQuotas(
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) -> [String: AgyQuotaInfo] {
        let resolvedStore = (userDefaults === UserDefaults.standard) ? defaultStore : userDefaults
        if resolvedStore === defaultStore {
            let snapshot = quotaLock.withLock { _persistedQuotasByEmail }
            return snapshot.mapValues { $0.normalizedForCurrentTime(now: now) }
        }

        _ = loadPeakGoogleOneAiCreditsDict(from: resolvedStore)
        guard let dictData = resolvedStore.data(forKey: persistedQuotasByEmailKey),
              let decodedDict = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: dictData) else {
            return [:]
        }
        let cleaned = sanitizePersistedQuotasDict(decodedDict, persistingTo: resolvedStore)
        return cleaned.mapValues { $0.normalizedForCurrentTime(now: now) }
    }

    public static func saveQuotaSnapshotForAccount(_ info: AgyQuotaInfo, userDefaults: UserDefaults = .standard) {
        guard let emailKey = normalizeEmailKey(info.email),
              !isSyntheticTestEmail(emailKey) else { return }
        let resolvedStore = (userDefaults === UserDefaults.standard) ? defaultStore : userDefaults
        if resolvedStore === defaultStore {
            let (dictSnapshot, updatedPeaks): ([String: AgyQuotaInfo], [String: Int]?) = quotaLock.withLock {
                _persistedQuotasByEmail[emailKey] = info
                let peaks = info.googleOneAiCredits.flatMap {
                    updatePeakGoogleOneAiCreditsUnlocked(emailKey: emailKey, credits: $0, userDefaults: resolvedStore)
                }
                return (_persistedQuotasByEmail, peaks)
            }

            if let updatedPeaks {
                resolvedStore.set(updatedPeaks, forKey: peakGoogleOneAiCreditsKey)
            }
            if let dictData = try? JSONEncoder().encode(dictSnapshot) {
                resolvedStore.set(dictData, forKey: persistedQuotasByEmailKey)
            }
            return
        }

        var dict: [String: AgyQuotaInfo] = [:]
        if let dictData = resolvedStore.data(forKey: persistedQuotasByEmailKey),
           let decodedDict = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: dictData) {
            dict = sanitizePersistedQuotasDict(decodedDict, persistingTo: resolvedStore)
        }
        dict[emailKey] = info
        if let credits = info.googleOneAiCredits {
            _ = updatePeakGoogleOneAiCreditsUnlocked(emailKey: emailKey, credits: credits, userDefaults: resolvedStore)
        }
        if let dictData = try? JSONEncoder().encode(dict) {
            resolvedStore.set(dictData, forKey: persistedQuotasByEmailKey)
        }
    }

    public static func savePersistedQuota(_ info: AgyQuotaInfo, userDefaults: UserDefaults = .standard) {
        if let email = info.email, isSyntheticTestEmail(email) {
            return
        }
        let resolvedStore = (userDefaults === UserDefaults.standard) ? defaultStore : userDefaults
        if resolvedStore === defaultStore {
            let (dictSnapshot, updatedPeaks): ([String: AgyQuotaInfo], [String: Int]?) = quotaLock.withLock {
                _lastKnownSubscriptionQuota = info
                var peaks: [String: Int]? = nil
                if let emailKey = normalizeEmailKey(info.email) {
                    _persistedQuotasByEmail[emailKey] = info
                    if let credits = info.googleOneAiCredits {
                        peaks = updatePeakGoogleOneAiCreditsUnlocked(emailKey: emailKey, credits: credits, userDefaults: resolvedStore)
                    }
                }
                return (_persistedQuotasByEmail, peaks)
            }

            if let updatedPeaks {
                resolvedStore.set(updatedPeaks, forKey: peakGoogleOneAiCreditsKey)
            }
            if let data = try? JSONEncoder().encode(info) {
                resolvedStore.set(data, forKey: persistedQuotaKey)
            }
            if let dictData = try? JSONEncoder().encode(dictSnapshot) {
                resolvedStore.set(dictData, forKey: persistedQuotasByEmailKey)
            }
            return
        }

        var dict: [String: AgyQuotaInfo] = [:]
        if let dictData = resolvedStore.data(forKey: persistedQuotasByEmailKey),
           let decodedDict = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: dictData) {
            dict = sanitizePersistedQuotasDict(decodedDict, persistingTo: resolvedStore)
        }
        if let emailKey = normalizeEmailKey(info.email) {
            dict[emailKey] = info
            if let credits = info.googleOneAiCredits {
                _ = updatePeakGoogleOneAiCreditsUnlocked(emailKey: emailKey, credits: credits, userDefaults: resolvedStore)
            }
        }
        if let data = try? JSONEncoder().encode(info) {
            resolvedStore.set(data, forKey: persistedQuotaKey)
        }
        if let dictData = try? JSONEncoder().encode(dict) {
            resolvedStore.set(dictData, forKey: persistedQuotasByEmailKey)
        }
    }

    public static func removePersistedAccount(_ email: String, userDefaults: UserDefaults? = nil) {
        guard let emailKey = normalizeEmailKey(email) else { return }
        let targetStore = userDefaults ?? .standard
        let resolvedStore = (targetStore === UserDefaults.standard) ? defaultStore : targetStore

        if resolvedStore === defaultStore {
            let (dictSnapshot, removedLast, updatedPeaks): ([String: AgyQuotaInfo], Bool, [String: Int]?) = quotaLock.withLock {
                _persistedQuotasByEmail.removeValue(forKey: emailKey)
                var clearedLast = false
                if let last = _lastKnownSubscriptionQuota, normalizeEmailKey(last.email) == emailKey {
                    _lastKnownSubscriptionQuota = nil
                    clearedLast = true
                }
                let peaks: [String: Int]? = (_peakGoogleOneAiCreditsByEmail.removeValue(forKey: emailKey) != nil)
                    ? _peakGoogleOneAiCreditsByEmail
                    : nil
                return (_persistedQuotasByEmail, clearedLast, peaks)
            }

            if removedLast {
                resolvedStore.removeObject(forKey: persistedQuotaKey)
            }
            if let updatedPeaks {
                resolvedStore.set(updatedPeaks, forKey: peakGoogleOneAiCreditsKey)
            }
            if let dictData = try? JSONEncoder().encode(dictSnapshot) {
                resolvedStore.set(dictData, forKey: persistedQuotasByEmailKey)
            }
            return
        }

        if let dictData = resolvedStore.data(forKey: persistedQuotasByEmailKey),
           var dict = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: dictData) {
            if dict.removeValue(forKey: emailKey) != nil,
               let encoded = try? JSONEncoder().encode(dict) {
                resolvedStore.set(encoded, forKey: persistedQuotasByEmailKey)
            }
        }
        if let data = resolvedStore.data(forKey: persistedQuotaKey),
           let last = try? JSONDecoder().decode(AgyQuotaInfo.self, from: data),
           normalizeEmailKey(last.email) == emailKey {
            resolvedStore.removeObject(forKey: persistedQuotaKey)
        }
        var peaks = loadPeakGoogleOneAiCreditsDict(from: resolvedStore)
        if peaks.removeValue(forKey: emailKey) != nil {
            resolvedStore.set(peaks, forKey: peakGoogleOneAiCreditsKey)
        }
    }

    public static func clearCache(clearActivePort: Bool = false) {
        quotaLock.withLock {
            cachedQuota = nil
            cachedDetectedPorts = nil
            if clearActivePort {
                lastActivePort = nil
            }
        }
    }

    // Synchronous lock helpers ensure NSLock is NEVER held across Swift concurrency suspension points or actor hops.
    private static func readCachedQuotaIfValid(targetEmail: String?) -> (hit: Bool, info: AgyQuotaInfo?) {
        quotaLock.withLock {
            guard let cached = cachedQuota else { return (false, nil) }
            let ttl = cached.info != nil ? cacheTTL : nilCacheTTL
            let emailMatches = targetEmail == nil || normalizeEmailKey(cached.info?.email) == targetEmail
            if emailMatches && Date().timeIntervalSince(cached.timestamp) < ttl {
                return (true, cached.info)
            }
            return (false, nil)
        }
    }

    private static func resolveAndStoreFallbackQuota(
        targetEmail: String?,
        resolvedExpectedEmail: String?
    ) -> AgyQuotaInfo? {
        let rawFallback: AgyQuotaInfo? = quotaLock.withLock {
            lastActivePort = nil
            let base: AgyQuotaInfo?
            if let targetEmail {
                base = loadPersistedQuotaUnlocked(expectedEmail: targetEmail)
                    ?? AgyQuotaInfo(email: resolvedExpectedEmail, plan: nil, groups: [])
            } else {
                base = cachedQuota?.info ?? _lastKnownSubscriptionQuota ?? loadPersistedQuotaUnlocked()
            }
            cachedQuota = CachedQuota(info: base, timestamp: Date())
            return base
        }
        return rawFallback?.normalizedForCurrentTime()
    }

    public static func fetchQuota(forceRefresh: Bool = false, expectedEmail: String? = nil) async -> AgyQuotaInfo? {
        let resolvedExpectedEmail = expectedEmail ?? AgyStatsService.resolveActiveConsumerEmail()
        let targetEmail = normalizeEmailKey(resolvedExpectedEmail)

        if !forceRefresh {
            let cachedResult = readCachedQuotaIfValid(targetEmail: targetEmail)
            if cachedResult.hit {
                return cachedResult.info?.normalizedForCurrentTime()
            }
        }

        return await Task.detached(priority: .userInitiated) {
            // Try last active port first if available
            let knownPort = quotaLock.withLock { lastActivePort }

            var invalidatedStalePort = false
            if let port = knownPort {
                if let info = await fetchFromPort(port), !info.groups.isEmpty {
                    if targetEmail == nil || normalizeEmailKey(info.email) == targetEmail {
                        savePersistedQuota(info)
                        quotaLock.withLock {
                            cachedQuota = CachedQuota(info: info, timestamp: Date())
                        }
                        return info
                    } else {
                        invalidatedStalePort = true
                        quotaLock.withLock {
                            if lastActivePort == port {
                                lastActivePort = nil
                            }
                        }
                    }
                }
            }

            let detectedPorts = detectAgyPorts(forceRefresh: forceRefresh || invalidatedStalePort)
            let portsToProbe = invalidatedStalePort ? detectedPorts : detectedPorts.filter { $0 != knownPort }

            guard !portsToProbe.isEmpty else {
                return resolveAndStoreFallbackQuota(targetEmail: targetEmail, resolvedExpectedEmail: resolvedExpectedEmail)
            }

            // Probe detected ports in parallel, prioritizing expectedEmail when set
            let found = await probePorts(portsToProbe, expectedEmail: resolvedExpectedEmail) { port in
                await fetchFromPort(port)
            }

            if let (port, info) = found {
                quotaLock.withLock {
                    lastActivePort = port
                    cachedQuota = CachedQuota(info: info, timestamp: Date())
                }
                savePersistedQuota(info)
                return info
            } else {
                return resolveAndStoreFallbackQuota(targetEmail: targetEmail, resolvedExpectedEmail: resolvedExpectedEmail)
            }
        }.value
    }

    public static func probePorts(
        _ ports: [Int],
        expectedEmail: String? = nil,
        fetcher: @escaping @Sendable (Int) async -> AgyQuotaInfo?
    ) async -> (Int, AgyQuotaInfo)? {
        guard !ports.isEmpty else { return nil }
        let targetEmail = normalizeEmailKey(expectedEmail)

        return await withTaskGroup(of: (Int, Int, AgyQuotaInfo?).self) { group in
            for (index, port) in ports.enumerated() {
                group.addTask {
                    let info = await fetcher(port)
                    return (index, port, info)
                }
            }

            var bestFallback: (index: Int, port: Int, info: AgyQuotaInfo)? = nil

            for await (index, port, info) in group {
                guard let info = info, !info.groups.isEmpty else { continue }

                if let targetEmail {
                    if normalizeEmailKey(info.email) == targetEmail {
                        group.cancelAll()
                        return (port, info)
                    }
                    if bestFallback == nil || index < bestFallback!.index {
                        bestFallback = (index, port, info)
                    }
                } else {
                    group.cancelAll()
                    return (port, info)
                }
            }

            if let fallback = bestFallback {
                return (fallback.port, fallback.info)
            }
            return nil
        }
    }

    public static func parsePsElapsedSeconds(_ etime: String) -> Int {
        let trimmed = etime.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Int.max }

        let daySplit = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let days: Int
        let timePart: Substring
        if daySplit.count == 2 {
            guard let d = Int(daySplit[0]), d >= 0 else { return Int.max }
            days = d
            timePart = daySplit[1]
        } else {
            days = 0
            timePart = daySplit[0]
        }

        let timeComponents = timePart.split(separator: ":", omittingEmptySubsequences: false)
        let hours: Int
        let minutes: Int
        let seconds: Int
        switch timeComponents.count {
        case 2:
            guard let m = Int(timeComponents[0]), let s = Int(timeComponents[1]), m >= 0, s >= 0 else {
                return Int.max
            }
            hours = 0
            minutes = m
            seconds = s
        case 3:
            guard let h = Int(timeComponents[0]), let m = Int(timeComponents[1]), let s = Int(timeComponents[2]),
                  h >= 0, m >= 0, s >= 0 else {
                return Int.max
            }
            hours = h
            minutes = m
            seconds = s
        default:
            return Int.max
        }

        return days * 86_400 + hours * 3_600 + minutes * 60 + seconds
    }

    public static func detectAgyPorts(forceRefresh: Bool = false) -> [Int] {
        quotaLock.lock()
        if !forceRefresh, let cached = cachedDetectedPorts, Date().timeIntervalSince(cached.timestamp) < portsCacheTTL {
            let ports = cached.ports
            quotaLock.unlock()
            return ports
        }
        quotaLock.unlock()

        let lsofPath = ["/usr/sbin/lsof", "/usr/bin/lsof"].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) ?? "/usr/sbin/lsof"

        guard let lsofOutput = runCommand(
            executable: lsofPath,
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "agy", "-c", "language_server"]
        ), !lsofOutput.isEmpty else {
            quotaLock.lock()
            cachedDetectedPorts = CachedPorts(ports: [], portToCsrf: [:], timestamp: Date())
            quotaLock.unlock()
            return []
        }

        struct DiscoveredPort {
            let pid: Int
            let port: Int
            let is10u: Bool
        }

        var discovered: [DiscoveredPort] = []
        var candidatePids = Set<Int>()
        let lines = lsofOutput.components(separatedBy: .newlines)
        let listenRegex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#)

        for line in lines {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count >= 2, let pid = Int(tokens[1]) else { continue }

            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = listenRegex?.firstMatch(in: line, options: [], range: range),
                  let portRange = Range(match.range(at: 1), in: line),
                  let port = Int(line[portRange]) else { continue }

            candidatePids.insert(pid)
            discovered.append(DiscoveredPort(pid: pid, port: port, is10u: line.contains("10u")))
        }

        guard !candidatePids.isEmpty else {
            quotaLock.lock()
            cachedDetectedPorts = CachedPorts(ports: [], portToCsrf: [:], timestamp: Date())
            quotaLock.unlock()
            return []
        }

        // Run at most ONE batched ps call to filter out .agy-gcp-home, capture process elapsed time, and extract CSRF tokens
        let pidArg = candidatePids.prefix(50).map(String.init).joined(separator: ",")
        var gcpPids = Set<Int>()
        var pidToCsrf: [Int: String] = [:]
        var pidToElapsed: [Int: Int] = [:]

        if let psOutput = runCommand(executable: "/bin/ps", arguments: ["-E", "-o", "pid=,etime=,command=", "-p", pidArg]) ??
                          runCommand(executable: "/bin/ps", arguments: ["-o", "pid=,etime=,command=", "-p", pidArg]) {
            let csrfRegex = try? NSRegularExpression(pattern: #"--csrf_token=([^\s]+)"#)
            let envCsrfRegex = try? NSRegularExpression(pattern: #"ANTIGRAVITY_CSRF_TOKEN=([^\s]+)"#)

            for psLine in psOutput.components(separatedBy: .newlines) {
                let trimmed = psLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard parts.count == 3, let pid = Int(parts[0]) else { continue }
                pidToElapsed[pid] = parsePsElapsedSeconds(String(parts[1]))
                let cmdAndEnv = String(parts[2])

                if cmdAndEnv.contains(".agy-gcp-home") {
                    gcpPids.insert(pid)
                    continue
                }

                let range = NSRange(cmdAndEnv.startIndex..<cmdAndEnv.endIndex, in: cmdAndEnv)
                if let match = csrfRegex?.firstMatch(in: cmdAndEnv, options: [], range: range),
                   let tokenRange = Range(match.range(at: 1), in: cmdAndEnv) {
                    pidToCsrf[pid] = String(cmdAndEnv[tokenRange])
                } else if let match = envCsrfRegex?.firstMatch(in: cmdAndEnv, options: [], range: range),
                          let tokenRange = Range(match.range(at: 1), in: cmdAndEnv) {
                    pidToCsrf[pid] = String(cmdAndEnv[tokenRange])
                }
            }
        }

        var primaryEntries: [(port: Int, elapsed: Int, index: Int)] = []
        var secondaryEntries: [(port: Int, elapsed: Int, index: Int)] = []
        var seenPorts = Set<Int>()
        var portToCsrf: [Int: String] = [:]

        for (index, item) in discovered.enumerated() {
            if gcpPids.contains(item.pid) { continue }
            if seenPorts.contains(item.port) { continue }
            seenPorts.insert(item.port)

            let elapsed = pidToElapsed[item.pid] ?? Int.max
            if item.is10u {
                primaryEntries.append((port: item.port, elapsed: elapsed, index: index))
            } else {
                secondaryEntries.append((port: item.port, elapsed: elapsed, index: index))
            }

            if let token = pidToCsrf[item.pid] {
                portToCsrf[item.port] = token
            }
        }

        primaryEntries.sort { ($0.elapsed, $0.index) < ($1.elapsed, $1.index) }
        secondaryEntries.sort { ($0.elapsed, $0.index) < ($1.elapsed, $1.index) }

        let ports = primaryEntries.map(\.port) + secondaryEntries.map(\.port)
        quotaLock.lock()
        cachedDetectedPorts = CachedPorts(ports: ports, portToCsrf: portToCsrf, timestamp: Date())
        quotaLock.unlock()
        return ports
    }

    private static func runCommand(executable: String, arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()

            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func getCsrfToken() -> String? {
        if let token = ProcessInfo.processInfo.environment["ANTIGRAVITY_CSRF_TOKEN"], !token.isEmpty {
            return token.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let tokenFile = homeDir.appendingPathComponent(".gemini/antigravity-cli/csrf_token")
        if let data = try? Data(contentsOf: tokenFile),
           let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }

        let altTokenFile = homeDir.appendingPathComponent(".gemini/config/csrf_token")
        if let data = try? Data(contentsOf: altTokenFile),
           let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return token
        }

        return nil
    }

    public static func extractCsrfToken(forPort port: Int) -> String? {
        quotaLock.lock()
        let token = cachedDetectedPorts?.portToCsrf[port]
        quotaLock.unlock()
        return token ?? getCsrfToken()
    }

    /// Compares consecutive live `resetTime` timestamps per `(email, bucketId)` so even if upstream AGY CLI
    /// changes its wording or reports 99–100% with a floating `now + window` timestamp, forward-drifting
    /// timestamps are automatically flagged as `isTimerStarted = false`.
    public static func annotateTimerStates(_ info: AgyQuotaInfo, now: Date = Date()) -> AgyQuotaInfo {
        let emailKey = normalizeEmailKey(info.email) ?? "_default"
        let annotatedGroups: [AgyQuotaGroup] = quotaLock.withLock {
            info.groups.map { group in
                let annotatedBuckets = group.buckets.map { bucket -> AgyQuotaBucket in
                    guard !bucket.disabled, let resetDate = bucket.parsedResetDate else {
                        return bucket
                    }
                    let obsKey = "\(emailKey)::\(bucket.bucketId)"
                    let frac = bucket.remainingFraction ?? 1.0
                    var detectedStarted: Bool? = bucket.isTimerStarted

                    if let prev = bucketResetObservations[obsKey] {
                        let elapsed = now.timeIntervalSince(prev.observedAt)
                        if elapsed >= 2.0 {
                            let resetDelta = resetDate.timeIntervalSince(prev.resetDate)
                            if resetDelta >= 1.5 && resetDelta <= elapsed + 15.0 && frac >= 0.98 {
                                // `resetTime` slid forward along with wall-clock time -> window timer has not begun
                                detectedStarted = false
                            } else if abs(resetDelta) < 1.5 && frac < 0.999 {
                                // `resetTime` is anchored while quota is consumed -> active countdown
                                detectedStarted = true
                            } else if resetDelta < -60.0 || resetDelta > elapsed + 60.0 {
                                // Genuine window rollover/reset; clear stale state
                                detectedStarted = nil
                            } else {
                                detectedStarted = prev.lastDetectedStarted
                            }
                            bucketResetObservations[obsKey] = ResetTimeObservation(
                                resetDate: resetDate,
                                observedAt: now,
                                lastDetectedStarted: detectedStarted
                            )
                        } else {
                            detectedStarted = prev.lastDetectedStarted
                        }
                    } else {
                        bucketResetObservations[obsKey] = ResetTimeObservation(
                            resetDate: resetDate,
                            observedAt: now,
                            lastDetectedStarted: detectedStarted
                        )
                    }

                    guard detectedStarted != bucket.isTimerStarted else { return bucket }
                    return AgyQuotaBucket(
                        bucketId: bucket.bucketId,
                        displayName: bucket.displayName,
                        remainingFraction: bucket.remainingFraction,
                        resetDescription: bucket.resetDescription,
                        disabled: bucket.disabled,
                        resetTime: bucket.resetTime,
                        isTimerStarted: detectedStarted
                    )
                }
                return AgyQuotaGroup(
                    displayName: group.displayName,
                    description: group.description,
                    buckets: annotatedBuckets
                )
            }
        }
        return AgyQuotaInfo(
            email: info.email,
            plan: info.plan,
            groups: annotatedGroups,
            googleOneAiCredits: info.googleOneAiCredits,
            minimumCreditAmountForUsage: info.minimumCreditAmountForUsage,
            lastUpdated: info.lastUpdated
        )
    }

    public static func resetTimerObservations() {
        quotaLock.withLock {
            bucketResetObservations.removeAll()
        }
    }

    private static func fetchFromPort(_ port: Int) async -> AgyQuotaInfo? {

        // 1. Prepare RetrieveUserQuotaSummary
        guard let summaryUrl = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"),
              let statusUrl = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else {
            return nil
        }

        let csrfToken = extractCsrfToken(forPort: port) ?? getCsrfToken()

        var summaryRequest = URLRequest(url: summaryUrl)
        summaryRequest.httpMethod = "POST"
        summaryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        summaryRequest.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if let token = csrfToken {
            summaryRequest.setValue(token, forHTTPHeaderField: "x-codeium-csrf-token")
        }
        summaryRequest.httpBody = try? JSONSerialization.data(withJSONObject: ["forceRefresh": true], options: [])

        var statusRequest = URLRequest(url: statusUrl)
        statusRequest.httpMethod = "POST"
        statusRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        statusRequest.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if let token = csrfToken {
            statusRequest.setValue(token, forHTTPHeaderField: "x-codeium-csrf-token")
        }
        statusRequest.httpBody = try? JSONSerialization.data(withJSONObject: [:], options: [])

        do {
            async let summaryTask = sharedLocalhostSession.data(for: summaryRequest)
            async let statusTask = sharedLocalhostSession.data(for: statusRequest)

            let (summaryData, _) = try await summaryTask
            let decoder = JSONDecoder()
            let summaryResp = try decoder.decode(QuotaSummaryResponse.self, from: summaryData)

            let payload = summaryResp.response ?? summaryResp.summary ?? summaryResp.rootPayload
            guard let actualPayload = payload else {
                return nil
            }

            let groups = actualPayload.groups.compactMap { groupPayload -> AgyQuotaGroup? in
                let displayName = groupPayload.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Quota"
                let buckets = (groupPayload.buckets ?? []).compactMap { bucketPayload -> AgyQuotaBucket? in
                    guard let bucketId = bucketPayload.bucketId else { return nil }
                    return AgyQuotaBucket(
                        bucketId: bucketId,
                        displayName: bucketPayload.displayName ?? bucketId,
                        remainingFraction: bucketPayload.resolvedRemainingFraction,
                        resetDescription: bucketPayload.description,
                        disabled: bucketPayload.disabled ?? false,
                        resetTime: bucketPayload.resetTime
                    )
                }
                guard !buckets.isEmpty else { return nil }
                return AgyQuotaGroup(
                    displayName: displayName,
                    description: groupPayload.description,
                    buckets: buckets
                )
            }

            var email: String? = nil
            var plan: String? = nil
            var googleOneAiCredits: Int? = nil
            var minimumCreditAmountForUsage: Int? = nil

            if let (statusData, _) = try? await statusTask,
               let decodedStatus = decodeUserStatus(from: statusData) {
                email = decodedStatus.email
                plan = decodedStatus.plan
                googleOneAiCredits = decodedStatus.googleOneAiCredits
                minimumCreditAmountForUsage = decodedStatus.minimumCreditAmountForUsage
            }

            let now = Date()

            // If groups is empty, but status call succeeded (e.g. GCP direct project mode or pay-as-you-go)
            if groups.isEmpty {
                if email != nil || plan != nil {
                    return AgyQuotaInfo(
                        email: email,
                        plan: plan,
                        groups: [],
                        googleOneAiCredits: googleOneAiCredits,
                        minimumCreditAmountForUsage: minimumCreditAmountForUsage,
                        lastUpdated: now
                    )
                }
                return nil
            }

            let rawInfo = AgyQuotaInfo(
                email: email,
                plan: plan,
                groups: groups,
                googleOneAiCredits: googleOneAiCredits,
                minimumCreditAmountForUsage: minimumCreditAmountForUsage,
                lastUpdated: now
            )
            let info = annotateTimerStates(rawInfo, now: now)
            if normalizeEmailKey(email) != nil {
                saveQuotaSnapshotForAccount(info)
            }
            return info
        } catch {
            return nil
        }
    }
}

final class LocalhostSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let protectionSpace = challenge.protectionSpace
        let host = protectionSpace.host.lowercased()
        if host == "127.0.0.1" || host == "localhost",
           protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
