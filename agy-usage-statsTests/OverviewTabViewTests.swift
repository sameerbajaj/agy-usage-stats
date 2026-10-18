//
//  OverviewTabViewTests.swift
//  agy-usage-statsTests
//
//  Created by Antigravity on 10/18/26.
//

import Testing
import Foundation
@testable import agy_usage_stats

@Suite(.serialized)
struct OverviewTabViewTests {
    
    // MARK: - Fixture Helpers
    
    private func makeBucket(
        periodKey: String,
        label: String,
        shortLabel: String,
        date: Date,
        totalCost: Double,
        quotaCost: Double,
        gcpCost: Double,
        queryCount: Int = 10,
        quotaQueryCount: Int = 4,
        gcpQueryCount: Int = 6,
        inputTokens: Int = 50_000,
        outputTokens: Int = 10_000,
        quotaInputTokens: Int = 20_000,
        quotaOutputTokens: Int = 5_000,
        gcpInputTokens: Int = 30_000,
        gcpOutputTokens: Int = 5_000,
        modelBreakdown: [String: Double] = [:],
        quotaModelBreakdown: [String: Double] = [:],
        gcpModelBreakdown: [String: Double] = [:]
    ) -> UsageTimeBucket {
        UsageTimeBucket(
            periodKey: periodKey,
            label: label,
            shortLabel: shortLabel,
            date: date,
            queryCount: queryCount,
            totalCost: totalCost,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            modelBreakdown: modelBreakdown,
            modelQueryBreakdown: [:],
            gcpCost: gcpCost,
            quotaCost: quotaCost,
            accountCostBreakdown: ["sub": quotaCost, "gcp": gcpCost],
            accountQueryBreakdown: ["sub": quotaQueryCount, "gcp": gcpQueryCount],
            gcpModelBreakdown: gcpModelBreakdown,
            quotaModelBreakdown: quotaModelBreakdown,
            gcpInputTokens: gcpInputTokens,
            gcpOutputTokens: gcpOutputTokens,
            quotaInputTokens: quotaInputTokens,
            quotaOutputTokens: quotaOutputTokens,
            gcpQueryCount: gcpQueryCount,
            quotaQueryCount: quotaQueryCount
        )
    }

    // MARK: - 1. Per-Account Bucket Cost Extraction
    
    @Test func testPerAccountBucketCostExtraction() {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        
        let bucket = makeBucket(
            periodKey: "2026-10-15",
            label: "Thu, Oct 15",
            shortLabel: "Oct 15",
            date: date,
            totalCost: 12.50,
            quotaCost: 4.50,
            gcpCost: 8.00,
            queryCount: 100,
            quotaQueryCount: 40,
            gcpQueryCount: 60,
            inputTokens: 200_000,
            outputTokens: 50_000,
            quotaInputTokens: 70_000,
            quotaOutputTokens: 20_000,
            gcpInputTokens: 130_000,
            gcpOutputTokens: 30_000,
            modelBreakdown: ["gemini-2.5-pro": 8.00, "claude-3-5-sonnet": 4.50],
            quotaModelBreakdown: ["claude-3-5-sonnet": 4.50],
            gcpModelBreakdown: ["gemini-2.5-pro": 8.00]
        )
        
        // 1. Costs
        #expect(OverviewTabView.bucketCost(bucket, account: .all) == 12.50)
        #expect(OverviewTabView.bucketCost(bucket, account: .subscription) == 4.50)
        #expect(OverviewTabView.bucketCost(bucket, account: .gcp) == 8.00)
        
        // 2. Tokens
        #expect(OverviewTabView.bucketTokens(bucket, account: .all) == 250_000)
        #expect(OverviewTabView.bucketTokens(bucket, account: .subscription) == 90_000)
        #expect(OverviewTabView.bucketTokens(bucket, account: .gcp) == 160_000)
        
        // 3. Queries
        #expect(OverviewTabView.bucketQueries(bucket, account: .all) == 100)
        #expect(OverviewTabView.bucketQueries(bucket, account: .subscription) == 40)
        #expect(OverviewTabView.bucketQueries(bucket, account: .gcp) == 60)
        
        // 4. Model Breakdown
        let allBreakdown = OverviewTabView.bucketModelBreakdown(bucket, account: .all)
        let subBreakdown = OverviewTabView.bucketModelBreakdown(bucket, account: .subscription)
        let gcpBreakdown = OverviewTabView.bucketModelBreakdown(bucket, account: .gcp)
        
        #expect(allBreakdown.values.reduce(0, +) == 12.50)
        #expect(subBreakdown.values.reduce(0, +) == 4.50)
        #expect(gcpBreakdown.values.reduce(0, +) == 8.00)
    }

    // MARK: - 2. Peak Day Calculation
    
