//
//  MuseQuotaService.swift
//  agy-usage-stats
//
//  Fetches live weekly usage, exact reset timestamp, and additional token balances
//  from Meta's Muse (https://muse.ai) via its Next.js fetchSubscriptionAction server action,
//  with automatic Next-Action ID rediscovery on redeploys and automatic browser session cookie
//  resolution via `agentcookie` (plus optional manual Cookie header override).
//

import Foundation

nonisolated public enum MuseQuotaService {
    public struct FetchResult: Equatable, Sendable {
        public let quota: MuseQuotaInfo?
        public let status: MuseFetchStatus

        public init(quota: MuseQuotaInfo?, status: MuseFetchStatus) {
            self.quota = quota
            self.status = status
        }
    }

    private struct CachedFetch {
        let result: FetchResult
        let timestamp: Date
    }

    private struct CachedCookie {
        let header: String
        let timestamp: Date
    }

    private final class NoAuthRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            // Never follow redirects to auth.muse.ai so we cleanly detect expired sessions.
            completionHandler(nil)
        }
    }

    private static let origin = "https://muse.ai"
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
    private static let defaultSeedActionID = "406cd44441421b58cea8309747129141947de9f499"

    private static let actionIDDefaultsKey = "agy_museActionId"
    private static let persistedQuotaDefaultsKey = "agy_lastKnownMuseQuota"

    private static let fetchCacheTTL: TimeInterval = 60.0
    private static let autoCookieCacheTTL: TimeInterval = 1800.0 // 30 minutes

    private static let lock = NSLock()
    private static var cachedFetch: CachedFetch? = nil
    private static var cachedAutoCookie: CachedCookie? = nil
    private static var cachedDefaultPersistedQuota: MuseQuotaInfo? = nil
    private static var hasLoadedDefaultPersistedQuota = false

    private static let redirectDelegate = NoAuthRedirectDelegate()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12.0
        config.timeoutIntervalForResource = 25.0
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        return URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
    }()

    private static let isRunningTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()

    private static let testIsolatedDefaults: UserDefaults = {
        let suite = "com.sameerbajaj.agy-usage-stats.muse-test.\(ProcessInfo.processInfo.processIdentifier)"
        let ud = UserDefaults(suiteName: suite) ?? .standard
        ud.removePersistentDomain(forName: suite)
        return ud
    }()

    public static var defaultStore: UserDefaults {
        isRunningTests ? testIsolatedDefaults : .standard
    }

    // MARK: - Persistence & Cache Helpers

    public static func clearCache(clearCookie: Bool = false) {
        lock.withLock {
            cachedFetch = nil
            if clearCookie {
                cachedAutoCookie = nil
            }
        }
    }

    public static func savePersistedQuota(_ info: MuseQuotaInfo, userDefaults: UserDefaults = defaultStore) {
        if userDefaults === defaultStore {
            lock.withLock {
                cachedDefaultPersistedQuota = info
                hasLoadedDefaultPersistedQuota = true
            }
        }
        if let data = try? JSONEncoder().encode(info) {
            userDefaults.set(data, forKey: persistedQuotaDefaultsKey)
        }
    }

    public static func loadPersistedQuota(userDefaults: UserDefaults = defaultStore, now: Date = Date()) -> MuseQuotaInfo? {
        if userDefaults === defaultStore {
            let cached: (loaded: Bool, quota: MuseQuotaInfo?) = lock.withLock {
                (hasLoadedDefaultPersistedQuota, cachedDefaultPersistedQuota)
            }
            if cached.loaded {
                return cached.quota?.normalizedForCurrentTime(now: now)
            }
            let decoded = userDefaults.data(forKey: persistedQuotaDefaultsKey)
                .flatMap { try? JSONDecoder().decode(MuseQuotaInfo.self, from: $0) }
            lock.withLock {
                cachedDefaultPersistedQuota = decoded
                hasLoadedDefaultPersistedQuota = true
            }
            return decoded?.normalizedForCurrentTime(now: now)
        }
        guard let data = userDefaults.data(forKey: persistedQuotaDefaultsKey),
              let decoded = try? JSONDecoder().decode(MuseQuotaInfo.self, from: data) else {
            return nil
        }
        return decoded.normalizedForCurrentTime(now: now)
    }

    public static func saveActionID(_ id: String?, userDefaults: UserDefaults = defaultStore) {
        if let id, !id.isEmpty {
            userDefaults.set(id, forKey: actionIDDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: actionIDDefaultsKey)
        }
    }

    public static func loadActionID(userDefaults: UserDefaults = defaultStore) -> String? {
        guard let raw = userDefaults.string(forKey: actionIDDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    public static func normalizeManualCookieHeader(_ raw: String?) -> String? {
        guard var trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.lowercased().hasPrefix("cookie:") {
            trimmed = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Live Fetch Pipeline

    public static func fetchUsage(
        forceRefresh: Bool = false,
        manualCookieHeader: String? = nil,
        userDefaults: UserDefaults = defaultStore
    ) async -> FetchResult {
        let now = Date()
        if !forceRefresh {
            let cached = lock.withLock { () -> FetchResult? in
                guard let entry = cachedFetch, now.timeIntervalSince(entry.timestamp) < fetchCacheTTL else {
                    return nil
                }
                return entry.result
            }
            if let cached {
                if let q = cached.quota {
                    return FetchResult(quota: q.normalizedForCurrentTime(now: now), status: cached.status)
                }
                return cached
            }
        }

        let persistedFallback = loadPersistedQuota(userDefaults: userDefaults, now: now)
        let normalizedManual = normalizeManualCookieHeader(manualCookieHeader)
        let usingManualCookie = normalizedManual != nil

        guard var cookieHeader = await resolveCookieHeader(
            manualHeader: normalizedManual,
            forceRefresh: forceRefresh && !usingManualCookie
        ) else {
            let res = FetchResult(
                quota: persistedFallback,
                status: .missingSession("No muse.ai browser session found. Sign in at muse.ai in Brave (or paste a Cookie header in Settings).")
            )
            cacheResult(res, at: now)
            return res
        }

        var attempt = 0
        while attempt < 2 {
            attempt += 1
            let outcome = await executeSubscriptionFetch(cookie: cookieHeader, userDefaults: userDefaults, now: now)
            switch outcome {
            case .success(let quota):
                savePersistedQuota(quota, userDefaults: userDefaults)
                let res = FetchResult(quota: quota, status: .connected)
                cacheResult(res, at: Date())
                return res

            case .signedOut:
                if !usingManualCookie && attempt == 1 {
                    // Re-sync fresh cookies from Brave via agentcookie once before reporting expired.
                    lock.withLock { cachedAutoCookie = nil }
                    if let refreshed = await resolveCookieHeader(manualHeader: nil, forceRefresh: true),
                       refreshed != cookieHeader {
                        cookieHeader = refreshed
                        continue
                    }
                }
                let res = FetchResult(
                    quota: persistedFallback,
                    status: .sessionExpired("Muse session expired. Sign in at muse.ai in Brave and refresh.")
                )
                cacheResult(res, at: Date())
                return res

            case .failure(let message):
                let res = FetchResult(quota: persistedFallback, status: .error(message))
                cacheResult(res, at: Date())
                return res
            }
        }

        let res = FetchResult(
            quota: persistedFallback,
            status: .sessionExpired("Muse session expired. Sign in at muse.ai in Brave and refresh.")
        )
        cacheResult(res, at: Date())
        return res
    }

    private enum InternalOutcome {
        case success(MuseQuotaInfo)
        case signedOut
        case failure(String)
    }

    private static func executeSubscriptionFetch(
        cookie: String,
        userDefaults: UserDefaults,
        now: Date
    ) async -> InternalOutcome {
        let initialActionID = loadActionID(userDefaults: userDefaults) ?? defaultSeedActionID

        if let initialResp = await postSubscriptionAction(cookie: cookie, actionID: initialActionID) {
            if isSignedOut(initialResp) {
                return .signedOut
            }
            if initialResp.status == 200 {
                if let parsed = parseFlightResponse(initialResp.body, now: now) {
                    saveActionID(initialActionID, userDefaults: userDefaults)
                    return .success(parsed)
                }
                return .failure("Unexpected muse.ai response format.")
            }
            if !needsActionRediscovery(initialResp) {
                return .failure("muse.ai returned HTTP \(initialResp.status).")
            }
        }

        // Stale Next-Action ID after a muse.ai redeploy: rediscover from Next.js chunks.
        saveActionID(nil, userDefaults: userDefaults)
        guard let discovery = await discoverActionID(cookie: cookie) else {
            return .failure("Could not find muse.ai subscription action. muse.ai may have updated — retry in a moment.")
        }
        switch discovery {
        case .signedOut:
            return .signedOut
        case .error(let msg):
            return .failure(msg)
        case .actionID(let freshActionID):
            guard let freshResp = await postSubscriptionAction(cookie: cookie, actionID: freshActionID) else {
                return .failure("Network request to muse.ai failed.")
            }
            if isSignedOut(freshResp) {
                return .signedOut
            }
            guard freshResp.status == 200 else {
                return .failure("muse.ai returned HTTP \(freshResp.status) after action rediscovery.")
            }
            guard let parsed = parseFlightResponse(freshResp.body, now: now) else {
                return .failure("Unexpected muse.ai response format.")
            }
            saveActionID(freshActionID, userDefaults: userDefaults)
            return .success(parsed)
        }
    }

    private static func cacheResult(_ result: FetchResult, at date: Date) {
        lock.withLock {
            cachedFetch = CachedFetch(result: result, timestamp: date)
        }
    }

    // MARK: - HTTP & Next.js Action Discovery

    private struct HTTPResult {
        let status: Int
        let location: String?
        let body: String
    }

    private static func isSignedOut(_ r: HTTPResult) -> Bool {
        if r.status == 401 || r.status == 403 {
            return true
        }
        if let loc = r.location?.lowercased(), loc.hasPrefix("https://auth.muse.ai/") {
            return true
        }
        return false
    }

    private static func needsActionRediscovery(_ r: HTTPResult) -> Bool {
        !isSignedOut(r) && (r.status == 400 || r.status == 404 || r.status == 409)
    }

    private static func postSubscriptionAction(cookie: String, actionID: String) async -> HTTPResult? {
        guard let url = URL(string: "\(origin)/") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data("[{\"includeAgreement\":true}]".utf8)
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue("text/x-component", forHTTPHeaderField: "Accept")
        req.setValue(actionID, forHTTPHeaderField: "Next-Action")
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            let location = http.value(forHTTPHeaderField: "Location")
            let body = String(data: data, encoding: .utf8) ?? ""
            return HTTPResult(status: http.statusCode, location: location, body: body)
        } catch {
            return nil
        }
    }

    private static func getURL(_ urlString: String, cookie: String?, accept: String) async -> HTTPResult? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if let cookie {
            req.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            let location = http.value(forHTTPHeaderField: "Location")
            let body = String(data: data, encoding: .utf8) ?? ""
            return HTTPResult(status: http.statusCode, location: location, body: body)
        } catch {
            return nil
        }
    }

    private enum DiscoveryResult {
        case actionID(String)
        case signedOut
        case error(String)
    }

    private static func discoverActionID(cookie: String) async -> DiscoveryResult? {
        guard let page = await getURL("\(origin)/", cookie: cookie, accept: "text/html") else {
            return .error("Could not reach muse.ai.")
        }
        if isSignedOut(page) {
            return .signedOut
        }
        guard page.status == 200 else {
            return .error("muse.ai returned HTTP \(page.status).")
        }

        let paths = Array(extractChunkPaths(from: page.body).prefix(96))
        var combined = ""
        let batchSize = 8
        var idx = 0
        while idx < paths.count {
            let end = min(paths.count, idx + batchSize)
            let batch = Array(paths[idx..<end])
            idx = end

            let bodies = await fetchChunksConcurrently(paths: batch)
            for body in bodies where !body.isEmpty {
                if let direct = extractActionID(from: body) {
                    return .actionID(direct)
                }
                combined.append("\n")
                combined.append(body)
            }
            if combined.utf8.count > 8 * 1024 * 1024 {
                return nil
            }

            if let moduleId = extractSettingsLoaderModuleID(from: combined) {
                let settingsPaths = Array(extractSettingsLoaderChunkList(moduleId: moduleId, from: combined).prefix(32))
                if !settingsPaths.isEmpty {
                    var sIdx = 0
                    while sIdx < settingsPaths.count {
                        let sEnd = min(settingsPaths.count, sIdx + batchSize)
                        let sBatch = Array(settingsPaths[sIdx..<sEnd])
                        sIdx = sEnd
                        let sBodies = await fetchChunksConcurrently(paths: sBatch)
                        for sBody in sBodies {
                            if let id = extractActionID(from: sBody) {
                                return .actionID(id)
                            }
                        }
                    }
                    break
                }
            }
        }
        return nil
    }

    private static func fetchChunksConcurrently(paths: [String]) async -> [String] {
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, path) in paths.enumerated() {
                group.addTask {
                    // Static chunks receive no session cookies.
                    let resp = await getURL("\(origin)\(path)", cookie: nil, accept: "*/*")
                    return (index, resp?.status == 200 ? (resp?.body ?? "") : "")
                }
            }
            var ordered = Array(repeating: "", count: paths.count)
            for await (index, body) in group {
                ordered[index] = body
            }
            return ordered
        }
    }

    // MARK: - Pure Regex & Flight Parsers (Unit-Tested)

    public static func extractChunkPaths(from text: String) -> [String] {
        let pattern = #"static/(?:immutable/)?chunks/[\w~.-]+\.js"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var seen: Set<String> = []
        var result: [String] = []
        for match in matches {
            let sub = nsText.substring(with: match.range)
            let path = "/_next/\(sub)"
            if seen.insert(path).inserted {
                result.append(path)
            }
        }
        return result
    }

    public static func extractActionID(from jsText: String) -> String? {
        let pattern = #""([0-9a-f]{40,})",[^"]{0,200}"fetchSubscriptionAction""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = jsText as NSString
        guard let match = regex.firstMatch(in: jsText, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }

    public static func extractSettingsLoaderModuleID(from jsText: String) -> String? {
        let pattern = #"\.A\((\d+)\)\.then\(\(\{[^}]*Settings"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = jsText as NSString
        guard let match = regex.firstMatch(in: jsText, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
    }

    public static func extractSettingsLoaderChunkList(moduleId: String, from jsText: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: moduleId)
        let pattern = #"[,{\[]\#(escaped),\w+=>\{\w+\.v\(\w+=>Promise\.all\(\[([^\]]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = jsText as NSString
        guard let match = regex.firstMatch(in: jsText, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1 else {
            return []
        }
        let arrayContents = nsText.substring(with: match.range(at: 1))
        return extractChunkPaths(from: arrayContents)
    }

    public static func parseFlightResponse(_ body: String, now: Date = Date()) -> MuseQuotaInfo? {
        for rawLine in body.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIdx = line.firstIndex(of: ":") else { continue }
            let prefix = line[..<colonIdx]
            guard !prefix.isEmpty, prefix.allSatisfy({ $0.isHexDigit }) else { continue }
            let jsonStart = line.index(after: colonIdx)
            let jsonSlice = line[jsonStart...]
            guard jsonSlice.first == "{",
                  let data = jsonSlice.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["success"] as? Bool) == true,
                  let sub = obj["subscription"] as? [String: Any],
                  let usage = sub["usage"] as? [String: Any] else {
                continue
            }

            let percentUsed: Double
            if let d = usage["percentUsed"] as? Double {
                percentUsed = d
            } else if let n = usage["percentUsed"] as? NSNumber {
                percentUsed = n.doubleValue
            } else {
                continue
            }

            let tier = sub["tier"] as? [String: Any]
            let planName = (tier?["name"] as? String)
                ?? (sub["usageRowLabel"] as? String)
                ?? "Muse"
            let subscriptionType = (sub["subscriptionType"] as? String) ?? "FREE"

            let resetsAt: Date? = {
                if let secs = usage["resetsAt"] as? Double, secs > 0 {
                    return Date(timeIntervalSince1970: secs)
                }
                if let num = usage["resetsAt"] as? NSNumber, num.doubleValue > 0 {
                    return Date(timeIntervalSince1970: num.doubleValue)
                }
                return nil
            }()

            let agreement = sub["agreement"] as? [String: Any]
            let renewsAt: Date? = {
                if let secs = agreement?["currentPeriodEndTime"] as? Double, secs > 0 {
                    return Date(timeIntervalSince1970: secs)
                }
                if let num = agreement?["currentPeriodEndTime"] as? NSNumber, num.doubleValue > 0 {
                    return Date(timeIntervalSince1970: num.doubleValue)
                }
                return nil
            }()

            let topupBalance: Double? = (sub["topupBalance"] as? NSNumber)?.doubleValue
            let topupTotal: Double? = (sub["topupTotal"] as? NSNumber)?.doubleValue

            return MuseQuotaInfo(
                planName: planName,
                subscriptionType: subscriptionType,
                percentUsed: min(100.0, max(0.0, percentUsed)),
                resetsAt: resetsAt,
                statusSubtitle: sub["statusSubtitle"] as? String,
                usageRowLabel: sub["usageRowLabel"] as? String,
                usageRowValueLabel: sub["usageRowValueLabel"] as? String,
                quotaStatus: usage["quotaStatus"] as? String,
                topupRowLabel: sub["topupRowLabel"] as? String,
                topupRowValueLabel: sub["topupRowValueLabel"] as? String,
                topupBalance: topupBalance,
                topupTotal: topupTotal,
                renewsAt: renewsAt,
                lastUpdated: now
            )
        }
        return nil
    }

    // MARK: - Automatic Browser Cookie Resolution (`agentcookie`)

    private static func resolveCookieHeader(manualHeader: String?, forceRefresh: Bool) async -> String? {
        if let manualHeader, !manualHeader.isEmpty {
            return manualHeader
        }
        let now = Date()
        if !forceRefresh {
            let cached = lock.withLock { () -> String? in
                guard let entry = cachedAutoCookie, now.timeIntervalSince(entry.timestamp) < autoCookieCacheTTL else {
                    return nil
                }
                return entry.header
            }
            if let cached {
                return cached
            }
        }

        guard let executable = findAgentCookieBinary() else {
            return nil
        }
        guard let cookie = await runAgentCookieProcess(executablePath: executable) else {
            return nil
        }
        lock.withLock {
            cachedAutoCookie = CachedCookie(header: cookie, timestamp: Date())
        }
        return cookie
    }

    private static func findAgentCookieBinary() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/go/bin/agentcookie",
            "/opt/homebrew/bin/agentcookie",
            "/usr/local/bin/agentcookie",
            "\(home)/.local/bin/agentcookie",
            "/usr/bin/agentcookie"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func runAgentCookieProcess(executablePath: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executablePath)
                proc.arguments = ["cookies", "--domain", "muse.ai"]

                let outPipe = Pipe()
                let errPipe = Pipe()
                proc.standardOutput = outPipe
                proc.standardError = errPipe

                do {
                    try proc.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let watchdog = DispatchWorkItem {
                    if proc.isRunning {
                        proc.terminate()
                    }
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 15.0, execute: watchdog)

                let data = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                proc.waitUntilExit()
                watchdog.cancel()

                guard proc.terminationStatus == 0,
                      let raw = String(data: data, encoding: .utf8) else {
                    continuation.resume(returning: nil)
                    return
                }
                let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: cleaned.isEmpty ? nil : cleaned)
            }
        }
    }
}
