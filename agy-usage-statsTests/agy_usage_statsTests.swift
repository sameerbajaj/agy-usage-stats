//
//  agy_usage_statsTests.swift
//  agy-usage-statsTests
//
//  Created by Sameer Bajaj on 6/14/26.
//

import Testing
@testable import agy_usage_stats

struct agy_usage_statsTests {

    @Test func testFetchQuota() async throws {
        print("--- TEST FETCH QUOTA START ---")
        if let quota = await AgyQuotaService.fetchQuota() {
            print("Quota Email: \(quota.email ?? "nil")")
            print("Quota Plan: \(quota.plan ?? "nil")")
            print("Quota Groups count: \(quota.groups.count)")
            for g in quota.groups {
                print("  Group: \(g.displayName)")
                for b in g.buckets {
                    print("    Bucket: \(b.displayName), remaining: \(b.remainingFraction ?? -1.0)")
                }
            }
        } else {
            print("Quota fetched returned nil!")
        }
        
        print("--- TEST LOAD STATS START ---")
        let (stats, settings) = await AgyStatsService.loadStats(cliDir: "~/.gemini/antigravity-cli")
        print("Stats Total Queries: \(stats.totalQueries)")
        print("Stats Queries Today: \(stats.queriesToday)")
        print("Stats Tool Calls: \(stats.totalToolCalls)")
        print("Stats Quota Info: \(stats.quotaInfo != nil ? "present" : "nil")")
        print("--- TEST END ---")
    }

}
