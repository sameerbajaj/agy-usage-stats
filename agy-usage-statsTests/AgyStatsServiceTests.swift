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
}
