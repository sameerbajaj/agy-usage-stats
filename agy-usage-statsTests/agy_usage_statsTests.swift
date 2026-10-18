//
//  agy_usage_statsTests.swift
//  agy-usage-statsTests
//
//  Created by Sameer Bajaj on 6/14/26.
//

import Testing
import AppKit
@testable import agy_usage_stats

@Suite(.serialized)
struct agy_usage_statsTests {

    // MARK: - Quota Probing Tests

    @Test func testNonemptySubscriptionBeatsEarlierEmptyGcp() async throws {
        let emptyGcpInfo = AgyQuotaInfo(
            email: "test@example.com",
            plan: "Pay-as-you-go",
            groups: []
        )
        let bucket = AgyQuotaBucket(
            bucketId: "gemini-weekly",
            displayName: "Weekly Limit Remaining",
            remainingFraction: 0.85,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )
        let subscriptionInfo = AgyQuotaInfo(
            email: "test@example.com",
            plan: "Google AI Pro",
            groups: [
                AgyQuotaGroup(displayName: "Gemini Models", description: nil, buckets: [bucket])
            ]
        )

        let result = await AgyQuotaService.probePorts([1001, 1002]) { port in
            if port == 1001 {
                return emptyGcpInfo
            } else {
                return subscriptionInfo
            }
        }

        #expect(result != nil)
        #expect(result?.0 == 1002)
        #expect(result?.1.groups.count == 1)
        #expect(result?.1.plan == "Google AI Pro")
    }

    @Test func testOnlyEmptyOrUnavailableCandidatesYieldNil() async throws {
        let emptyInfo = AgyQuotaInfo(
            email: "test@example.com",
            plan: "Free",
            groups: []
        )

        let result = await AgyQuotaService.probePorts([2001, 2002]) { port in
            if port == 2001 {
                return emptyInfo
            } else {
                return nil
            }
        }

        #expect(result == nil)
    }

    // MARK: - Quota Text Resolution Tests

    @Test func testQuotaTextResolution() {
        // Both models available
        let bothText = MenuBarPresentationResolver.resolveQuotaText(
            geminiFraction: 0.75,
            claudeFraction: 0.50
        )
        #expect(bothText == "G:75% C:50%")

        // Gemini only
        let geminiOnlyText = MenuBarPresentationResolver.resolveQuotaText(
            geminiFraction: 0.80,
            claudeFraction: nil
        )
        #expect(geminiOnlyText == "G:80%")

        // Claude only
        let claudeOnlyText = MenuBarPresentationResolver.resolveQuotaText(
            geminiFraction: nil,
            claudeFraction: 0.90
        )
        #expect(claudeOnlyText == "C:90%")

        // All three models available, including equal fractions (e.g. both 100%)
        let allThreeEqual = MenuBarPresentationResolver.resolveQuotaText(
            geminiFraction: 1.00,
            argonFraction: 1.00,
            claudeFraction: 0.50
        )
        #expect(allThreeEqual == "G:100% A:100% C:50%")

        // Both missing: never "gcp direct" or false "100%"
        let missingText = MenuBarPresentationResolver.resolveQuotaText(
            geminiFraction: nil,
            claudeFraction: nil
        )
        #expect(missingText == "no subscription session")
    }

    // MARK: - Icon Presentation Tests

    @Test func testIconPresentationActiveModel() {
        let litNS = NSColor.systemGreen

        // Active model with valid fraction
        let activeWithQuota = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .active,
            queriesToday: 10,
            litColor: litNS,
            activeUsageFraction: 0.65,
            activeFillFraction: 0.65,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(activeWithQuota.text == "65%")
        #expect(activeWithQuota.gaugeStyle == .single(fraction: 0.65, strokeColor: litNS))

        // Active model with NO quota fraction, but queriesToday > 0: activity fallback (Nq)
        let activeActivityFallback = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .active,
            queriesToday: 7,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(activeActivityFallback.text == "7q")
        #expect(activeActivityFallback.gaugeStyle == .single(fraction: 1.0, strokeColor: litNS))

        // Active model with NO quota and queriesToday == 0: neutral chevron (no text, no gauge)
        let activeChevronFallback = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .active,
            queriesToday: 0,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(activeChevronFallback.text == "")
        #expect(activeChevronFallback.gaugeStyle == .none)
    }

