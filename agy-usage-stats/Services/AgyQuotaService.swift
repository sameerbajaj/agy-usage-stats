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
    
    private static var lastActivePort: Int? = nil
    private static var cachedQuota: CachedQuota? = nil
    private static let cacheTTL: TimeInterval = 30.0
    private static let nilCacheTTL: TimeInterval = 15.0
    private static let quotaLock = NSLock()
    
    private static let sharedLocalhostSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 0.5
        config.timeoutIntervalForResource = 0.5
        config.httpShouldUsePipelining = true
        let delegate = LocalhostSessionDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    
    public static func clearCache(clearActivePort: Bool = false) {
        quotaLock.lock()
        cachedQuota = nil
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
                    let info = cached.info
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
                if let info = await fetchFromPort(port) {
                    quotaLock.lock()
                    cachedQuota = CachedQuota(info: info, timestamp: Date())
                    quotaLock.unlock()
                    return info
                }
            }
            
            let detectedPorts = detectAgyPorts()
            let portsToProbe = detectedPorts.filter { $0 != knownPort }
            guard !portsToProbe.isEmpty else {
                quotaLock.lock()
                cachedQuota = CachedQuota(info: nil, timestamp: Date())
                quotaLock.unlock()
                return nil
            }
            
            // Probe detected ports in parallel to prevent sequential timeout stacking
            let found: (Int, AgyQuotaInfo)? = await withTaskGroup(of: (Int, AgyQuotaInfo?).self) { group in
                for port in portsToProbe {
                    group.addTask {
                        let info = await fetchFromPort(port)
                        return (port, info)
                    }
                }
                for await (port, info) in group {
                    if let info = info {
                        group.cancelAll()
                        return (port, info)
                    }
                }
                return nil
            }
            
            quotaLock.lock()
            if let (port, info) = found {
                lastActivePort = port
                cachedQuota = CachedQuota(info: info, timestamp: Date())
                quotaLock.unlock()
                return info
            } else {
                cachedQuota = CachedQuota(info: nil, timestamp: Date())
                quotaLock.unlock()
                return nil
            }
        }.value
    }
    
    private static func detectAgyPorts() -> [Int] {
        let lsofPath = ["/usr/sbin/lsof", "/usr/bin/lsof"].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) ?? "/usr/sbin/lsof"
        
        // Fast path: Ask lsof directly for listening sockets owned by 'agy' process
        if let directOutput = runCommand(executable: lsofPath, arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-c", "agy", "-a"]),
           !directOutput.isEmpty {
            let ports = parseListeningPorts(directOutput)
            if !ports.isEmpty {
                return ports
            }
        }
        
        // Fallback: Query via ps if -c agy didn't match
        guard let psOutput = runCommand(executable: "/bin/ps", arguments: ["-ax", "-o", "pid=,command="]) else {
            return []
        }
        
        let lines = psOutput.components(separatedBy: .newlines)
        var pids: [Int] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int(parts[0]) else { continue }
            let command = String(parts[1]).lowercased()
            
            // Check if it's agy CLI or language server (exclude tmux and stats app)
            if (command.contains("agy") || command.contains("language_server") || command.contains("language-server")) &&
               !command.contains("agy-usage-stats") && !command.contains("tmux") {
                pids.append(pid)
            }
        }
        
        guard !pids.isEmpty else { return [] }
        pids.sort(by: >)
        
        let pidArg = pids.prefix(25).map(String.init).joined(separator: ",")
        guard let lsofOutput = runCommand(executable: lsofPath, arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", pidArg]) else {
            return []
        }
        
        return parseListeningPorts(lsofOutput)
    }
    
    private static func parseListeningPorts(_ output: String) -> [Int] {
        // Line-based parsing: prioritize FD 10u lines (the Connect protocol HTTPS port on agy)
        let lines = output.components(separatedBy: .newlines)
        var primaryPorts: [Int] = []
        var secondaryPorts: [Int] = []
        var seen = Set<Int>()
        
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return [] }
        
        for line in lines {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  let portRange = Range(match.range(at: 1), in: line),
                  let port = Int(line[portRange]),
                  !seen.contains(port) else { continue }
            
            seen.insert(port)
            if line.contains("10u") {
                primaryPorts.append(port)
            } else {
                secondaryPorts.append(port)
            }
        }
        
        // Return 10u ports first, followed by others
        return primaryPorts + secondaryPorts
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
    
    private static func fetchFromPort(_ port: Int) async -> AgyQuotaInfo? {
        // 1. Prepare RetrieveUserQuotaSummary
        guard let summaryUrl = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary"),
              let statusUrl = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else {
            return nil
        }
        
        var summaryRequest = URLRequest(url: summaryUrl)
        summaryRequest.httpMethod = "POST"
        summaryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        summaryRequest.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        summaryRequest.httpBody = try? JSONSerialization.data(withJSONObject: ["forceRefresh": true], options: [])
        
        var statusRequest = URLRequest(url: statusUrl)
        statusRequest.httpMethod = "POST"
        statusRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        statusRequest.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
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
            
            guard !groups.isEmpty else { return nil }
            
            var email: String? = nil
            var plan: String? = nil
            
            if let (statusData, _) = try? await statusTask,
               let statusResp = try? decoder.decode(UserStatusResponse.self, from: statusData) {
                email = statusResp.userStatus?.email
                plan = statusResp.userStatus?.userTier?.name
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