    @Test func testPeakDayCalculation() {
        let baseDate = Date(timeIntervalSince1970: 1792100000) // approx Oct 2026
        let daySecs: TimeInterval = 86400
        
        // Bucket 1: Day 1 - Moderate Sub, Low GCP
        let b1 = makeBucket(
            periodKey: "day-1", label: "Day 1", shortLabel: "D1",
            date: baseDate,
            totalCost: 3.0, quotaCost: 2.5, gcpCost: 0.5
        )
        // Bucket 2: Day 2 - Zero Sub, Massive GCP
        let b2 = makeBucket(
            periodKey: "day-2", label: "Day 2", shortLabel: "D2",
            date: baseDate.addingTimeInterval(daySecs),
            totalCost: 15.0, quotaCost: 0.0, gcpCost: 15.0
        )
        // Bucket 3: Day 3 - Highest Sub, Zero GCP
        let b3 = makeBucket(
            periodKey: "day-3", label: "Day 3", shortLabel: "D3",
            date: baseDate.addingTimeInterval(daySecs * 2),
            totalCost: 10.0, quotaCost: 10.0, gcpCost: 0.0
        )
        // Bucket 4: Day 4 - $0 Day
        let b4 = makeBucket(
            periodKey: "day-4", label: "Day 4", shortLabel: "D4",
            date: baseDate.addingTimeInterval(daySecs * 3),
            totalCost: 0.0, quotaCost: 0.0, gcpCost: 0.0
        )
        
        let buckets = [b1, b2, b3, b4]
        
        // .all peak should be Day 2 ($15.00)
        let peakAll = OverviewTabView.peakBucket(in: buckets, account: .all)
        #expect(peakAll?.id == "day-2")
        #expect(OverviewTabView.bucketCost(peakAll!, account: .all) == 15.0)
        
        // .subscription peak should be Day 3 ($10.00)
        let peakSub = OverviewTabView.peakBucket(in: buckets, account: .subscription)
        #expect(peakSub?.id == "day-3")
        #expect(OverviewTabView.bucketCost(peakSub!, account: .subscription) == 10.0)
        
        // .gcp peak should be Day 2 ($15.00)
        let peakGcp = OverviewTabView.peakBucket(in: buckets, account: .gcp)
        #expect(peakGcp?.id == "day-2")
        #expect(OverviewTabView.bucketCost(peakGcp!, account: .gcp) == 15.0)
        
        // Empty buckets should yield nil
        #expect(OverviewTabView.peakBucket(in: [], account: .all) == nil)
        
        // All-zero cost buckets should yield nil (must have cost > 0 to be a peak day)
        #expect(OverviewTabView.peakBucket(in: [b4], account: .all) == nil)
    }

    // MARK: - 3. Day Selection & Timeframe Filtering
    
    @Test func testDaySelectionAndFiltering() {
        let baseDate = Date(timeIntervalSince1970: 1792100000)
        let daySecs: TimeInterval = 86400
        
        var allBuckets: [UsageTimeBucket] = []
        for i in 0..<14 {
            allBuckets.append(
                makeBucket(
                    periodKey: "day-\(i)",
                    label: "Day \(i)",
                    shortLabel: "D\(i)",
                    date: baseDate.addingTimeInterval(daySecs * Double(i)),
                    totalCost: Double(i + 1) * 1.5,
                    quotaCost: Double(i + 1),
                    gcpCost: Double(i + 1) * 0.5
                )
            )
        }
        
        // 1. Timeframe filtering
        let todayBuckets = OverviewTabView.filterBuckets(for: .today, in: allBuckets)
        #expect(todayBuckets.count == 1)
        #expect(todayBuckets.first?.id == "day-13")
        
        let weekBuckets = OverviewTabView.filterBuckets(for: .week, in: allBuckets)
        #expect(weekBuckets.count == 7)
        #expect(weekBuckets.first?.id == "day-7")
        #expect(weekBuckets.last?.id == "day-13")
        
        let monthBuckets = OverviewTabView.filterBuckets(for: .month, in: allBuckets)
        #expect(monthBuckets.count == 14) // bounded by available 14
        
        let allFiltered = OverviewTabView.filterBuckets(for: .all, in: allBuckets)
        #expect(allFiltered.count == 14)
        
        // 2. Day selection (pinnedBucket)
        let pinned = OverviewTabView.pinnedBucket(for: "day-5", in: allBuckets)
        #expect(pinned != nil)
        #expect(pinned?.id == "day-5")
        #expect(OverviewTabView.bucketCost(pinned!, account: .all) == 9.0)
        
        let nonExistent = OverviewTabView.pinnedBucket(for: "day-999", in: allBuckets)
        #expect(nonExistent == nil)
        
        let nilSelection = OverviewTabView.pinnedBucket(for: nil, in: allBuckets)
        #expect(nilSelection == nil)
    }

    // MARK: - 4. Non-Overlapping Tick Indices
    
    @Test func testNonOverlappingTickIndices() {
        #expect(OverviewTabView.computeTickIndices(totalCount: 1) == [0])
        #expect(OverviewTabView.computeTickIndices(totalCount: 0).isEmpty)
        #expect(OverviewTabView.computeTickIndices(totalCount: 7) == [0, 1, 2, 3, 4, 5, 6])
        
        let ticks14 = OverviewTabView.computeTickIndices(totalCount: 14)
        #expect(ticks14.first == 0)
        #expect(ticks14.last == 13)
        #expect(ticks14.count >= 3 && ticks14.count <= 5)
        #expect(ticks14 == Array(Set(ticks14)).sorted())
        
        let ticks30 = OverviewTabView.computeTickIndices(totalCount: 30)
        #expect(ticks30 == [0, 7, 14, 21, 29])
        #expect(ticks30.first == 0)
        #expect(ticks30.last == 29)
        for idx in ticks30 {
            #expect(idx >= 0 && idx < 30)
        }
        
        let ticks45 = OverviewTabView.computeTickIndices(totalCount: 45)
        #expect(ticks45.first == 0)
        #expect(ticks45.last == 44)
        #expect(ticks45 == Array(Set(ticks45)).sorted())
        for idx in ticks45 {
            #expect(idx >= 0 && idx < 45)
        }
    }
}

