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

    private struct UserStatusResponse: Decodable {
        let userStatus: UserStatus?
    }

    private struct UserStatus: Decodable {
        let email: String?
        let userTier: UserTier?
    }

    private struct UserTier: Decodable {
        let name: String?
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
    private static var _lastKnownSubscriptionQuota: AgyQuotaInfo? = {
        if let data = UserDefaults.standard.data(forKey: persistedQuotaKey),
           let decoded = try? JSONDecoder().decode(AgyQuotaInfo.self, from: data) {
            return decoded
        }
        return nil
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

    private static func loadPersistedQuotaUnlocked(now: Date = Date()) -> AgyQuotaInfo? {
        if let data = UserDefaults.standard.data(forKey: persistedQuotaKey),
           let decoded = try? JSONDecoder().decode(AgyQuotaInfo.self, from: data) {
            _lastKnownSubscriptionQuota = decoded
            return decoded.normalizedForCurrentTime(now: now)
        }
        return _lastKnownSubscriptionQuota?.normalizedForCurrentTime(now: now)
    }

    public static func loadPersistedQuota(now: Date = Date()) -> AgyQuotaInfo? {
        quotaLock.lock()
        defer { quotaLock.unlock() }
        return loadPersistedQuotaUnlocked(now: now)
    }

    public static func savePersistedQuota(_ info: AgyQuotaInfo) {
        quotaLock.lock()
        _lastKnownSubscriptionQuota = info
        quotaLock.unlock()
        if let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: persistedQuotaKey)
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

    public static func fetchQuota(forceRefresh: Bool = false) async -> AgyQuotaInfo? {
        if !forceRefresh {
            quotaLock.lock()
            if let cached = cachedQuota {
                let ttl = cached.info != nil ? cacheTTL : nilCacheTTL
                if Date().timeIntervalSince(cached.timestamp) < ttl {
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

            if let port = knownPort {
                if let info = await fetchFromPort(port), !info.groups.isEmpty {
                    savePersistedQuota(info)
                    quotaLock.lock()
                    cachedQuota = CachedQuota(info: info, timestamp: Date())
                    quotaLock.unlock()
                    return info
                }
            }

            let detectedPorts = detectAgyPorts(forceRefresh: forceRefresh)
            let portsToProbe = detectedPorts.filter { $0 != knownPort }
            guard !portsToProbe.isEmpty else {
                quotaLock.lock()
                lastActivePort = nil
                let fallback = (cachedQuota?.info ?? _lastKnownSubscriptionQuota ?? loadPersistedQuotaUnlocked())?.normalizedForCurrentTime()
                cachedQuota = CachedQuota(info: fallback, timestamp: Date())
                quotaLock.unlock()
                return fallback
            }

            // Probe detected ports in parallel until a group-bearing result arrives
            let found = await probePorts(portsToProbe) { port in
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
                let fallback = (cachedQuota?.info ?? _lastKnownSubscriptionQuota ?? loadPersistedQuotaUnlocked())?.normalizedForCurrentTime()
                cachedQuota = CachedQuota(info: fallback, timestamp: Date())
                quotaLock.unlock()
                return fallback
            }
        }.value
    }

    public static func probePorts(
        _ ports: [Int],
        fetcher: @escaping @Sendable (Int) async -> AgyQuotaInfo?
    ) async -> (Int, AgyQuotaInfo)? {
        await withTaskGroup(of: (Int, AgyQuotaInfo?).self) { group in
            for port in ports {
                group.addTask {
                    let info = await fetcher(port)
                    return (port, info)
                }
            }
            for await (port, info) in group {
                if let info = info, !info.groups.isEmpty {
                    group.cancelAll()
                    return (port, info)
                }
            }
            return nil
        }
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

        // Run at most ONE batched ps call to filter out .agy-gcp-home and extract CSRF tokens
        let pidArg = candidatePids.prefix(50).map(String.init).joined(separator: ",")
        var gcpPids = Set<Int>()
        var pidToCsrf: [Int: String] = [:]

        if let psOutput = runCommand(executable: "/bin/ps", arguments: ["-E", "-o", "pid=,command=", "-p", pidArg]) ??
                          runCommand(executable: "/bin/ps", arguments: ["-o", "pid=,command=", "-p", pidArg]) {
            let csrfRegex = try? NSRegularExpression(pattern: #"--csrf_token=([^\s]+)"#)
            let envCsrfRegex = try? NSRegularExpression(pattern: #"ANTIGRAVITY_CSRF_TOKEN=([^\s]+)"#)

            for psLine in psOutput.components(separatedBy: .newlines) {
                let trimmed = psLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2, let pid = Int(parts[0]) else { continue }
                let cmdAndEnv = String(parts[1])

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

        var primaryPorts: [Int] = []
        var secondaryPorts: [Int] = []
        var seenPorts = Set<Int>()
        var portToCsrf: [Int: String] = [:]

        for item in discovered {
            if gcpPids.contains(item.pid) { continue }
            if seenPorts.contains(item.port) { continue }
            seenPorts.insert(item.port)

            if item.is10u {
                primaryPorts.append(item.port)
            } else {
                secondaryPorts.append(item.port)
            }

            if let token = pidToCsrf[item.pid] {
                portToCsrf[item.port] = token
            }
        }

        let ports = primaryPorts + secondaryPorts
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

            if let (statusData, _) = try? await statusTask,
               let statusResp = try? decoder.decode(UserStatusResponse.self, from: statusData) {
                email = statusResp.userStatus?.email
                plan = statusResp.userStatus?.userTier?.name
            }

            // If groups is empty, but status call succeeded (e.g. GCP direct project mode or pay-as-you-go)
            if groups.isEmpty {
                if email != nil || plan != nil {
                    return AgyQuotaInfo(email: email, plan: plan, groups: [])
                }
                return nil
            }

            return AgyQuotaInfo(email: email, plan: plan, groups: groups)
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