    @Test func testIconPresentationSingleModelsMissingQuota() {
        let litNS = NSColor.systemGreen

        // Gemini with quota
        let geminiPresent = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .gemini,
            queriesToday: 5,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: 0.82,
            geminiFillFraction: 0.82,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(geminiPresent.text == "G:82%")
        #expect(geminiPresent.gaugeStyle == .single(fraction: 0.82, strokeColor: MenuBarPresentationResolver.geminiColor))

        // Gemini missing quota: neutral chevron, never "GCP" or "100%"
        let geminiMissing = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .gemini,
            queriesToday: 5,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(geminiMissing.text == "")
        #expect(geminiMissing.gaugeStyle == .none)

        // Claude with quota
        let claudePresent = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .claude,
            queriesToday: 5,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: 0.45,
            claudeFillFraction: 0.45
        )
        #expect(claudePresent.text == "C:45%")
        #expect(claudePresent.gaugeStyle == .single(fraction: 0.45, strokeColor: MenuBarPresentationResolver.claudeColor))

        // Claude missing quota: neutral chevron, never "GCP" or "100%"
        let claudeMissing = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .claude,
            queriesToday: 5,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(claudeMissing.text == "")
        #expect(claudeMissing.gaugeStyle == .none)
    }

    @Test func testBothSelectionHandlesMissingModelSafely() {
        let litNS = NSColor.systemGreen

        // Both present
        let bothPresent = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .both,
            queriesToday: 3,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: 0.85,
            geminiFillFraction: 0.85,
            claudeUsageFraction: 0.40,
            claudeFillFraction: 0.40
        )
        #expect(bothPresent.text == "G:85% C:40%")
        #expect(bothPresent.gaugeStyle == .both(geminiFraction: 0.85, claudeFraction: 0.40))

        // Only Gemini present in Both mode: safe single gauge & text, no fabricated Claude 100%
        let geminiOnlyInBoth = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .both,
            queriesToday: 3,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: 0.85,
            geminiFillFraction: 0.85,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(geminiOnlyInBoth.text == "G:85%")
        #expect(geminiOnlyInBoth.gaugeStyle == .single(fraction: 0.85, strokeColor: MenuBarPresentationResolver.geminiColor))

        // Only Claude present in Both mode: safe single gauge & text, no fabricated Gemini 100%
        let claudeOnlyInBoth = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .both,
            queriesToday: 3,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: 0.40,
            claudeFillFraction: 0.40
        )
        #expect(claudeOnlyInBoth.text == "C:40%")
        #expect(claudeOnlyInBoth.gaugeStyle == .single(fraction: 0.40, strokeColor: MenuBarPresentationResolver.claudeColor))

        // Both missing: neutral chevron, never "GCP" or "100%"
        let bothMissing = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .both,
            queriesToday: 3,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(bothMissing.text == "")
        #expect(bothMissing.gaugeStyle == .none)
    }

    // MARK: - GCP Decoupling Tests

    @Test func testGcpActiveWithSubscriptionQuotasRendersSubscriptionValues() {
        var stats = AgyUsageStats.empty
        stats.gcpProject = "clawdbot-485304"
        #expect(stats.isGcpActive == true)

        // With valid quota fractions, quotaText must render subscription percentages, NOT "gcp direct"
        let text = MenuBarPresentationResolver.resolveQuotaText(
            geminiFraction: 0.70,
            claudeFraction: 0.90
        )
        #expect(text == "G:70% C:90%")
        #expect(!text.contains("gcp"))

        // With valid quota fractions, icon presentation must render subscription percentages, NOT "GCP"
        let iconState = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .both,
            queriesToday: 5,
            litColor: NSColor.systemGreen,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: 0.70,
            geminiFillFraction: 0.70,
            claudeUsageFraction: 0.90,
            claudeFillFraction: 0.90
        )
        #expect(iconState.text == "G:70% C:90%")
        #expect(!iconState.text.contains("GCP"))
        #expect(iconState.gaugeStyle == .both(geminiFraction: 0.70, claudeFraction: 0.90))
    }

    // MARK: - Multi-Session Dynamic Model Tracking Tests

    @Test func testDynamicModelSwitchingToDepletedModel() {
        let vm = AgyStatsViewModel()
        vm.selectedModelForIcon = .active
        vm.iconQuotaLimitTarget = .fiveHour
        vm.settings.model = "Claude Sonnet 4.6 (Thinking)"

        let geminiBucket = AgyQuotaBucket(
            bucketId: "gemini-5h",
            displayName: "Five Hour Limit Remaining",
            remainingFraction: 0.17,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )
        let claudeBucket = AgyQuotaBucket(
            bucketId: "3p-5h",
            displayName: "Five Hour Limit Remaining",
            remainingFraction: 0.97,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )

        let geminiGroup = AgyQuotaGroup(displayName: "Gemini Models", description: nil, buckets: [geminiBucket])
        let claudeGroup = AgyQuotaGroup(displayName: "Claude and GPT models", description: nil, buckets: [claudeBucket])

        vm.stats.quotaInfo = AgyQuotaInfo(
            email: "test@example.com",
            plan: "Google AI Pro",
            groups: [geminiGroup, claudeGroup]
        )

        // Simulate active terminal querying Gemini
        let recentQ = QueryEntry(
            display: "Fix AGY usage stats menu bar app",
            timestamp: Date(),
            workspace: "/Users/sameerbajaj/PARA/Projects/dev/cli-chores/dev_bot",
            conversationId: "test-conv-1",
            type: nil,
            conversationMeta: nil,
            modelName: "Gemini 3.8 Flash (High)",
            isGcp: false,
            gcpProject: nil,
            accountEmail: nil
        )
        vm.stats.recentQueries = [recentQ]

        // Despite settings.model being Sonnet, active model must dynamically switch to Gemini!
        let activeGroup = vm.getActiveGroup()
        #expect(activeGroup != nil)
        #expect(activeGroup?.displayName == "Gemini Models")
        #expect(vm.selectedModelUsageFraction == 0.17)
        #expect(vm.activeModelDisplayName == "Gemini 3.8 Flash (High)")
    }

    @Test func testMultiTerminalActiveDepletionPriority() {
        let vm = AgyStatsViewModel()
        vm.selectedModelForIcon = .active
        vm.iconQuotaLimitTarget = .fiveHour
        vm.settings.model = "Claude Sonnet 4.6 (Thinking)"

        let geminiBucket = AgyQuotaBucket(
            bucketId: "gemini-5h",
            displayName: "Five Hour Limit Remaining",
            remainingFraction: 0.15,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )
        let claudeBucket = AgyQuotaBucket(
            bucketId: "3p-5h",
            displayName: "Five Hour Limit Remaining",
            remainingFraction: 0.85,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )

        let geminiGroup = AgyQuotaGroup(displayName: "Gemini Models", description: nil, buckets: [geminiBucket])
        let claudeGroup = AgyQuotaGroup(displayName: "Claude and GPT models", description: nil, buckets: [claudeBucket])

        vm.stats.quotaInfo = AgyQuotaInfo(
            email: "test@example.com",
            plan: "Google AI Pro",
            groups: [geminiGroup, claudeGroup]
        )

        // Both terminals active recently (one Sonnet, one Gemini)
        let q1 = QueryEntry(
            display: "Query 1",
            timestamp: Date().addingTimeInterval(-100),
            workspace: "/ws1",
            conversationId: "c1",
            type: nil,
            conversationMeta: nil,
            modelName: "Claude Sonnet 4.6",
            isGcp: false,
            gcpProject: nil,
            accountEmail: nil
        )
        let q2 = QueryEntry(
            display: "Query 2",
            timestamp: Date().addingTimeInterval(-200),
            workspace: "/ws2",
            conversationId: "c2",
            type: nil,
            conversationMeta: nil,
            modelName: "Gemini 3.8 Flash",
            isGcp: false,
            gcpProject: nil,
            accountEmail: nil
        )
        vm.stats.recentQueries = [q1, q2]

        // When both models are active, it must prioritize the one actively getting depleted (Gemini at 0.15)!
        let activeGroup = vm.getActiveGroup()
        #expect(activeGroup?.displayName == "Gemini Models")
        #expect(vm.selectedModelUsageFraction == 0.15)
    }

    @Test func testMostDepletedSelection() {
        let vm = AgyStatsViewModel()
        vm.selectedModelForIcon = .mostDepleted

        let geminiBucket = AgyQuotaBucket(
            bucketId: "gemini-5h",
            displayName: "Five Hour Limit Remaining",
            remainingFraction: 0.40,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )
        let claudeBucket = AgyQuotaBucket(
            bucketId: "3p-5h",
            displayName: "Five Hour Limit Remaining",
            remainingFraction: 0.10, // Claude is more depleted here
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )

        let geminiGroup = AgyQuotaGroup(displayName: "Gemini Models", description: nil, buckets: [geminiBucket])
        let claudeGroup = AgyQuotaGroup(displayName: "Claude and GPT models", description: nil, buckets: [claudeBucket])

        vm.stats.quotaInfo = AgyQuotaInfo(
            email: "test@example.com",
            plan: "Google AI Pro",
            groups: [geminiGroup, claudeGroup]
        )

        let group = vm.getActiveGroup()
        #expect(group?.displayName == "Claude and GPT models")
        #expect(vm.selectedModelUsageFraction == 0.10)
    }

    @Test func testResolveIconPresentationMostDepleted() {
        let litNS = NSColor.systemGreen

        let presentation = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .mostDepleted,
            queriesToday: 12,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: 0.75,
            geminiFillFraction: 0.75,
            claudeUsageFraction: 0.22,
            claudeFillFraction: 0.22
        )

        // Claude is at 22% vs Gemini at 75%, so most depleted is Claude at 22%
        #expect(presentation.text == "22%")
        #expect(presentation.gaugeStyle == .single(fraction: 0.22, strokeColor: litNS))
    }

    // MARK: - Gemini 4 Argon & Claude 5.5 Tests

    @Test func testArgonAndClaude55CatalogAndPricing() {
        // Gemini 4 Argon
        let argonHigh = knownModels.first { $0.name == "Gemini 4 Argon (High)" }
        #expect(argonHigh != nil)
        #expect(argonHigh?.inputPricePerMillion == 2.00)
        #expect(argonHigh?.outputPricePerMillion == 10.00)
        #expect(argonHigh?.cachedInputPricePerMillion == 0.10)

        let argonLow = knownModels.first { $0.name == "Gemini 4 Argon (Low)" }
        #expect(argonLow != nil)
        #expect(argonLow?.inputPricePerMillion == 2.00)
        #expect(argonLow?.outputPricePerMillion == 10.00)

        // Claude Sonnet 5.5
        let sonnet55High = knownModels.first { $0.name == "Claude Sonnet 5.5 (High)" }
        #expect(sonnet55High != nil)
        #expect(sonnet55High?.inputPricePerMillion == 2.00)
        #expect(sonnet55High?.outputPricePerMillion == 10.00)
        #expect(sonnet55High?.cachedInputPricePerMillion == 0.20)

        // Claude Opus 5.5
        let opus55High = knownModels.first { $0.name == "Claude Opus 5.5 (High)" }
        #expect(opus55High != nil)
        #expect(opus55High?.inputPricePerMillion == 4.00)
        #expect(opus55High?.outputPricePerMillion == 20.00)
        #expect(opus55High?.cachedInputPricePerMillion == 0.20)
    }

    @Test func testArgonAndClaudeCostCalculation() {
        let meta = ConversationDbMeta(
            llmCalls: 1,
            totalOutputBytes: 40000,
            inputTokens: 100_000,
            outputTokens: 10_000,
            cachedInputTokens: 50_000
        )
        let query = QueryEntry(
            display: "Build complex feature",
            timestamp: Date(),
            workspace: "/Users/test/workspace",
            conversationId: "test-conv",
            type: nil,
            conversationMeta: meta,
            modelName: nil
        )

        // Argon: 100k * $2/M ($0.20) + 50k * $0.10/M ($0.005) + 10k * $10/M ($0.10) = $0.305
        let argon = knownModels.first { $0.name == "Gemini 4 Argon (High)" }!
        let argonResult = argon.estimateTokensAndCost(for: query)
        #expect(argonResult.inputTokens == 150_000)
        #expect(argonResult.outputTokens == 10_000)
        #expect(abs(argonResult.cost - 0.305) < 0.0001)

        // Sonnet 5.5: 100k * $2/M ($0.20) + 50k * $0.20/M ($0.010) + 10k * $10/M ($0.10) = $0.310
        let sonnet55 = knownModels.first { $0.name == "Claude Sonnet 5.5 (High)" }!
        let sonnetResult = sonnet55.estimateTokensAndCost(for: query)
        #expect(abs(sonnetResult.cost - 0.310) < 0.0001)

        // Opus 5.5: 100k * $4/M ($0.40) + 50k * $0.20/M ($0.010) + 10k * $20/M ($0.20) = $0.610
        let opus55 = knownModels.first { $0.name == "Claude Opus 5.5 (High)" }!
        let opusResult = opus55.estimateTokensAndCost(for: query)
        #expect(abs(opusResult.cost - 0.610) < 0.0001)
    }

    @Test func testModelNamePatternMappings() {
        #expect(AgyStatsService.cleanAndMapModelName("gemini-4-argon") == "Gemini 4 Argon (High)")
        #expect(AgyStatsService.cleanAndMapModelName("gemini-argon-low") == "Gemini 4 Argon (Low)")
        #expect(AgyStatsService.cleanAndMapModelName("argon-high") == "Gemini 4 Argon (High)")
        #expect(AgyStatsService.cleanAndMapModelName("argon") == "Gemini 4 Argon (High)")

        #expect(AgyStatsService.cleanAndMapModelName("claude-sonnet-5-5-high") == "Claude Sonnet 5.5 (High)")
        #expect(AgyStatsService.cleanAndMapModelName("claude-sonnet-5.5-medium") == "Claude Sonnet 5.5 (Medium)")
        #expect(AgyStatsService.cleanAndMapModelName("sonnet-5.5-low") == "Claude Sonnet 5.5 (Low)")
        #expect(AgyStatsService.cleanAndMapModelName("sonnet") == "Claude Sonnet 5.5 (High)")

        #expect(AgyStatsService.cleanAndMapModelName("claude-opus-5-5-high") == "Claude Opus 5.5 (High)")
        #expect(AgyStatsService.cleanAndMapModelName("opus-5-5-low") == "Claude Opus 5.5 (Low)")
        #expect(AgyStatsService.cleanAndMapModelName("opus") == "Claude Opus 5.5 (High)")

        #expect(AgyStatsService.cleanAndMapModelName("claude-sonnet-4-6") == "Claude Sonnet 4.6 (Thinking)")
        #expect(AgyStatsService.cleanAndMapModelName("claude-opus-4-6") == "Claude Opus 4.6 (Thinking)")
    }

    @Test func testArgonAndClaude55QuotaGroupMatching() {
        let vm = AgyStatsViewModel()
        let geminiBucket = AgyQuotaBucket(
            bucketId: "gemini-weekly",
            displayName: "Weekly Limit",
            remainingFraction: 0.80,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )
        let claudeBucket = AgyQuotaBucket(
            bucketId: "claude-weekly",
            displayName: "Weekly Limit",
            remainingFraction: 0.60,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )

        let geminiGroup = AgyQuotaGroup(displayName: "Gemini Models", description: nil, buckets: [geminiBucket])
        let claudeGroup = AgyQuotaGroup(displayName: "Claude and GPT models", description: nil, buckets: [claudeBucket])

        vm.stats.quotaInfo = AgyQuotaInfo(
            email: "test@example.com",
            plan: "Google AI Pro",
            groups: [geminiGroup, claudeGroup]
        )

        // Argon matches Gemini quota group
        let argonGroup = vm.getGroup(matchingModelName: "Gemini 4 Argon (High)")
        #expect(argonGroup?.displayName == "Gemini Models")

        let argonShortGroup = vm.getGroup(matchingModelName: "argon-high")
        #expect(argonShortGroup?.displayName == "Gemini Models")

        // Claude 5.5 matches Claude quota group
        let sonnet55Group = vm.getGroup(matchingModelName: "Claude Sonnet 5.5 (High)")
        #expect(sonnet55Group?.displayName == "Claude and GPT models")

        let opus55Group = vm.getGroup(matchingModelName: "Claude Opus 5.5 (High)")
        #expect(opus55Group?.displayName == "Claude and GPT models")

        // When dedicated Argon quota group is present (e.g. Pro plan with separate Argon quota)
        let argonBucket = AgyQuotaBucket(
            bucketId: "gemini-argon-wtu-weekly",
            displayName: "Gemini 4 Argon Weekly Limit",
            remainingFraction: 1.0,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )
        let dedicatedArgonGroup = AgyQuotaGroup(
            displayName: "Gemini 4 Argon",
            description: "For paid Pro plans, Argon quota is separate.",
            buckets: [argonBucket]
        )
        vm.stats.quotaInfo = AgyQuotaInfo(
            email: "test@example.com",
            plan: "Google AI Pro",
            groups: [geminiGroup, claudeGroup, dedicatedArgonGroup]
        )

        let dedicatedMatch = vm.getGroup(matchingModelName: "Gemini 4 Argon (High)")
        #expect(dedicatedMatch?.displayName == "Gemini 4 Argon")

        let dedicatedShortMatch = vm.getGroup(matchingModelName: "argon-high")
        #expect(dedicatedShortMatch?.displayName == "Gemini 4 Argon")
    }

    // MARK: - Tab Consolidation & Canonical Model Tests

    @Test func testCanonicalModelConsolidation() {
        let bucket = UsageTimeBucket(
            periodKey: "2026-10-17",
            label: "Today",
            shortLabel: "17",
            date: Date(),
            queryCount: 15,
            totalCost: 1.50,
            inputTokens: 20_000,
            outputTokens: 1_000,
            modelBreakdown: [
                "Gemini 4 Argon (High)": 1.40,
                "Gemini 4 Argon (Medium)": 0.10
            ]
        )

        let consolidated = bucket.consolidatedModelBreakdown
        #expect(consolidated.count == 1)
        #expect(consolidated["Gemini 4 Argon"] != nil)
        #expect(abs((consolidated["Gemini 4 Argon"] ?? 0.0) - 1.50) < 0.001)

        // Test multi-day aggregation
        let bucket2 = UsageTimeBucket(
            periodKey: "2026-10-16",
            label: "Oct 16",
            shortLabel: "16",
            date: Date().addingTimeInterval(-86400),
            queryCount: 10,
            totalCost: 2.20,
            inputTokens: 30_000,
            outputTokens: 2_000,
            modelBreakdown: [
                "Gemini 4 Argon (High)": 0.80,
                "Claude Opus 5.5 (High)": 1.40
            ]
        )

        let multiDay = [bucket, bucket2]
        let multiBreakdown = multiDay.aggregatedModelBreakdown

        #expect(multiBreakdown.count == 2)
        #expect(abs((multiBreakdown["Gemini 4 Argon"] ?? 0.0) - 2.30) < 0.001)
        #expect(abs((multiBreakdown["Claude Opus 5.5"] ?? 0.0) - 1.40) < 0.001)
        #expect(abs(multiDay.aggregatedTotalCost - 3.70) < 0.001)
        #expect(multiDay.aggregatedQueryCount == 25)
    }

    @Test func testPopoverTabConsolidation() {
        let tabs = PopoverTab.allCases
        #expect(tabs.count == 2)
        #expect(tabs == [.usage, .settings])
    }

    @Test func testExhaustedWeeklyQuotaOverridesDisabledFiveHourBucket() {
        let vm = AgyStatsViewModel()
        vm.selectedModelForIcon = .claude
        vm.iconQuotaLimitTarget = .fiveHour

        // Simulates real Anthropic quota returned by Antigravity:
        // Weekly is 0% (hit weekly limit), and 5-hour is 5.8% with disabled: true
        let disabledFiveHourBucket = AgyQuotaBucket(
            bucketId: "3p-5h",
            displayName: "5-Hour Limit",
            remainingFraction: 0.0584544,
            resetDescription: "You have hit your weekly limit, the 5-hour limit does not currently apply",
            disabled: true,
            resetTime: nil
        )
        let exhaustedWeeklyBucket = AgyQuotaBucket(
            bucketId: "3p-weekly",
            displayName: "Weekly Limit",
            remainingFraction: 0.0,
            resetDescription: "Resets Saturday at 12:43 PM",
            disabled: false,
            resetTime: nil
        )

        let claudeGroup = AgyQuotaGroup(
            displayName: "Claude and GPT models",
            description: nil,
            buckets: [disabledFiveHourBucket, exhaustedWeeklyBucket]
        )

        vm.stats.quotaInfo = AgyQuotaInfo(
            email: "sameerbajaj24@gmail.com",
            plan: "Google AI Ultra",
            groups: [claudeGroup]
        )

        // Menu bar utilization must be 0% (exhausted), NOT 6% from the disabled bucket!
        #expect(vm.selectedModelUsageFraction == 0.0)
        #expect(vm.claudeUsageFraction == 0.0)
    }

    @Test func testOfflineCommandsNeverAccrueCost() {
        let model = knownModels.first { $0.name == "Claude Opus 5.5 (Medium)" }!
        let rewindQuery = QueryEntry(
            display: "/rewind",
            timestamp: Date(),
            workspace: "/test"
        )
        let (inTokens, outTokens, cost) = model.estimateTokensAndCost(for: rewindQuery)
        #expect(inTokens == 0)
        #expect(outTokens == 0)
        #expect(cost == 0.0)

        let modelQuery = QueryEntry(
            display: "/model",
            timestamp: Date(),
            workspace: "/test"
        )
        let (_, _, modelCost) = model.estimateTokensAndCost(for: modelQuery)
        #expect(modelCost == 0.0)
    }

    @Test func testHistoricalGcpAttributionAndCostAggregation() async throws {
        AgyStatsService.clearCaches()
        let cliDir = AgyStatsService.getDefaultCliDir()
        if FileManager.default.fileExists(atPath: (cliDir as NSString).appendingPathComponent("history.jsonl")) {
            let (stats, _) = await AgyStatsService.loadStats(cliDir: cliDir)
            let gcpDays = stats.dailyUsage.filter { $0.gcpCost > 0 }.map { $0.periodKey }
            #expect(gcpDays.contains("2026-09-02"))
            #expect(gcpDays.contains("2026-09-03"))
            #expect(gcpDays.contains("2026-09-15"))
            #expect(stats.gcpTotalCost >= 13.0)
            
            let hasGcpAccount = stats.accountCostTotals.keys.contains { $0.contains("GCP") || $0.contains("clawdbot") }
            #expect(hasGcpAccount)
        }
    }

    @Test func testArgonGroupNilWhenNotPresent() {
        let vm = AgyStatsViewModel()
        let geminiBucket = AgyQuotaBucket(bucketId: "g-w", displayName: "Weekly Limit", remainingFraction: 0.8, resetDescription: nil, disabled: false, resetTime: nil)
        let claudeBucket = AgyQuotaBucket(bucketId: "c-w", displayName: "Weekly Limit", remainingFraction: 0.5, resetDescription: nil, disabled: false, resetTime: nil)
        let geminiGroup = AgyQuotaGroup(displayName: "Gemini Models", description: nil, buckets: [geminiBucket])
        let claudeGroup = AgyQuotaGroup(displayName: "Claude and GPT models", description: nil, buckets: [claudeBucket])
        
        vm.stats.quotaInfo = AgyQuotaInfo(email: "test@example.com", plan: "Pro", groups: [geminiGroup, claudeGroup])
        // Must return nil and not fall back to Gemini
        #expect(vm.argonUsageFraction == nil)
        #expect(vm.argonCircleFillFraction == nil)
        
        // When Argon group is added, it resolves cleanly
        let argonBucket = AgyQuotaBucket(bucketId: "a-w", displayName: "Weekly Limit", remainingFraction: 0.95, resetDescription: nil, disabled: false, resetTime: nil)
        let argonGroup = AgyQuotaGroup(displayName: "Gemini 4 Argon", description: nil, buckets: [argonBucket])
        vm.stats.quotaInfo = AgyQuotaInfo(email: "test@example.com", plan: "Pro", groups: [geminiGroup, claudeGroup, argonGroup])
        #expect(vm.argonUsageFraction == 0.95)
    }

    @Test func testAllThreeAndArgonIconPresentation() {
        let litNS = NSColor.systemGreen

        // Argon single presentation
        let argonPresent = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .argon,
            queriesToday: 4,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            argonUsageFraction: 0.75,
            argonFillFraction: 0.75,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(argonPresent.text == "A:75%")
        #expect(argonPresent.gaugeStyle == .single(fraction: 0.75, strokeColor: MenuBarPresentationResolver.argonColor))

        // Argon missing presentation -> neutral chevron
        let argonMissing = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .argon,
            queriesToday: 4,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            argonUsageFraction: nil,
            argonFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(argonMissing.text == "")
        #expect(argonMissing.gaugeStyle == .none)

        // All three present
        let allThreePresent = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .allThree,
            queriesToday: 4,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: 0.80,
            geminiFillFraction: 0.80,
            argonUsageFraction: 0.90,
            argonFillFraction: 0.90,
            claudeUsageFraction: 0.50,
            claudeFillFraction: 0.50
        )
        #expect(allThreePresent.text == "G:80% A:90% C:50%")
        #expect(allThreePresent.gaugeStyle == .three(geminiFraction: 0.80, argonFraction: 0.90, claudeFraction: 0.50))

        // All three mode when Argon is nil: graceful fallback to .both
        let allThreeArgonNil = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .allThree,
            queriesToday: 4,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: 0.80,
            geminiFillFraction: 0.80,
            argonUsageFraction: nil,
            argonFillFraction: nil,
            claudeUsageFraction: 0.50,
            claudeFillFraction: 0.50
        )
        #expect(allThreeArgonNil.text == "G:80% C:50%")
        #expect(allThreeArgonNil.gaugeStyle == .both(geminiFraction: 0.80, claudeFraction: 0.50))
    }

    @Test func testGcpCreditPoolConfiguration() {
        let vm = AgyStatsViewModel()
        // Default pool for promo credit
        #expect(vm.gcpCreditPool >= 0.0)

        // Configure custom pool
        vm.gcpCreditPool = 150.0
        #expect(vm.gcpCreditPool == 150.0)

        // Set to 0.0 for unlimited spend tracking
        vm.gcpCreditPool = 0.0
        #expect(vm.gcpCreditPool == 0.0)
    }
}



