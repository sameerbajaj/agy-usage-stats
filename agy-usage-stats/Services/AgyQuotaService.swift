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

    private static let persistedQuotaKey = "agy.lastKnownSubscriptionQuota"
    private static let persistedQuotasByEmailKey = "agy.persistedQuotasByEmail"
    private static let peakGoogleOneAiCreditsKey = "agy.peakGoogleOneAiCreditsByEmail"
    private static var _lastKnownSubscriptionQuota: AgyQuotaInfo? = {
        if let data = UserDefaults.standard.data(forKey: persistedQuotaKey),
           let decoded = try? JSONDecoder().decode(AgyQuotaInfo.self, from: data) {
            return decoded
        }
        return nil
    }()
    private static var _persistedQuotasByEmail: [String: AgyQuotaInfo] = {
        if let data = UserDefaults.standard.data(forKey: persistedQuotasByEmailKey),
           let decoded = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: data) {
            return decoded
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

    private static var lastActivePort: Int? = nil
    private static var cachedQuota: CachedQuota? = nil
    private static var cachedDetectedPorts: CachedPorts? = nil
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

    private static func loadPersistedQuotaUnlocked(
        expectedEmail: String? = nil,
        now: Date = Date()
    ) -> AgyQuotaInfo? {
        if let data = UserDefaults.standard.data(forKey: persistedQuotaKey),
           let decoded = try? JSONDecoder().decode(AgyQuotaInfo.self, from: data) {
            _lastKnownSubscriptionQuota = decoded
        }
        if let dictData = UserDefaults.standard.data(forKey: persistedQuotasByEmailKey),
           let decodedDict = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: dictData) {
            _persistedQuotasByEmail = decodedDict
        }

        if let targetEmail = normalizeEmailKey(expectedEmail) {
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
        if userDefaults === UserDefaults.standard {
            quotaLock.lock()
            defer { quotaLock.unlock() }
            return loadPersistedQuotaUnlocked(expectedEmail: expectedEmail, now: now)
        }

        var dict: [String: AgyQuotaInfo] = [:]
        if let dictData = userDefaults.data(forKey: persistedQuotasByEmailKey),
           let decodedDict = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: dictData) {
            dict = decodedDict
        }
        var lastKnown: AgyQuotaInfo? = nil
        if let data = userDefaults.data(forKey: persistedQuotaKey),
           let decoded = try? JSONDecoder().decode(AgyQuotaInfo.self, from: data) {
            lastKnown = decoded
        }

        if let targetEmail = normalizeEmailKey(expectedEmail) {
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
        for (key, value) in raw {
            if let intVal = value as? Int {
                result[key] = intVal
            } else if let numVal = value as? NSNumber {
                result[key] = numVal.intValue
            }
        }
        return result
    }

    private static func updatePeakGoogleOneAiCredits(
        emailKey: String,
        credits: Int,
        userDefaults: UserDefaults
    ) {
        var peaks = loadPeakGoogleOneAiCreditsDict(from: userDefaults)
        let existing = peaks[emailKey]
        let newPeak = existing.map { max($0, credits) } ?? credits
        if existing != newPeak {
            peaks[emailKey] = newPeak
            userDefaults.set(peaks, forKey: peakGoogleOneAiCreditsKey)
        }
    }

    public static func peakGoogleOneAiCredits(
        forEmail: String,
        userDefaults: UserDefaults = .standard
    ) -> Int? {
        guard let emailKey = normalizeEmailKey(forEmail) else { return nil }
        if userDefaults === UserDefaults.standard {
            quotaLock.lock()
            defer { quotaLock.unlock() }
            return loadPeakGoogleOneAiCreditsDict(from: userDefaults)[emailKey]
        }
        return loadPeakGoogleOneAiCreditsDict(from: userDefaults)[emailKey]
    }

    public static func allPersistedQuotas(
        now: Date = Date(),
        userDefaults: UserDefaults = .standard
    ) -> [String: AgyQuotaInfo] {
        if userDefaults === UserDefaults.standard {
            quotaLock.lock()
            if let dictData = UserDefaults.standard.data(forKey: persistedQuotasByEmailKey),
               let decodedDict = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: dictData) {
                _persistedQuotasByEmail = decodedDict
            }
            let snapshot = _persistedQuotasByEmail
            quotaLock.unlock()
            return snapshot.mapValues { $0.normalizedForCurrentTime(now: now) }
        }

        guard let dictData = userDefaults.data(forKey: persistedQuotasByEmailKey),
              let decodedDict = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: dictData) else {
            return [:]
        }
        return decodedDict.mapValues { $0.normalizedForCurrentTime(now: now) }
    }

    public static func saveQuotaSnapshotForAccount(_ info: AgyQuotaInfo, userDefaults: UserDefaults = .standard) {
        guard let emailKey = normalizeEmailKey(info.email) else { return }
        if userDefaults === UserDefaults.standard {
            quotaLock.lock()
            _persistedQuotasByEmail[emailKey] = info
            let dictSnapshot = _persistedQuotasByEmail
            if let credits = info.googleOneAiCredits {
                updatePeakGoogleOneAiCredits(emailKey: emailKey, credits: credits, userDefaults: userDefaults)
            }
            quotaLock.unlock()

            if let dictData = try? JSONEncoder().encode(dictSnapshot) {
                userDefaults.set(dictData, forKey: persistedQuotasByEmailKey)
            }
            return
        }

        var dict: [String: AgyQuotaInfo] = [:]
        if let dictData = userDefaults.data(forKey: persistedQuotasByEmailKey),
           let decodedDict = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: dictData) {
            dict = decodedDict
        }
        dict[emailKey] = info
        if let credits = info.googleOneAiCredits {
            updatePeakGoogleOneAiCredits(emailKey: emailKey, credits: credits, userDefaults: userDefaults)
        }
        if let dictData = try? JSONEncoder().encode(dict) {
            userDefaults.set(dictData, forKey: persistedQuotasByEmailKey)
        }
    }

    public static func savePersistedQuota(_ info: AgyQuotaInfo, userDefaults: UserDefaults = .standard) {
        if userDefaults === UserDefaults.standard {
            quotaLock.lock()
            _lastKnownSubscriptionQuota = info
            if let emailKey = normalizeEmailKey(info.email) {
                _persistedQuotasByEmail[emailKey] = info
                if let credits = info.googleOneAiCredits {
                    updatePeakGoogleOneAiCredits(emailKey: emailKey, credits: credits, userDefaults: userDefaults)
                }
            }
            let dictSnapshot = _persistedQuotasByEmail
            quotaLock.unlock()

            if let data = try? JSONEncoder().encode(info) {
                userDefaults.set(data, forKey: persistedQuotaKey)
            }
            if let dictData = try? JSONEncoder().encode(dictSnapshot) {
                userDefaults.set(dictData, forKey: persistedQuotasByEmailKey)
            }
            return
        }

        var dict: [String: AgyQuotaInfo] = [:]
        if let dictData = userDefaults.data(forKey: persistedQuotasByEmailKey),
           let decodedDict = try? JSONDecoder().decode([String: AgyQuotaInfo].self, from: dictData) {
            dict = decodedDict
        }
        if let emailKey = normalizeEmailKey(info.email) {
            dict[emailKey] = info
            if let credits = info.googleOneAiCredits {
                updatePeakGoogleOneAiCredits(emailKey: emailKey, credits: credits, userDefaults: userDefaults)
            }
        }
        if let data = try? JSONEncoder().encode(info) {
            userDefaults.set(data, forKey: persistedQuotaKey)
        }
        if let dictData = try? JSONEncoder().encode(dict) {
            userDefaults.set(dictData, forKey: persistedQuotasByEmailKey)
        }
    }

    public static func clearCache(clearActivePort: Bool = false) {
        quotaLock.lock()
        cachedQuota = nil
        cachedDetectedPorts = nil
        if clearActivePort {
            lastActivePort = nil
        }
        quotaLock.unlock()
    }

    public static func fetchQuota(forceRefresh: Bool = false, expectedEmail: String? = nil) async -> AgyQuotaInfo? {
        let resolvedExpectedEmail = expectedEmail ?? AgyStatsService.resolveActiveConsumerEmail()
        let targetEmail = normalizeEmailKey(resolvedExpectedEmail)

        if !forceRefresh {
            quotaLock.lock()
            if let cached = cachedQuota {
                let ttl = cached.info != nil ? cacheTTL : nilCacheTTL
                let emailMatches = targetEmail == nil || normalizeEmailKey(cached.info?.email) == targetEmail
                if emailMatches && Date().timeIntervalSince(cached.timestamp) < ttl {
                    let info = cached.info?.normalizedForCurrentTime()
                    quotaLock.unlock()
                    return info
                }
            }
            quotaLock.unlock()
        }

        return await Task.detached(priority: .userInitiated) {
            // Try last active port first if available
            quotaLock.lock()
            let knownPort = lastActivePort
            quotaLock.unlock()

            var invalidatedStalePort = false
            if let port = knownPort {
                if let info = await fetchFromPort(port), !info.groups.isEmpty {
                    if targetEmail == nil || normalizeEmailKey(info.email) == targetEmail {
                        savePersistedQuota(info)
                        quotaLock.lock()
                        cachedQuota = CachedQuota(info: info, timestamp: Date())
                        quotaLock.unlock()
                        return info
                    } else {
                        invalidatedStalePort = true
                        quotaLock.lock()
                        if lastActivePort == port {
                            lastActivePort = nil
                        }
                        quotaLock.unlock()
                    }
                }
            }

            let detectedPorts = detectAgyPorts(forceRefresh: forceRefresh || invalidatedStalePort)
            let portsToProbe = invalidatedStalePort ? detectedPorts : detectedPorts.filter { $0 != knownPort }

            let fallbackClosure: () -> AgyQuotaInfo? = {
                if let targetEmail {
                    return loadPersistedQuotaUnlocked(expectedEmail: targetEmail)?.normalizedForCurrentTime()
                        ?? AgyQuotaInfo(email: resolvedExpectedEmail, plan: nil, groups: [])
                }
                return (cachedQuota?.info ?? _lastKnownSubscriptionQuota ?? loadPersistedQuotaUnlocked())?.normalizedForCurrentTime()
            }

            guard !portsToProbe.isEmpty else {
                quotaLock.lock()
                lastActivePort = nil
                let fallback = fallbackClosure()
                cachedQuota = CachedQuota(info: fallback, timestamp: Date())
                quotaLock.unlock()
                return fallback
            }

            // Probe detected ports in parallel, prioritizing expectedEmail when set
            let found = await probePorts(portsToProbe, expectedEmail: resolvedExpectedEmail) { port in
                await fetchFromPort(port)
            }

            quotaLock.lock()
            if let (port, info) = found {
                lastActivePort = port
                cachedQuota = CachedQuota(info: info, timestamp: Date())
                quotaLock.unlock()
                savePersistedQuota(info)
                return info
            } else {
                lastActivePort = nil
                let fallback = fallbackClosure()
                cachedQuota = CachedQuota(info: fallback, timestamp: Date())
                quotaLock.unlock()
                return fallback
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

            let info = AgyQuotaInfo(
                email: email,
                plan: plan,
                groups: groups,
                googleOneAiCredits: googleOneAiCredits,
                minimumCreditAmountForUsage: minimumCreditAmountForUsage,
                lastUpdated: now
            )
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
