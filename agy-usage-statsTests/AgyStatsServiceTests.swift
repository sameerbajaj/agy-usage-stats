//
//  AgyStatsServiceTests.swift
//  agy-usage-statsTests
//
//  Created by Antigravity on 10/22/26.
//

import Testing
import Foundation
import SQLite3
@testable import agy_usage_stats

@Suite(.serialized)
struct AgyStatsServiceTests {
    
    // MARK: - Protobuf Encoding Helpers for Test Fixtures
    
    private func encodeVarint(_ value: Int) -> Data {
        var v = value
        var data = Data()
        while true {
            let b = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 {
                data.append(b | 0x80)
            } else {
                data.append(b)
                break
            }
        }
        return data
    }
    
    private func encodeField(tag: Int, varint: Int) -> Data {
        var data = encodeVarint((tag << 3) | 0)
        data.append(encodeVarint(varint))
        return data
    }
    
    private func encodeField(tag: Int, bytes: Data) -> Data {
        var data = encodeVarint((tag << 3) | 2)
        data.append(encodeVarint(bytes.count))
        data.append(bytes)
        return data
    }
    
    private func encodeField(tag: Int, string: String) -> Data {
        return encodeField(tag: tag, bytes: Data(string.utf8))
    }
    
    private func makeStepMetadata(timestamp: Date) -> Data {
        let sub = encodeField(tag: 1, varint: Int(timestamp.timeIntervalSince1970))
        return encodeField(tag: 1, bytes: sub)
    }
    
    private func makeGenMetadata(modelName: String, inputTokens: Int, outputTokens: Int, cachedTokens: Int, stepIndex: Int) -> Data {
        var f4Data = Data()
        f4Data.append(encodeField(tag: 2, varint: inputTokens))
        f4Data.append(encodeField(tag: 3, varint: outputTokens))
        f4Data.append(encodeField(tag: 5, varint: cachedTokens))
        
        var kvData = Data()
        kvData.append(encodeField(tag: 1, string: "last_step_index"))
        kvData.append(encodeField(tag: 2, string: "\(stepIndex)"))
        
        var f1Data = Data()
        f1Data.append(encodeField(tag: 19, string: modelName))
        f1Data.append(encodeField(tag: 4, bytes: f4Data))
        f1Data.append(encodeField(tag: 20, bytes: kvData))
        
        return encodeField(tag: 1, bytes: f1Data)
    }
    
