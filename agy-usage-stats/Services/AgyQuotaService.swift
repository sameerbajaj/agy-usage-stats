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
    
    public static func fetchQuota() async -> AgyQuotaInfo? {
        return await Task.detached(priority: .userInitiated) {
            let ports = detectAgyPorts()
            for port in ports {
                if let info = await fetchFromPort(port) {
                    return info
                }
            }
            return nil
        }.value
    }
    
    private static func detectAgyPorts() -> [Int] {
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
            
            // Check if it's agy CLI or language server
            if command.contains("agy") || command.contains("language_server") || command.contains("language-server") {
                pids.append(pid)
            }
        }
        
        let lsofPath = ["/usr/sbin/lsof", "/usr/bin/lsof"].first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) ?? "/usr/sbin/lsof"
        
        var ports: Set<Int> = []
        for pid in pids {
            guard let lsofOutput = runCommand(executable: lsofPath, arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(pid)]) else {
                continue
            }
            let pList = parseListeningPorts(lsofOutput)
            for port in pList {
                ports.insert(port)
            }
        }
        
        return Array(ports).sorted()
    }
    
    private static func parseListeningPorts(_ output: String) -> [Int] {
        guard let regex = try? NSRegularExpression(pattern: #":(\d+)\s+\(LISTEN\)"#) else { return [] }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        var ports: Set<Int> = []
        regex.enumerateMatches(in: output, options: [], range: range) { match, _, _ in
            guard let match,
                  let range = Range(match.range(at: 1), in: output),
                  let value = Int(output[range]) else { return }
            ports.insert(value)
        }
        return ports.sorted()
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
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
    
    private static func fetchFromPort(_ port: Int) async -> AgyQuotaInfo? {
        let urlSession = makeLocalhostSession()
        defer { urlSession.invalidateAndCancel() }
        
        // 1. Fetch RetrieveUserQuotaSummary
        guard let summaryUrl = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else {
            return nil
        }
        
        var summaryRequest = URLRequest(url: summaryUrl)
        summaryRequest.httpMethod = "POST"
        summaryRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        summaryRequest.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        summaryRequest.httpBody = try? JSONSerialization.data(withJSONObject: ["forceRefresh": true], options: [])
        
        // 2. Fetch GetUserStatus for profile details
        guard let statusUrl = URL(string: "https://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus") else {
            return nil
        }
        
        var statusRequest = URLRequest(url: statusUrl)
        statusRequest.httpMethod = "POST"
        statusRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        statusRequest.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        statusRequest.httpBody = try? JSONSerialization.data(withJSONObject: [:], options: [])
        
        do {
            let (summaryData, _) = try await urlSession.data(for: summaryRequest)
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
            
            if let (statusData, _) = try? await urlSession.data(for: statusRequest),
               let statusResp = try? decoder.decode(UserStatusResponse.self, from: statusData) {
                email = statusResp.userStatus?.email
                plan = statusResp.userStatus?.userTier?.name
            }
            
            return AgyQuotaInfo(email: email, plan: plan, groups: groups)
        } catch {
            return nil
        }
    }
    
    private static func makeLocalhostSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 2.0
        config.timeoutIntervalForResource = 2.0
        let delegate = LocalhostSessionDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
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