    private func insertStep(db: OpaquePointer?, idx: Int, metadata: Data) {
        var stmt: OpaquePointer?
        let query = "INSERT INTO steps (idx, metadata, step_payload) VALUES (?, ?, ?)"
        #expect(sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_int(stmt, 1, Int32(idx))
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        metadata.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, 2, rawBuffer.baseAddress, Int32(rawBuffer.count), transient)
        }
        sqlite3_bind_null(stmt, 3)
        #expect(sqlite3_step(stmt) == SQLITE_DONE)
        sqlite3_finalize(stmt)
    }
    
    private func insertGen(db: OpaquePointer?, idx: Int, data: Data, size: Int) {
        var stmt: OpaquePointer?
        let query = "INSERT INTO gen_metadata (idx, data, size) VALUES (?, ?, ?)"
        #expect(sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK)
        sqlite3_bind_int(stmt, 1, Int32(idx))
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        data.withUnsafeBytes { rawBuffer in
            sqlite3_bind_blob(stmt, 2, rawBuffer.baseAddress, Int32(rawBuffer.count), transient)
        }
        sqlite3_bind_int(stmt, 3, Int32(size))
        #expect(sqlite3_step(stmt) == SQLITE_DONE)
        sqlite3_finalize(stmt)
    }
    
    // MARK: - Unit Tests
    
    @Test func testDirectoryContentSignatureDetectsWalChanges() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sig-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let initialSig = AgyStatsService.directoryContentSignature(atPath: tempDir.path)
        #expect(initialSig.totalSize == 0)
        
        let dbFile = tempDir.appendingPathComponent("session.db")
        let walFile = tempDir.appendingPathComponent("session.db-wal")
        
        try Data([1, 2, 3, 4]).write(to: dbFile)
        let sigAfterDb = AgyStatsService.directoryContentSignature(atPath: tempDir.path)
        #expect(sigAfterDb.totalSize == 4)
        
        try Data([5, 6, 7, 8, 9]).write(to: walFile)
        let sigAfterWal = AgyStatsService.directoryContentSignature(atPath: tempDir.path)
        #expect(sigAfterWal.totalSize == 9)
        #expect(sigAfterWal != sigAfterDb)
    }
    
    @Test func testWalModeConversationDbUpdatesStatsWithoutDirectoryMtimeChange() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("wal-test-\(UUID().uuidString)")
        let convDir = tempDir.appendingPathComponent("conversations")
        try FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            AgyStatsService.clearCaches()
        }
        
        let convId = "conv-\(UUID().uuidString)"
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let timestampMs = Int64(now.timeIntervalSince1970 * 1000)
        
        // 1. Write history.jsonl and settings.json
        let historyLine = "{\"display\": \"WAL prompt\", \"timestamp\": \(timestampMs), \"workspace\": \"/tmp/ws\", \"conversationId\": \"\(convId)\"}\n"
        try historyLine.write(to: tempDir.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)
        
        let settingsJson = "{\"model\": \"Claude Sonnet 4.6 (Thinking)\"}"
        try settingsJson.write(to: tempDir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        
        let dbPath = convDir.appendingPathComponent("\(convId).db")
        
        // 2. Create SQLite DB in WAL mode
        var db: OpaquePointer?
        #expect(sqlite3_open(dbPath.path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE steps (idx INTEGER PRIMARY KEY, metadata BLOB, step_payload BLOB);", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE gen_metadata (idx INTEGER PRIMARY KEY, data BLOB, size INTEGER);", nil, nil, nil) == SQLITE_OK)
        
        // 3. Insert initial turn (Step 0 and Gen 0)
        let step0Meta = makeStepMetadata(timestamp: now)
        insertStep(db: db, idx: 0, metadata: step0Meta)
        
        let gen0Data = makeGenMetadata(
            modelName: "claude-sonnet-4-6",
            inputTokens: 1000,
            outputTokens: 500,
            cachedTokens: 0,
            stepIndex: 0
        )
        insertGen(db: db, idx: 0, data: gen0Data, size: gen0Data.count)
        
        // Checkpoint initial data to establish base file
        #expect(sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_close(db) == SQLITE_OK)
        
        // 4. Initial loadStats call: parses base DB and populates caches
        // Use an isolated empty gcpCliDir so external GCP histories on the test runner do not pollute the isolated test
        let isolatedGcpDir = tempDir.appendingPathComponent("empty_gcp").path
        AgyStatsService.clearCaches()
        let (initialStats, _) = await AgyStatsService.loadStats(cliDir: tempDir.path, gcpCliDir: isolatedGcpDir)
        #expect(initialStats.totalQueries == 1)
        #expect(initialStats.totalCostEstimate > 0)
        let initialCost = initialStats.totalCostEstimate
        let initialQuery = initialStats.recentQueries.first(where: { $0.conversationId == convId })
        #expect(initialQuery != nil)
        #expect(initialQuery?.conversationMeta?.inputTokens == 1000)
        #expect(initialQuery?.conversationMeta?.llmCalls == 1)
        
        // 5. Open writer connection in WAL mode, append new turn (Step 1 and Gen 1) to .db-wal without checkpointing
        var writerDb: OpaquePointer?
        #expect(sqlite3_open(dbPath.path, &writerDb) == SQLITE_OK)
        #expect(sqlite3_exec(writerDb, "PRAGMA journal_mode=WAL;", nil, nil, nil) == SQLITE_OK)
        
        let step1Meta = makeStepMetadata(timestamp: now.addingTimeInterval(5))
        insertStep(db: writerDb, idx: 1, metadata: step1Meta)
        
        let gen1Data = makeGenMetadata(
            modelName: "claude-sonnet-4-6",
            inputTokens: 8000,
            outputTokens: 4000,
            cachedTokens: 0,
            stepIndex: 1
        )
        insertGen(db: writerDb, idx: 1, data: gen1Data, size: gen1Data.count)
        
        // Verify .db-wal file exists and has content
        let walPath = dbPath.path + "-wal"
        #expect(FileManager.default.fileExists(atPath: walPath))
        let walSize = (try? FileManager.default.attributesOfItem(atPath: walPath)[.size] as? NSNumber)?.int64Value ?? 0
        #expect(walSize > 0)
        
        // 6. Freeze / Revert the directory modification date to a fixed past time so dir mtime does not change
        let frozenPastDate = now.addingTimeInterval(-3600)
        try FileManager.default.setAttributes([.modificationDate: frozenPastDate], ofItemAtPath: convDir.path)
        
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: convDir.path)
        let dirModDate = dirAttrs[.modificationDate] as? Date
        #expect(dirModDate == frozenPastDate)
        
        // 7. Load stats again WITHOUT clearing caches manually
        // The service must detect the .db-wal modification via directory content signature,
        // invalidate statsCache & conversationCache, and read the live WAL frames via mode=ro
        let (updatedStats, _) = await AgyStatsService.loadStats(cliDir: tempDir.path, gcpCliDir: isolatedGcpDir)
        
        // Verify the updated generation in .db-wal was read and priced
        #expect(updatedStats.totalCostEstimate > initialCost)
        let updatedQuery = updatedStats.recentQueries.first(where: { $0.conversationId == convId })
        #expect(updatedQuery != nil)
        #expect(updatedQuery?.conversationMeta?.inputTokens == 9000) // 1000 (Gen 0) + 8000 (Gen 1)
        #expect(updatedQuery?.conversationMeta?.llmCalls == 2)
        
        // Clean up open writer connection
        sqlite3_close(writerDb)
    }
    
    @Test
    func testConsumerUserPromptContainingGcpKeywordsDoesNotTriggerGcpAuthTransition() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let logDir = tempDir.appendingPathComponent("log")
        let convDir = tempDir.appendingPathComponent("conversations")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let logDateStr = dateFormatter.string(from: now)
        let logFile = logDir.appendingPathComponent("cli-\(logDateStr).log")
        
        // Log file where user prompt mentions GCP project and aiplatform, but NOT actual GCP auth setup
        let logContent = """
        I1022 09:25:24.123456    1000 input_loop.go:106] HandleUserInput called with text: "inspect clawdbot-485304 and aiplatform credentials"
        I1022 09:25:25.123456    1000 runner.go:200] Step completed
        """
        try logContent.write(to: logFile, atomically: true, encoding: .utf8)
        
        let historyFile = tempDir.appendingPathComponent("history.jsonl")
        let historyJson = """
        {"display":"inspect clawdbot-485304 and aiplatform credentials","timestamp":\(Int64(now.timeIntervalSince1970 * 1000)),"workspace":"/tmp","conversationId":"test-conv-1","type":"user"}
        """
        try historyJson.write(to: historyFile, atomically: true, encoding: .utf8)
        
        let isolatedGcpDir = tempDir.appendingPathComponent("empty_gcp").path
        AgyStatsService.clearCaches()
        let (stats, _) = await AgyStatsService.loadStats(cliDir: tempDir.path, gcpCliDir: isolatedGcpDir)
        
        // Query and cost must NOT be attributed to GCP
        #expect(stats.gcpTotalCost == 0.0)
        let q = stats.recentQueries.first(where: { $0.conversationId == "test-conv-1" })
        #expect(q != nil)
        #expect(q?.isGcp == false)
    }

    @Test
    func testGcpRegionalMultiplierAppliesOnlyToGcpBoxAcrossAllAggregations() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent("gcp-mult-test-\(UUID().uuidString)")
        let consumerDir = rootDir.appendingPathComponent("consumer")
        let consumerConvDir = consumerDir.appendingPathComponent("conversations")
        let gcpDir = rootDir.appendingPathComponent("gcp")
        let gcpConvDir = gcpDir.appendingPathComponent("conversations")
        try FileManager.default.createDirectory(at: consumerConvDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gcpConvDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootDir)
            AgyStatsService.clearCaches()
        }

        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let tsMs = Int64(now.timeIntervalSince1970 * 1000)

        // Consumer box: Gemini 4 Carbon (1M in, 1M cached, 1M out -> $24.20 at 1.0x)
        let consumerConvId = "consumer-\(UUID().uuidString)"
        let consumerHist = "{\"display\":\"consumer prompt\",\"timestamp\":\(tsMs),\"workspace\":\"/tmp/c\",\"conversationId\":\"\(consumerConvId)\"}\n"
        try consumerHist.write(to: consumerDir.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)
        try "{\"model\":\"Gemini 4 Carbon (High)\"}".write(to: consumerDir.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)

        var cDb: OpaquePointer?
        let cDbPath = consumerConvDir.appendingPathComponent("\(consumerConvId).db").path
        #expect(sqlite3_open(cDbPath, &cDb) == SQLITE_OK)
        #expect(sqlite3_exec(cDb, "CREATE TABLE steps (idx INTEGER PRIMARY KEY, metadata BLOB, step_payload BLOB);", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(cDb, "CREATE TABLE gen_metadata (idx INTEGER PRIMARY KEY, data BLOB, size INTEGER);", nil, nil, nil) == SQLITE_OK)
        insertStep(db: cDb, idx: 0, metadata: makeStepMetadata(timestamp: now))
        let cGen = makeGenMetadata(modelName: "gemini-4-carbon", inputTokens: 1_000_000, outputTokens: 1_000_000, cachedTokens: 1_000_000, stepIndex: 0)
        insertGen(db: cDb, idx: 0, data: cGen, size: cGen.count)
        sqlite3_close(cDb)

        // GCP box: Gemini 4 Carbon (1M in, 1M cached, 1M out -> $24.20 * 1.10 = $26.62)
        //          + Gemini 4 Hydrogen (1M in, 1M cached, 1M out -> $9.075 * 1.10 = $9.9825)
        let gcpConvId = "gcp-\(UUID().uuidString)"
        let gcpHist = "{\"display\":\"gcp prompt\",\"timestamp\":\(tsMs),\"workspace\":\"/tmp/g\",\"conversationId\":\"\(gcpConvId)\"}\n"
        try gcpHist.write(to: gcpDir.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)

        var gDb: OpaquePointer?
        let gDbPath = gcpConvDir.appendingPathComponent("\(gcpConvId).db").path
        #expect(sqlite3_open(gDbPath, &gDb) == SQLITE_OK)
        #expect(sqlite3_exec(gDb, "CREATE TABLE steps (idx INTEGER PRIMARY KEY, metadata BLOB, step_payload BLOB);", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(gDb, "CREATE TABLE gen_metadata (idx INTEGER PRIMARY KEY, data BLOB, size INTEGER);", nil, nil, nil) == SQLITE_OK)
        insertStep(db: gDb, idx: 0, metadata: makeStepMetadata(timestamp: now))
        insertStep(db: gDb, idx: 1, metadata: makeStepMetadata(timestamp: now.addingTimeInterval(5)))
        let gGen0 = makeGenMetadata(modelName: "gemini-4-carbon", inputTokens: 1_000_000, outputTokens: 1_000_000, cachedTokens: 1_000_000, stepIndex: 0)
        let gGen1 = makeGenMetadata(modelName: "gemini-4-hydrogen", inputTokens: 1_000_000, outputTokens: 1_000_000, cachedTokens: 1_000_000, stepIndex: 1)
        insertGen(db: gDb, idx: 0, data: gGen0, size: gGen0.count)
        insertGen(db: gDb, idx: 1, data: gGen1, size: gGen1.count)
        sqlite3_close(gDb)

        AgyStatsService.clearCaches()
        let (stats, _) = await AgyStatsService.loadStats(cliDir: consumerDir.path, gcpCliDir: gcpDir.path)

        let expectedConsumer = 24.20
        let expectedGcp = 26.62 + 9.9825 // 36.6025
        #expect(abs(stats.quotaTotalCost - expectedConsumer) < 0.0001)
        #expect(abs(stats.quotaTodayCost - expectedConsumer) < 0.0001)
        #expect(abs(stats.quotaWeeklyCost - expectedConsumer) < 0.0001)

        #expect(abs(stats.gcpTotalCost - expectedGcp) < 0.0001)
        #expect(abs(stats.gcpTodayCost - expectedGcp) < 0.0001)
        #expect(abs(stats.gcpWeeklyCost - expectedGcp) < 0.0001)
        #expect(abs(stats.totalCostEstimate - (expectedConsumer + expectedGcp)) < 0.0001)

        let entriesSum = stats.gcpSpendEntries.reduce(0.0) { $0 + $1.cost }
        #expect(abs(entriesSum - expectedGcp) < 0.0001)

        let todayBucket = stats.dailyUsage.last
        #expect(todayBucket != nil)
        #expect(abs((todayBucket?.quotaCost ?? 0) - expectedConsumer) < 0.0001)
        #expect(abs((todayBucket?.gcpCost ?? 0) - expectedGcp) < 0.0001)
        #expect(abs((todayBucket?.gcpModelBreakdown["Gemini 4 Carbon (High)"] ?? 0) - 26.62) < 0.0001)
        #expect(abs((todayBucket?.gcpModelBreakdown["Gemini 4 Hydrogen (High)"] ?? 0) - 9.9825) < 0.0001)
        #expect(abs((todayBucket?.quotaModelBreakdown["Gemini 4 Carbon (High)"] ?? 0) - 24.20) < 0.0001)
    }

    @Test
    func testMidLogOAuthAccountSwitchAndCustomDomainResolution() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent("multi-sub-auth-\(UUID().uuidString)")
        let logDir = rootDir.appendingPathComponent("log")
        let convDir = rootDir.appendingPathComponent("conversations")
        let isolatedGcpDir = rootDir.appendingPathComponent("empty_gcp").path
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: convDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootDir)
            AgyStatsService.clearCaches()
        }

        let logFile = logDir.appendingPathComponent("cli-20261117_190000.log")
        let paddingLine = "I1117 19:01:00.000000    1000 runner.go:100] Processing step output chunk padding data\n"
        let filler = String(repeating: paddingLine, count: 950) // > 70KB (>64KB offset)

        let logContent = """
        I1117 19:00:05.100000    1000 server_oauth.go:221] applyAuthResult: email=first.user@gmail.com, authMethod=consumer, quotaProject=
        I1117 19:00:05.100010    1000 server_oauth.go:226] OAuth: authenticated successfully as first.user@gmail.com
        \(filler)
        I1117 19:15:10.500000    1000 server_oauth.go:221] applyAuthResult: email=gcp.only@corp.example, authMethod=gcp, quotaProject=my-proj
        I1117 19:15:10.500020    1000 server_oauth.go:226] OAuth: authenticated successfully as gcp.only@corp.example
        I1117 19:20:49.989245    2085 browser.go:167] consumerOAuth: authenticated successfully as alice@acme-custom.io
        """
        try logContent.write(to: logFile, atomically: true, encoding: .utf8)

        // Symlink cli.log -> log/cli-20261117_190000.log like real CLI
        let cliLogSymlink = rootDir.appendingPathComponent("cli.log")
        try FileManager.default.createSymbolicLink(at: cliLogSymlink, withDestinationURL: logFile)

        // 1. resolveActiveConsumerEmail must read tail (>64KB), skip gcp-paired OAuth, and return custom domain email
        let resolved = AgyStatsService.resolveActiveConsumerEmail(cliDir: rootDir.path)
        #expect(resolved == "alice@acme-custom.io")

        // 2. loadAuthTransitions must record all mid-session transitions chronologically
        AgyStatsService.clearCaches()
        let transitions = AgyStatsService.loadAuthTransitions(logDir: logDir.path, defaultProject: nil)
        let customTransitions = transitions.filter { $0.email == "alice@acme-custom.io" }
        #expect(!customTransitions.isEmpty)
        #expect(customTransitions.last?.isGcp == false)

        let firstTransitions = transitions.filter { $0.email == "first.user@gmail.com" }
        #expect(!firstTransitions.isEmpty)

        // 3. loadStats must attribute queries after the mid-log /login to alice@acme-custom.io and invalidate cache on token switch
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let tsAfterSwitch = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 19, minute: 22, second: 0))!
        let tsMs = Int64(tsAfterSwitch.timeIntervalSince1970 * 1000)
        let historyLine = "{\"display\":\"post-switch query\",\"timestamp\":\(tsMs),\"workspace\":\"/tmp/ws\",\"conversationId\":\"conv-switch-1\"}\n"
        try historyLine.write(to: rootDir.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)

        let (stats1, _) = await AgyStatsService.loadStats(cliDir: rootDir.path, gcpCliDir: isolatedGcpDir)
        let q1 = stats1.recentQueries.first(where: { $0.conversationId == "conv-switch-1" })
        #expect(q1?.isGcp == false)
        #expect(q1?.accountEmail == "alice@acme-custom.io")

        // 4. Write antigravity-oauth-token with another custom domain and verify resolveActiveConsumerEmail + statsCache invalidation
        let tokenJson = """
        {"auth_method":"consumer","id_token_email":"bob@enterprise.org"}
        """
        try tokenJson.write(to: rootDir.appendingPathComponent("antigravity-oauth-token"), atomically: true, encoding: .utf8)
        #expect(AgyStatsService.resolveActiveConsumerEmail(cliDir: rootDir.path) == "bob@enterprise.org")
    }

    @Test
    func testResolveActiveConsumerEmailPreservesStartupAuthWithOver300KBTrailingLogs() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent("head-tail-auth-\(UUID().uuidString)")
        let logDir = rootDir.appendingPathComponent("log")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootDir)
            AgyStatsService.clearCaches()
        }

        let logFile = logDir.appendingPathComponent("cli-20261117_193000.log")
        let paddingLine = "I1117 19:31:00.000000    1000 runner.go:100] Streaming model response chunk without any auth event padding data\n"
        // > 300KB (> 262,144 byte tail window) of trailing non-auth log output
        let filler = String(repeating: paddingLine, count: 3_200)
        #expect(filler.utf8.count > 300_000)

        let logContent = """
        I1117 19:30:01.100000    1000 server_oauth.go:221] applyAuthResult: email=startup.user@custom.dev, authMethod=consumer, quotaProject=
        I1117 19:30:01.100010    1000 server_oauth.go:226] OAuth: authenticated successfully as startup.user@custom.dev
        \(filler)
        """
        try logContent.write(to: logFile, atomically: true, encoding: .utf8)

        let cliLogSymlink = rootDir.appendingPathComponent("cli.log")
        try FileManager.default.createSymbolicLink(at: cliLogSymlink, withDestinationURL: logFile)

        AgyStatsService.clearCaches()
        // 1. Startup consumer email in first 32KB must still resolve even when >300KB of trailing logs follow it
        #expect(AgyStatsService.resolveActiveConsumerEmail(cliDir: rootDir.path) == "startup.user@custom.dev")
        // 2. Second call hits memo cache and returns identical result
        #expect(AgyStatsService.resolveActiveConsumerEmail(cliDir: rootDir.path) == "startup.user@custom.dev")

        // 3. Appending a mid-session /login in the tail must invalidate memo cache and win over startup auth
        let switchLine = "I1117 19:45:00.500000    1000 consumer_oauth.go:167] consumerOAuth: authenticated successfully as switched.user@acme.io\n"
        let handle = try FileHandle(forWritingTo: logFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(switchLine.utf8))
        try handle.close()

        #expect(AgyStatsService.resolveActiveConsumerEmail(cliDir: rootDir.path) == "switched.user@acme.io")
    }

    @Test
    func testLoadStatsPopulatesDiscoveredConsumerEmailsAndAccountQueries() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent("discovered-emails-\(UUID().uuidString)")
        let logDir = rootDir.appendingPathComponent("log")
        let isolatedGcpDir = rootDir.appendingPathComponent("gcp-empty").path
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootDir)
            AgyStatsService.clearCaches()
        }

        let logContent = """
        I1117 19:10:00.000000    1000 server_oauth.go:221] applyAuthResult: email=used.account@acme.io, authMethod=consumer, quotaProject=
        I1117 19:20:00.000000    1000 server_oauth.go:221] applyAuthResult: email=brandnew.unused@acme.io, authMethod=consumer, quotaProject=
        """
        try logContent.write(to: logDir.appendingPathComponent("cli-20261117_191000.log"), atomically: true, encoding: .utf8)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let qDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 19, minute: 12, second: 0))!
        let tsMs = Int64(qDate.timeIntervalSince1970 * 1000)
        let historyLine = "{\"display\":\"hello world\",\"timestamp\":\(tsMs),\"workspace\":\"/tmp/ws\",\"conversationId\":\"conv-1\"}\n"
        try historyLine.write(to: rootDir.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)

        AgyStatsService.clearCaches()
        let (stats, _) = await AgyStatsService.loadStats(cliDir: rootDir.path, gcpCliDir: isolatedGcpDir)

        #expect(stats.discoveredConsumerEmails.contains("used.account@acme.io"))
        #expect(stats.discoveredConsumerEmails.contains("brandnew.unused@acme.io"))
        #expect(stats.accountQueryTotals["used.account@acme.io"] == 1)
        #expect(stats.accountQueryTotals["brandnew.unused@acme.io"] == nil)
        #expect(!stats.consumerSpendEntries.isEmpty)
        #expect(stats.consumerSpendEntries.allSatisfy { $0.email == "used.account@acme.io" })
    }

    @Test
    func testParseAuthEventsIgnoresNonGlogLinesAndSyntheticEmails() throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent("glog-anchor-\(UUID().uuidString)")
        let logDir = rootDir.appendingPathComponent("log")
        try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootDir)
            AgyStatsService.clearCaches()
        }

        let logFile = logDir.appendingPathComponent("cli-20261117_191300.log")
        let logContent = """
        I1117 19:13:16.341234    2203 server_oauth.go:221] applyAuthResult: email=real.user@acme.org, authMethod=consumer, quotaProject=
        I1117 19:14:00.000000    2203 server_oauth.go:221] applyAuthResult: email=fixture@test.com, authMethod=consumer, quotaProject=
        I1117 19:14:01.000000    2203 server_oauth.go:221] applyAuthResult: email=leak@company.internal, authMethod=consumer, quotaProject=
        applyAuthResult: email=fake@domain.com, authMethod=consumer, quotaProject=
        +I1117 19:15:00.000000    2203 server_oauth.go:221] applyAuthResult: email=diff@domain.com, authMethod=consumer, quotaProject=
          consumerOAuth: authenticated successfully as tool@domain.com
        {"tool_output":"OAuth: authenticated successfully as payload@domain.com"}
        """
        try logContent.write(to: logFile, atomically: true, encoding: .utf8)

        let cliLogSymlink = rootDir.appendingPathComponent("cli.log")
        try FileManager.default.createSymbolicLink(at: cliLogSymlink, withDestinationURL: logFile)

        AgyStatsService.clearCaches()
        let resolved = AgyStatsService.resolveActiveConsumerEmail(cliDir: rootDir.path)
        #expect(resolved == "real.user@acme.org")

        let transitions = AgyStatsService.loadAuthTransitions(logDir: logDir.path, defaultProject: nil)
        let emails = Set(transitions.compactMap(\.email))
        #expect(emails.contains("real.user@acme.org"))
        #expect(!emails.contains("fake@domain.com"))
        #expect(!emails.contains("diff@domain.com"))
        #expect(!emails.contains("tool@domain.com"))
        #expect(!emails.contains("payload@domain.com"))
        #expect(!emails.contains("fixture@test.com"))
        #expect(!emails.contains("leak@company.internal"))
    }

    @Test
    func testCombinedConsumerAndGcpHistoryPreservesNewestFirstOrderAndNeonPricing() async throws {
        let rootDir = FileManager.default.temporaryDirectory.appendingPathComponent("neon-sort-test-\(UUID().uuidString)")
        let consumerDir = rootDir.appendingPathComponent("consumer")
        let consumerConvDir = consumerDir.appendingPathComponent("conversations")
        let gcpDir = rootDir.appendingPathComponent("gcp")
        let gcpConvDir = gcpDir.appendingPathComponent("conversations")
        try FileManager.default.createDirectory(at: consumerConvDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gcpConvDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootDir)
            AgyStatsService.clearCaches()
        }

        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let tenDaysAgo = now.addingTimeInterval(-10 * 86400)

        // Consumer history has an old query (10d ago) AND a today query
        let consumerConvOld = "conv-old-\(UUID().uuidString)"
        let consumerConvToday = "conv-today-\(UUID().uuidString)"
        let consumerHistory = """
        {"display":"old prompt","timestamp":\(Int64(tenDaysAgo.timeIntervalSince1970 * 1000)),"workspace":"/tmp/c","conversationId":"\(consumerConvOld)"}
        {"display":"today neon prompt","timestamp":\(Int64(now.timeIntervalSince1970 * 1000)),"workspace":"/tmp/c","conversationId":"\(consumerConvToday)"}
        """
        try consumerHistory.write(to: consumerDir.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)

        // GCP history has a query 10 days ago
        let gcpConvOld = "gcp-old-\(UUID().uuidString)"
        let gcpHistory = """
        {"display":"gcp old prompt","timestamp":\(Int64(tenDaysAgo.timeIntervalSince1970 * 1000)),"workspace":"/tmp/g","conversationId":"\(gcpConvOld)"}
        """
        try gcpHistory.write(to: gcpDir.appendingPathComponent("history.jsonl"), atomically: true, encoding: .utf8)

        // Write a Neon generation with a large unused Field 1.2 payload to verify fast zero-copy protobuf walker skips it accurately
        var f4Data = Data()
        f4Data.append(encodeField(tag: 1, varint: 1532)) // Gemini 4 Neon (High)
        f4Data.append(encodeField(tag: 2, varint: 1_000_000))
        f4Data.append(encodeField(tag: 3, varint: 1_000_000))
        f4Data.append(encodeField(tag: 5, varint: 1_000_000))

        var kvStep = Data()
        kvStep.append(encodeField(tag: 1, string: "last_step_index"))
        kvStep.append(encodeField(tag: 2, string: "0"))

        var f1Data = Data()
        f1Data.append(encodeField(tag: 2, bytes: Data(repeating: 0x41, count: 65_536))) // large unused payload
        f1Data.append(encodeField(tag: 19, string: "gemini-4-neon"))
        f1Data.append(encodeField(tag: 4, bytes: f4Data))
        f1Data.append(encodeField(tag: 20, bytes: kvStep))
        let neonGenBlob = encodeField(tag: 1, bytes: f1Data)

        var db: OpaquePointer?
        let dbPath = consumerConvDir.appendingPathComponent("\(consumerConvToday).db").path
        #expect(sqlite3_open(dbPath, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE steps (idx INTEGER PRIMARY KEY, metadata BLOB, step_payload BLOB);", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(db, "CREATE TABLE gen_metadata (idx INTEGER PRIMARY KEY, data BLOB, size INTEGER);", nil, nil, nil) == SQLITE_OK)
        insertStep(db: db, idx: 0, metadata: makeStepMetadata(timestamp: now))
        insertGen(db: db, idx: 0, data: neonGenBlob, size: neonGenBlob.count)
        sqlite3_close(db)

        AgyStatsService.clearCaches()
        let (stats, _) = await AgyStatsService.loadStats(cliDir: consumerDir.path, gcpCliDir: gcpDir.path)

        // Queries must remain sorted newest-first even when GCP history is merged, so queriesToday == 1
        #expect(stats.totalQueries == 3)
        #expect(stats.queriesToday == 1)
        #expect(stats.queriesThisWeek == 1)
        #expect(stats.recentQueries.first?.conversationId == consumerConvToday)

        // Gemini 4 Neon consumer cost: $3.00 + $15.00 + $0.15 = $18.15
        #expect(abs(stats.quotaTodayCost - 18.15) < 0.0001)
        let todayBucket = stats.dailyUsage.last
        #expect(abs((todayBucket?.quotaModelBreakdown["Gemini 4 Neon (High)"] ?? 0) - 18.15) < 0.0001)
    }
}
