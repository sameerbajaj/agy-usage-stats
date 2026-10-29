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
    private static func makeIsolatedViewModel() -> AgyStatsViewModel {
        let suiteName = "test-suite-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return AgyStatsViewModel(userDefaults: defaults)
    }

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

        // Active model with valid fraction (> 50% -> healthy green)
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
        #expect(activeWithQuota.textColor == MenuBarPresentationResolver.healthyGreenColor)
        #expect(activeWithQuota.gaugeStyle == .single(fraction: 0.65, strokeColor: MenuBarPresentationResolver.healthyGreenColor))

        // Active model with decoupled colors: 5-Hour low (15% -> red) vs Weekly healthy (85% -> green)
        let decoupledActive = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .active,
            queriesToday: 10,
            litColor: litNS,
            activeUsageFraction: 0.15,
            activeFillFraction: 0.85,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(decoupledActive.text == "15%")
        #expect(decoupledActive.textColor == MenuBarPresentationResolver.lowRedColor)
        #expect(decoupledActive.gaugeStyle == .single(fraction: 0.85, strokeColor: MenuBarPresentationResolver.healthyGreenColor))

        // Active model with warning tier (35% -> amber)
        let amberActive = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .active,
            queriesToday: 10,
            litColor: litNS,
            activeUsageFraction: 0.35,
            activeFillFraction: 0.35,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(amberActive.text == "35%")
        #expect(amberActive.textColor == MenuBarPresentationResolver.warningAmberColor)
        #expect(amberActive.gaugeStyle == .single(fraction: 0.35, strokeColor: MenuBarPresentationResolver.warningAmberColor))

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

        // Gemini with quota (> 50% -> healthy green)
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
        #expect(geminiPresent.text == "82%")
        #expect(geminiPresent.textColor == MenuBarPresentationResolver.healthyGreenColor)
        #expect(geminiPresent.gaugeStyle == .single(fraction: 0.82, strokeColor: MenuBarPresentationResolver.healthyGreenColor))

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

        // Claude with warning quota (45% -> warning amber)
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
        #expect(claudePresent.text == "45%")
        #expect(claudePresent.textColor == MenuBarPresentationResolver.warningAmberColor)
        #expect(claudePresent.gaugeStyle == .single(fraction: 0.45, strokeColor: MenuBarPresentationResolver.warningAmberColor))

        // Claude with low quota (12% -> low red)
        let claudeLow = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .claude,
            queriesToday: 5,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: 0.12,
            claudeFillFraction: 0.12
        )
        #expect(claudeLow.text == "12%")
        #expect(claudeLow.textColor == MenuBarPresentationResolver.lowRedColor)
        #expect(claudeLow.gaugeStyle == .single(fraction: 0.12, strokeColor: MenuBarPresentationResolver.lowRedColor))

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
        #expect(geminiOnlyInBoth.text == "85%")
        #expect(geminiOnlyInBoth.textColor == MenuBarPresentationResolver.healthyGreenColor)
        #expect(geminiOnlyInBoth.gaugeStyle == .single(fraction: 0.85, strokeColor: MenuBarPresentationResolver.healthyGreenColor))

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
        #expect(claudeOnlyInBoth.text == "40%")
        #expect(claudeOnlyInBoth.textColor == MenuBarPresentationResolver.warningAmberColor)
        #expect(claudeOnlyInBoth.gaugeStyle == .single(fraction: 0.40, strokeColor: MenuBarPresentationResolver.warningAmberColor))

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
        let vm = Self.makeIsolatedViewModel()
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
        let vm = Self.makeIsolatedViewModel()
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
        let vm = Self.makeIsolatedViewModel()
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

        // Claude is at 22% vs Gemini at 75%, so most depleted is Claude at 22% (warning amber)
        #expect(presentation.text == "22%")
        #expect(presentation.textColor == MenuBarPresentationResolver.warningAmberColor)
        #expect(presentation.gaugeStyle == .single(fraction: 0.22, strokeColor: MenuBarPresentationResolver.warningAmberColor))

        // Claude is at 10% (low red)
        let redPresentation = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .mostDepleted,
            queriesToday: 12,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: 0.75,
            geminiFillFraction: 0.75,
            claudeUsageFraction: 0.10,
            claudeFillFraction: 0.10
        )
        #expect(redPresentation.text == "10%")
        #expect(redPresentation.textColor == MenuBarPresentationResolver.lowRedColor)
        #expect(redPresentation.gaugeStyle == .single(fraction: 0.10, strokeColor: MenuBarPresentationResolver.lowRedColor))
    }

    // MARK: - Gemini 4 Argon & Claude 5.5 Tests

    @Test func testArgonAndClaude55CatalogAndPricing() {
        // Gemini 4 Argon
        let argonHigh = knownModels.first { $0.name == "Gemini 4 Argon (High)" }
        #expect(argonHigh != nil)
        #expect(argonHigh?.inputPricePerMillion == 2.00)
        #expect(argonHigh?.outputPricePerMillion == 12.00)
        #expect(argonHigh?.cachedInputPricePerMillion == 0.50)

        let argonLow = knownModels.first { $0.name == "Gemini 4 Argon (Low)" }
        #expect(argonLow != nil)
        #expect(argonLow?.inputPricePerMillion == 2.00)
        #expect(argonLow?.outputPricePerMillion == 12.00)

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

        // Argon: 100k * $2/M ($0.20) + 50k * $0.50/M ($0.025) + 10k * $12/M ($0.12) = $0.345
        let argon = knownModels.first { $0.name == "Gemini 4 Argon (High)" }!
        let argonResult = argon.estimateTokensAndCost(for: query)
        #expect(argonResult.inputTokens == 150_000)
        #expect(argonResult.outputTokens == 10_000)
        #expect(abs(argonResult.cost - 0.345) < 0.0001)

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
        let vm = Self.makeIsolatedViewModel()
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
        let vm = Self.makeIsolatedViewModel()
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
            let totalGcpQueries = stats.dailyUsage.reduce(0) { $0 + $1.gcpQueryCount }
            let gcpDays = stats.dailyUsage.filter { $0.gcpCost > 0 }.map { $0.periodKey }
            #expect(!gcpDays.isEmpty)
            #expect(gcpDays.contains("2026-09-03"))
            #expect(stats.gcpTodayCost >= 0.0)
            #expect(totalGcpQueries > 0)
            
            let hasGcpAccount = stats.accountCostTotals.keys.contains { $0.contains("GCP") || $0.contains("clawdbot") }
            #expect(hasGcpAccount)
        }
    }

    @Test func testArgonGroupNilWhenNotPresent() {
        let vm = Self.makeIsolatedViewModel()
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
        #expect(argonPresent.text == "75%")
        #expect(argonPresent.textColor == MenuBarPresentationResolver.healthyGreenColor)
        #expect(argonPresent.gaugeStyle == .single(fraction: 0.75, strokeColor: MenuBarPresentationResolver.healthyGreenColor))

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
        let vm = Self.makeIsolatedViewModel()
        // Default pool for promo credit
        #expect(vm.gcpCreditPool >= 0.0)

        // Configure custom pool
        vm.gcpCreditPool = 150.0
        #expect(vm.gcpCreditPool == 150.0)

        // Set to 0.0 for unlimited spend tracking
        vm.gcpCreditPool = 0.0
        #expect(vm.gcpCreditPool == 0.0)
    }

    @Test func testGcpCreditPoolStringAndTypeDeserialization() {
        let suiteName = "test-deserialization-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        
        // String formatted value (e.g. from defaults write without -float)
        defaults.set("200.55", forKey: "agy_gcpCreditPool")
        let vmString = AgyStatsViewModel(userDefaults: defaults)
        #expect(vmString.gcpCreditPool == 200.55)

        // Explicit 0.0 for unlimited tracking
        defaults.set(0.0, forKey: "agy_gcpCreditPool")
        let vmZero = AgyStatsViewModel(userDefaults: defaults)
        #expect(vmZero.gcpCreditPool == 0.0)

        // Missing key defaults to 300.0 promo budget
        defaults.removeObject(forKey: "agy_gcpCreditPool")
        let vmDefault = AgyStatsViewModel(userDefaults: defaults)
        #expect(vmDefault.gcpCreditPool == 300.0)
    }

    @Test func testGcpCreditPoolRemainingCalculationWithBaseline() {
        let vm = Self.makeIsolatedViewModel()
        // Simulate existing historical GCP spend prior to setting credit pool
        vm.stats.gcpTotalCost = 5.78
        vm.stats.gcpTodayCost = 0.0

        // User sets remaining credit to 199.86
        vm.gcpCreditPool = 199.86

        #expect(vm.gcpCreditBaselineCost == 5.78)
        #expect(vm.gcpCreditBaselineTimestamp > 0.0)
        #expect(vm.gcpCostSinceBaseline == 0.0)
        #expect(vm.gcpCreditRemaining == 199.86)
        #expect(vm.gcpCreditConsumedFraction == 0.0)

        // Menu bar icon fraction matches 100% remaining of the set credit pool
        vm.selectedModelForIcon = .gcp
        #expect(vm.selectedModelUsageFraction == 1.0)
        #expect(vm.selectedModelCircleFillFraction == 1.0)
    }

    @Test func testGcpCreditPoolDeductsOnlySubsequentCost() {
        let vm = Self.makeIsolatedViewModel()
        vm.stats.gcpTotalCost = 5.78
        vm.gcpCreditPool = 199.86

        // Now new GCP queries run, adding $1.00 of spend
        vm.stats.gcpTotalCost = 6.78
        vm.stats.gcpTodayCost = 1.00

        #expect(abs(vm.gcpCostSinceBaseline - 1.00) < 0.001)
        #expect(abs(vm.gcpCreditRemaining - 198.86) < 0.001)
        #expect(abs(vm.gcpCreditConsumedFraction - (1.00 / 199.86)) < 0.001)

        vm.selectedModelForIcon = .gcp
        #expect(abs((vm.selectedModelUsageFraction ?? 0.0) - (198.86 / 199.86)) < 0.001)
    }

    @Test func testGcpCreditPoolUnaffectedBySubscriptionCost() {
        let vm = Self.makeIsolatedViewModel()
        vm.stats.gcpTotalCost = 5.78
        vm.gcpCreditPool = 199.86

        // Subscription queries incur cost, but GCP cost is unchanged
        vm.stats.quotaTotalCost = 25.50
        vm.stats.quotaTodayCost = 5.00
        #expect(vm.stats.gcpTotalCost == 5.78)

        #expect(vm.gcpCostSinceBaseline == 0.0)
        #expect(vm.gcpCreditRemaining == 199.86)
    }

    @Test func testGcpCreditPoolBaselinePersistenceAndReinstantiation() {
        let suiteName = "test-baseline-persistence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // First session: sets credit pool
        let vm1 = AgyStatsViewModel(userDefaults: defaults)
        vm1.stats.gcpTotalCost = 5.78
        vm1.gcpCreditPool = 199.86

        #expect(defaults.double(forKey: "agy_gcpCreditBaselineCost") == 5.78)
        #expect(defaults.double(forKey: "agy_gcpCreditBaselineTimestamp") > 0.0)

        // Second session: app re-opened with loaded history
        let vm2 = AgyStatsViewModel(userDefaults: defaults)
        vm2.stats.gcpTotalCost = 5.78

        #expect(vm2.gcpCreditPool == 199.86)
        #expect(vm2.gcpCreditBaselineCost == 5.78)
        #expect(vm2.gcpCreditRemaining == 199.86)

        // Subsequent session spend deducts correctly
        vm2.stats.gcpTotalCost = 7.78
        #expect(abs(vm2.gcpCreditRemaining - 197.86) < 0.001)
    }

    @Test func testGcpCreditPoolPreExistingMigration() async {
        let suiteName = "test-pre-existing-migration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Simulate pre-existing state on Sam's machine where agy_gcpCreditPool = "199.86" but baseline is nil
        defaults.set("199.86", forKey: "agy_gcpCreditPool")
        defaults.removeObject(forKey: "agy_gcpCreditBaselineCost")

        let vm = AgyStatsViewModel(userDefaults: defaults)
        #expect(vm.gcpCreditPool == 199.86)
        #expect(vm.gcpCreditBaselineCost == 0.0)

        // When stats refresh, it automatically migrates the baseline
        await MainActor.run {
            var stats = AgyUsageStats.empty
            stats.gcpTotalCost = 5.78
            vm.stats = stats
            vm.resetGcpCreditBaseline()
        }

        #expect(vm.gcpCreditBaselineCost == 5.78)
        #expect(vm.gcpCreditRemaining == 199.86)
    }

    @Test func testGcpCreditPoolTimestampAnchoredDeductionImmuneToHistoricalBaselineShift() {
        let suiteName = "test-timestamp-baseline-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Simulate stale inflated baseline cost ($17.40) recorded before historical attribution bugfix
        let baselineTs: Double = 1792954228.0
        defaults.set(179.56, forKey: "agy_gcpCreditPool")
        defaults.set(17.40, forKey: "agy_gcpCreditBaselineCost")
        defaults.set(baselineTs, forKey: "agy_gcpCreditBaselineTimestamp")

        let vm = AgyStatsViewModel(userDefaults: defaults)
        #expect(vm.gcpCreditPool == 179.56)
        #expect(vm.gcpCreditBaselineCost == 17.40)
        #expect(vm.gcpCreditBaselineTimestamp == baselineTs)

        // True pre-baseline GCP cost is $13.11, plus $0.09 spent after baselineTs ($13.20 total)
        var loadedStats = AgyUsageStats.empty
        loadedStats.gcpTotalCost = 13.20
        loadedStats.gcpTodayCost = 0.09
        loadedStats.gcpSpendEntries = [
            GcpSpendEntry(timestamp: baselineTs - 86400.0, cost: 13.11),
            GcpSpendEntry(timestamp: baselineTs + 3600.0, cost: 0.09)
        ]

        vm.stats = loadedStats
        vm.reconcileGcpBaseline(with: loadedStats)

        // Baseline self-heals to $13.11 and $0.09 post-baseline spend is accurately deducted from $179.56
        #expect(abs(vm.gcpCreditBaselineCost - 13.11) < 0.001)
        #expect(abs(vm.gcpCostSinceBaseline - 0.09) < 0.001)
        #expect(abs(vm.gcpCreditRemaining - 179.47) < 0.001)
    }

    @Test func testGcpCreditPoolNoOpReassignmentDoesNotWipeBaseline() {
        let suiteName = "test-noop-pool-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Simulate 32-bit float precision stored in plist ("179.559998")
        let baselineTs: Double = 1792954228.0
        defaults.set("179.559998", forKey: "agy_gcpCreditPool")
        defaults.set(13.11, forKey: "agy_gcpCreditBaselineCost")
        defaults.set(baselineTs, forKey: "agy_gcpCreditBaselineTimestamp")

        let vm = AgyStatsViewModel(userDefaults: defaults)
        #expect(vm.gcpCreditPool == 179.56)

        vm.stats.gcpTotalCost = 13.20
        vm.stats.gcpSpendEntries = [
            GcpSpendEntry(timestamp: baselineTs - 86400.0, cost: 13.11),
            GcpSpendEntry(timestamp: baselineTs + 3600.0, cost: 0.09)
        ]

        // Re-assigning the same value (e.g. when Settings TextField loses focus) must NOT reset baseline
        vm.gcpCreditPool = 179.56
        #expect(vm.gcpCreditBaselineTimestamp == baselineTs)
        #expect(abs(vm.gcpCostSinceBaseline - 0.09) < 0.001)
        #expect(abs(vm.gcpCreditRemaining - 179.47) < 0.001)
    }

    @Test func testGcpIconPresentation() {
        let litNS = NSColor.systemBlue
        let gcpBlue = NSColor(red: 0.26, green: 0.52, blue: 0.96, alpha: 1.0)

        // GCP model with spend today
        let gcpWithCost = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .gcp,
            queriesToday: 6,
            litColor: litNS,
            activeUsageFraction: 0.95,
            activeFillFraction: 0.95,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil,
            gcpTodayCost: 0.24
        )
        #expect(gcpWithCost.text == "$0.24")
        #expect(gcpWithCost.gaugeStyle == .single(fraction: 0.95, strokeColor: gcpBlue))

        // GCP model with 0 spend today, fallback to queries
        let gcpZeroCostQueries = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .gcp,
            queriesToday: 4,
            litColor: litNS,
            activeUsageFraction: 1.0,
            activeFillFraction: 1.0,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil,
            gcpTodayCost: 0.0
        )
        #expect(gcpZeroCostQueries.text == "100%")
        #expect(gcpZeroCostQueries.gaugeStyle == .single(fraction: 1.0, strokeColor: gcpBlue))

        // GCP model with showUsage = false -> empty text and no gauge
        let gcpHidden = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: false,
            selectedModel: .gcp,
            queriesToday: 6,
            litColor: litNS,
            activeUsageFraction: 0.95,
            activeFillFraction: 0.95,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil,
            gcpTodayCost: 0.24
        )
        #expect(gcpHidden.text == "")
        #expect(gcpHidden.gaugeStyle == .none)
    }

    @Test func testGcpQuotaTextResolution() {
        // Quota text with subscription fractions and GCP spend
        let textWithGcp = MenuBarPresentationResolver.resolveQuotaText(
            geminiFraction: 0.80,
            claudeFraction: 0.50,
            gcpTodayCost: 0.24
        )
        #expect(textWithGcp == "G:80% C:50% ☁️$0.24")

        // Quota text with no subscription session but GCP spend
        let gcpOnlyText = MenuBarPresentationResolver.resolveQuotaText(
            geminiFraction: nil,
            claudeFraction: nil,
            gcpTodayCost: 0.24
        )
        #expect(gcpOnlyText == "☁️$0.24")

        // Quota text with no session and 0 GCP spend
        let noSessionText = MenuBarPresentationResolver.resolveQuotaText(
            geminiFraction: nil,
            claudeFraction: nil,
            gcpTodayCost: 0.0
        )
        #expect(noSessionText == "no subscription session")
    }

    @Test func testViewModelGcpActiveModelTracking() {
        let vm = Self.makeIsolatedViewModel()
        vm.selectedModelForIcon = .active
        
        let claudeBucket = AgyQuotaBucket(bucketId: "c-w", displayName: "Weekly Limit", remainingFraction: 0.5, resetDescription: nil, disabled: false, resetTime: nil)
        let claudeGroup = AgyQuotaGroup(displayName: "Claude and GPT models", description: nil, buckets: [claudeBucket])
        vm.stats.quotaInfo = AgyQuotaInfo(email: "test@example.com", plan: "Pro", groups: [claudeGroup])
        
        // Add a GCP query
        let gcpQuery = QueryEntry(
            display: "Investigate GCP",
            timestamp: Date(),
            workspace: "/Users/sameerbajaj/PARA/Projects/dev/agy-usage-stats",
            modelName: "claude-3-5-sonnet",
            isGcp: true,
            gcpProject: "clawdbot-485304"
        )
        vm.stats.recentQueries = [gcpQuery]
        
        #expect(vm.activeModelDisplayName == "claude-3-5-sonnet (GCP)")
    }

    @Test func testNoPrefixesForTrackedModels() {
        let litNS = NSColor.systemGreen

        // Gemini: no "G:" prefix
        let geminiState = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .gemini,
            queriesToday: 5,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: 0.82,
            geminiFillFraction: 0.82,
            argonUsageFraction: nil,
            argonFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(geminiState.text == "82%")
        #expect(!geminiState.text.contains("G:"))

        // Argon: no "A:" prefix
        let argonState = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .argon,
            queriesToday: 5,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            argonUsageFraction: 0.40,
            argonFillFraction: 0.40,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(argonState.text == "40%")
        #expect(!argonState.text.contains("A:"))

        // Claude: no "C:" prefix
        let claudeState = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .claude,
            queriesToday: 5,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: nil,
            geminiFillFraction: nil,
            argonUsageFraction: nil,
            argonFillFraction: nil,
            claudeUsageFraction: 0.50,
            claudeFillFraction: 0.50
        )
        #expect(claudeState.text == "50%")
        #expect(!claudeState.text.contains("C:"))

        // Active: clean percentage
        let activeState = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .active,
            queriesToday: 5,
            litColor: litNS,
            activeUsageFraction: 0.34,
            activeFillFraction: 0.34,
            geminiUsageFraction: 0.82,
            geminiFillFraction: 0.82,
            argonUsageFraction: nil,
            argonFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(activeState.text == "34%")
        #expect(!activeState.text.contains(":"))

        // Most Depleted: clean percentage
        let depletedState = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .mostDepleted,
            queriesToday: 5,
            litColor: litNS,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: 0.82,
            geminiFillFraction: 0.82,
            argonUsageFraction: 0.40,
            argonFillFraction: 0.40,
            claudeUsageFraction: 0.50,
            claudeFillFraction: 0.50
        )
        #expect(depletedState.text == "40%")
        #expect(!depletedState.text.contains(":"))
    }

    @Test func testDecoupledCircleRingAndNumberLimits() {
        let vm = Self.makeIsolatedViewModel()
        vm.selectedModelForIcon = .gemini
        vm.iconQuotaLimitTarget = .fiveHour
        vm.iconCircleFillMetric = .weekly

        // Setup mock quota with 5h limit = 34% and weekly limit = 82%
        let gemini5h = AgyQuotaBucket(bucketId: "g-5h", displayName: "5-Hour Limit", remainingFraction: 0.34, resetDescription: nil, disabled: false, resetTime: nil)
        let geminiWeekly = AgyQuotaBucket(bucketId: "g-w", displayName: "Weekly Limit", remainingFraction: 0.82, resetDescription: nil, disabled: false, resetTime: nil)
        let geminiGroup = AgyQuotaGroup(displayName: "Gemini Models", description: nil, buckets: [gemini5h, geminiWeekly])

        // Argon group has only Weekly Limit = 40%
        let argonWeekly = AgyQuotaBucket(bucketId: "a-w", displayName: "Weekly Limit", remainingFraction: 0.40, resetDescription: nil, disabled: false, resetTime: nil)
        let argonGroup = AgyQuotaGroup(displayName: "Gemini 4 Argon", description: nil, buckets: [argonWeekly])

        vm.stats.quotaInfo = AgyQuotaInfo(email: "test@example.com", plan: "Pro", groups: [geminiGroup, argonGroup])

        // Gemini: Number (%) should be 5-Hour (0.34) and Circle Ring should be Weekly (0.82)
        #expect(vm.selectedModelUsageFraction == 0.34)
        #expect(vm.selectedModelCircleFillFraction == 0.82)
        #expect(vm.geminiUsageFraction == 0.34)
        #expect(vm.geminiCircleFillFraction == 0.82)

        // Argon: 5-Hour target falls back to Weekly Limit (0.40)
        vm.selectedModelForIcon = .argon
        #expect(vm.selectedModelUsageFraction == 0.40)
        #expect(vm.selectedModelCircleFillFraction == 0.40)

        // Match Percentage: Circle Ring matches Number (%)
        vm.selectedModelForIcon = .gemini
        vm.iconCircleFillMetric = .matchNumber
        vm.iconQuotaLimitTarget = .fiveHour
        #expect(vm.selectedModelUsageFraction == 0.34)
        #expect(vm.selectedModelCircleFillFraction == 0.34)

        vm.iconQuotaLimitTarget = .weekly
        #expect(vm.selectedModelUsageFraction == 0.82)
        #expect(vm.selectedModelCircleFillFraction == 0.82)

        // Decoupled colors: percentage number and ring gauge independently color-coded
        vm.iconQuotaLimitTarget = .fiveHour
        vm.iconCircleFillMetric = .weekly
        let decoupledPresentation = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .gemini,
            queriesToday: 4,
            litColor: .systemGreen,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: vm.geminiUsageFraction,
            geminiFillFraction: vm.geminiCircleFillFraction,
            argonUsageFraction: nil,
            argonFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        // 5-Hour is 34% (warning amber), Weekly is 82% (healthy green)
        #expect(decoupledPresentation.textColor == MenuBarPresentationResolver.warningAmberColor)
        #expect(decoupledPresentation.gaugeStyle == .single(fraction: 0.82, strokeColor: MenuBarPresentationResolver.healthyGreenColor))

        // Red (15%) + Green (82%) decoupled presentation
        let redGreenPresentation = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .gemini,
            queriesToday: 4,
            litColor: .systemGreen,
            activeUsageFraction: nil,
            activeFillFraction: nil,
            geminiUsageFraction: 0.15,
            geminiFillFraction: 0.82,
            argonUsageFraction: nil,
            argonFillFraction: nil,
            claudeUsageFraction: nil,
            claudeFillFraction: nil
        )
        #expect(redGreenPresentation.textColor == MenuBarPresentationResolver.lowRedColor)
        #expect(redGreenPresentation.gaugeStyle == .single(fraction: 0.82, strokeColor: MenuBarPresentationResolver.healthyGreenColor))
    }

    @Test func testSpendBadgePresentationAndMenuBarSpendSource() {
        let litNS = NSColor.systemGreen

        // GCP Spend Today
        let gcpToday = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .active,
            queriesToday: 4,
            litColor: litNS,
            activeUsageFraction: 0.34,
            activeFillFraction: 0.82,
            geminiUsageFraction: 0.34,
            geminiFillFraction: 0.82,
            claudeUsageFraction: nil,
            claudeFillFraction: nil,
            gcpTodayCost: 0.49,
            showSpend: true,
            spendSource: .gcpToday,
            spendAmount: 0.49
        )
        #expect(gcpToday.text == "34%")
        #expect(gcpToday.spendBadge != nil)
        #expect(gcpToday.spendBadge?.icon == .cloud)
        #expect(gcpToday.spendBadge?.text == "$0.49")

        // GCP Spend Total
        let gcpTotal = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .active,
            queriesToday: 4,
            litColor: litNS,
            activeUsageFraction: 0.34,
            activeFillFraction: 0.82,
            geminiUsageFraction: 0.34,
            geminiFillFraction: 0.82,
            claudeUsageFraction: nil,
            claudeFillFraction: nil,
            showSpend: true,
            spendSource: .gcpTotal,
            spendAmount: 9.67,
            gcpTotalCost: 9.67
        )
        #expect(gcpTotal.spendBadge != nil)
        #expect(gcpTotal.spendBadge?.icon == .cloud)
        #expect(gcpTotal.spendBadge?.text == "$9.67")

        // Today's API Spend (All)
        let apiToday = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .active,
            queriesToday: 4,
            litColor: litNS,
            activeUsageFraction: 0.34,
            activeFillFraction: 0.82,
            geminiUsageFraction: 0.34,
            geminiFillFraction: 0.82,
            claudeUsageFraction: nil,
            claudeFillFraction: nil,
            showSpend: true,
            spendSource: .apiToday,
            spendAmount: 51.94,
            todayCost: 51.94
        )
        #expect(apiToday.spendBadge != nil)
        #expect(apiToday.spendBadge?.icon == .dollar)
        #expect(apiToday.spendBadge?.text == "$51.94")

        // Zero cost when explicitly enabled
        let zeroSpend = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .active,
            queriesToday: 4,
            litColor: litNS,
            activeUsageFraction: 0.34,
            activeFillFraction: 0.82,
            geminiUsageFraction: 0.34,
            geminiFillFraction: 0.82,
            claudeUsageFraction: nil,
            claudeFillFraction: nil,
            gcpTodayCost: 0.0,
            showSpend: true,
            spendSource: .gcpToday,
            spendAmount: 0.0
        )
        #expect(zeroSpend.spendBadge != nil)
        #expect(zeroSpend.spendBadge?.text == "$0.00")

        // Spend disabled
        let spendDisabled = MenuBarPresentationResolver.resolveIconPresentation(
            showUsage: true,
            selectedModel: .active,
            queriesToday: 4,
            litColor: litNS,
            activeUsageFraction: 0.34,
            activeFillFraction: 0.82,
            geminiUsageFraction: 0.34,
            geminiFillFraction: 0.82,
            claudeUsageFraction: nil,
            claudeFillFraction: nil,
            gcpTodayCost: 0.49,
            showSpend: false
        )
        #expect(spendDisabled.spendBadge == nil)
    }

    // MARK: - Fast Quota & Adaptive Polling Tests

    @Test func testAdaptiveQuotaSessionDetectionAndCacheClearing() {
        // Clear active port and cache
        AgyQuotaService.clearCache(clearActivePort: true)
        #expect(AgyQuotaService.hasActiveSession == false)
        #expect(AgyQuotaService.activePort == nil)
    }

    @Test func testViewModelRefreshQuotaOnlyMainActorExecution() async {
        let viewModel = Self.makeIsolatedViewModel()
        #expect(viewModel.stats.quotaInfo == nil)
        
        // Calling refreshQuotaOnly runs safely without crash or race
        await viewModel.refreshQuotaOnly(forceRefresh: false)
    }

    // MARK: - Quota Service & Persistence Tests

    private static let persistedKey = "agy.lastKnownSubscriptionQuota"

    @Test
    func testNormalizedForCurrentTimePromotesExpiredResetTimeAndPreservesFuture() {
        let now = Date(timeIntervalSince1970: 1_700_000_000) // Fixed reference date
        let pastDate = now.addingTimeInterval(-3600) // 1 hour in the past
        let futureDate = now.addingTimeInterval(7200) // 2 hours in the future

        let isoFormatter = ISO8601DateFormatter()
        let pastIsoString = isoFormatter.string(from: pastDate)
        let futureIsoString = isoFormatter.string(from: futureDate)

        let expiredBucket = AgyQuotaBucket(
            bucketId: "gemini-5h",
            displayName: "5-Hour Limit",
            remainingFraction: 0.15,
            resetDescription: "Resets in 1 hour",
            disabled: false,
            resetTime: pastIsoString
        )

        let futureBucket = AgyQuotaBucket(
            bucketId: "gemini-weekly",
            displayName: "Weekly Limit",
            remainingFraction: 0.72,
            resetDescription: "Resets in 2 days",
            disabled: false,
            resetTime: futureIsoString
        )

        let intactBucket = AgyQuotaBucket(
            bucketId: "claude-weekly",
            displayName: "Weekly Limit",
            remainingFraction: 1.0,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )

        let group = AgyQuotaGroup(
            displayName: "Gemini",
            description: "Gemini Quota Group",
            buckets: [expiredBucket, futureBucket, intactBucket]
        )

        let quotaInfo = AgyQuotaInfo(
            email: "engineer@company.internal",
            plan: "Antigravity Pro",
            groups: [group]
        )

        let normalized = quotaInfo.normalizedForCurrentTime(now: now)
        #expect(normalized.groups.count == 1)

        let normBuckets = normalized.groups[0].buckets
        #expect(normBuckets.count == 3)

        // 1. Expired bucket must be promoted to 1.0 and have resetTime cleared to nil
        let normExpired = normBuckets.first(where: { $0.bucketId == "gemini-5h" })
        #expect(normExpired != nil)
        #expect(normExpired?.remainingFraction == 1.0)
        #expect(normExpired?.resetTime == nil)

        // 2. Future bucket must preserve its remainingFraction and resetTime
        let normFuture = normBuckets.first(where: { $0.bucketId == "gemini-weekly" })
        #expect(normFuture != nil)
        #expect(normFuture?.remainingFraction == 0.72)
        #expect(normFuture?.resetTime == futureIsoString)

        // 3. Intact bucket remains 1.0 and nil
        let normIntact = normBuckets.first(where: { $0.bucketId == "claude-weekly" })
        #expect(normIntact != nil)
        #expect(normIntact?.remainingFraction == 1.0)
        #expect(normIntact?.resetTime == nil)
    }

    @Test
    func testNormalizedForCurrentTimeWithFractionalSecondsAndEpoch() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pastDate = now.addingTimeInterval(-120)

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let pastFractionalString = fractionalFormatter.string(from: pastDate)

        let bucketWithFractional = AgyQuotaBucket(
            bucketId: "b-frac",
            displayName: "Fractional",
            remainingFraction: 0.45,
            resetDescription: nil,
            disabled: false,
            resetTime: pastFractionalString
        )

        let normFractional = bucketWithFractional.normalizedForCurrentTime(now: now)
        #expect(normFractional.remainingFraction == 1.0)
        #expect(normFractional.resetTime == nil)

        let pastEpochString = String(format: "%.3f", pastDate.timeIntervalSince1970)
        let bucketWithEpoch = AgyQuotaBucket(
            bucketId: "b-epoch",
            displayName: "Epoch",
            remainingFraction: 0.30,
            resetDescription: nil,
            disabled: false,
            resetTime: pastEpochString
        )

        let normEpoch = bucketWithEpoch.normalizedForCurrentTime(now: now)
        #expect(normEpoch.remainingFraction == 1.0)
        #expect(normEpoch.resetTime == nil)
    }

    @Test
    func testSavePersistedQuotaAndLoadPersistedQuotaRoundTrip() {
        let existingBackup = UserDefaults.standard.data(forKey: Self.persistedKey)
        defer {
            if let backup = existingBackup {
                UserDefaults.standard.set(backup, forKey: Self.persistedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.persistedKey)
            }
        }

        let bucket = AgyQuotaBucket(
            bucketId: "roundtrip-bucket",
            displayName: "Roundtrip Bucket",
            remainingFraction: 0.88,
            resetDescription: "No reset pending",
            disabled: false,
            resetTime: nil
        )
        let group = AgyQuotaGroup(
            displayName: "Roundtrip Group",
            description: nil,
            buckets: [bucket]
        )
        let originalInfo = AgyQuotaInfo(
            email: "roundtrip@company.internal",
            plan: "Team Quota",
            groups: [group]
        )

        // Save through AgyQuotaService
        AgyQuotaService.savePersistedQuota(originalInfo)

        // In-memory property should immediately reflect saved value
        #expect(AgyQuotaService.lastKnownSubscriptionQuota == originalInfo)

        // Load persisted quota (with no expired reset time, should equal original exactly)
        let loaded = AgyQuotaService.loadPersistedQuota()
        #expect(loaded == originalInfo)
    }

    @Test
    func testClearCachePreservesPersistedFallback() {
        let existingBackup = UserDefaults.standard.data(forKey: Self.persistedKey)
        defer {
            if let backup = existingBackup {
                UserDefaults.standard.set(backup, forKey: Self.persistedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.persistedKey)
            }
        }

        let bucket = AgyQuotaBucket(
            bucketId: "sticky-bucket",
            displayName: "Sticky Limit",
            remainingFraction: 0.65,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )
        let group = AgyQuotaGroup(displayName: "Sticky Group", buckets: [bucket])
        let originalInfo = AgyQuotaInfo(email: "sticky@company.internal", plan: "Pro", groups: [group])

        AgyQuotaService.savePersistedQuota(originalInfo)

        // Clear cache with clearActivePort: true
        AgyQuotaService.clearCache(clearActivePort: true)

        // active session should be cleared
        #expect(!AgyQuotaService.hasActiveSession)
        #expect(AgyQuotaService.activePort == nil)

        // In-memory lastKnownSubscriptionQuota must NOT be erased by clearCache
        #expect(AgyQuotaService.lastKnownSubscriptionQuota == originalInfo)

        // UserDefaults persisted quota must NOT be erased by clearCache
        let loaded = AgyQuotaService.loadPersistedQuota()
        #expect(loaded == originalInfo)
    }

    @Test
    func testLoadPersistedQuotaNormalizesExpiredWindowsAutomatically() {
        let existingBackup = UserDefaults.standard.data(forKey: Self.persistedKey)
        defer {
            if let backup = existingBackup {
                UserDefaults.standard.set(backup, forKey: Self.persistedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.persistedKey)
            }
        }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pastDate = now.addingTimeInterval(-1800) // 30 minutes in the past
        let pastIsoString = ISO8601DateFormatter().string(from: pastDate)

        let bucket = AgyQuotaBucket(
            bucketId: "expired-on-disk",
            displayName: "5-Hour Limit",
            remainingFraction: 0.05,
            resetDescription: "Expired window",
            disabled: false,
            resetTime: pastIsoString
        )
        let group = AgyQuotaGroup(displayName: "Gemini", buckets: [bucket])
        let unnormalizedInfo = AgyQuotaInfo(email: "expired@test.com", plan: "Pro", groups: [group])

        AgyQuotaService.savePersistedQuota(unnormalizedInfo)

        // When loaded with now, it must automatically promote to 1.0 and clear resetTime
        let loaded = AgyQuotaService.loadPersistedQuota(now: now)
        #expect(loaded != nil)
        let loadedBucket = loaded?.groups.first?.buckets.first
        #expect(loadedBucket?.remainingFraction == 1.0)
        #expect(loadedBucket?.resetTime == nil)
    }

    @Test
    func testModelQuotaTypealiasesConformToCodableAndEquatable() throws {
        let bucket = ModelQuotaBucket(
            bucketId: "alias-b",
            displayName: "Alias Bucket",
            remainingFraction: 0.5,
            resetDescription: nil,
            disabled: false,
            resetTime: nil
        )
        let group = ModelQuotaGroup(displayName: "Alias Group", buckets: [bucket])
        let info = AgyQuotaInfo(email: nil, plan: nil, groups: [group])

        let encoder = JSONEncoder()
        let data = try encoder.encode(info)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AgyQuotaInfo.self, from: data)

        #expect(decoded == info)
        #expect(decoded.groups[0] == group)
        #expect(decoded.groups[0].buckets[0] == bucket)
    }

    @Test
    func testQuotaServiceFetchAndPersistedQuotaNeverDeadlocks() async {
        let existingBackup = UserDefaults.standard.data(forKey: Self.persistedKey)
        defer {
            if let backup = existingBackup {
                UserDefaults.standard.set(backup, forKey: Self.persistedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.persistedKey)
            }
        }

        AgyQuotaService.clearCache(clearActivePort: true)
        _ = AgyQuotaService.loadPersistedQuota()

        // Calling fetchQuota with forceRefresh: true will discover ports or fallback to loadPersistedQuotaUnlocked,
        // which must NEVER deadlock on quotaLock.
        let quota = await AgyQuotaService.fetchQuota(forceRefresh: true)
        _ = quota

        AgyQuotaService.clearCache(clearActivePort: true)
        let loaded = AgyQuotaService.loadPersistedQuota()
        _ = loaded
    }

    // MARK: - Update Checker Anti-Loop Tests

    @Test func testUpdateCheckerIsNewerSemanticComparison() {
        // Standard semantic version comparisons
        #expect(UpdateChecker.isNewer("1.1.85", than: "1.1.84") == true)
        #expect(UpdateChecker.isNewer("1.2.0", than: "1.1.84") == true)
        #expect(UpdateChecker.isNewer("2.0.0", than: "1.9.99") == true)
        #expect(UpdateChecker.isNewer("1.1.84", than: "1.1.84") == false)
        #expect(UpdateChecker.isNewer("1.1.83", than: "1.1.84") == false)
        #expect(UpdateChecker.isNewer("1.1.0", than: "1.1.84") == false)

        // Non-numeric versions must NEVER be treated as older (prevents infinite update loop)
        #expect(UpdateChecker.isNewer("1.1.84", than: "latest") == false)
        #expect(UpdateChecker.isNewer("latest", than: "1.1.84") == false)
        #expect(UpdateChecker.isNewer("latest", than: "latest") == false)
        #expect(UpdateChecker.isNewer("1.1.84", than: "") == false)
        #expect(UpdateChecker.isNewer("", than: "1.1.84") == false)
        #expect(UpdateChecker.isNewer("unknown", than: "unknown") == false)
    }

    @Test func testUpdateCheckerVersionExtractionAndNormalisation() {
        #expect(UpdateChecker.version(from: "agy-usage-stats 1.1.84") == "1.1.84")
        #expect(UpdateChecker.version(from: "Release v1.2.34 notes") == "1.2.34")
        #expect(UpdateChecker.version(from: "v1.0.0") == "1.0.0")
        #expect(UpdateChecker.version(from: "latest build") == nil)

        #expect(UpdateChecker.normalise("v1.1.84") == "1.1.84")
        #expect(UpdateChecker.normalise("V2.0.1") == "2.0.1")
        #expect(UpdateChecker.normalise("1.1.84") == "1.1.84")
        #expect(UpdateChecker.normalise("latest") == "latest")
    }

    @Test func testUpdateCheckerRollingTimestampRecording() {
        let testTs: TimeInterval = 1793156761
        let testVer = "1.1.84"
        UpdateChecker.recordInstalledRollingTimestamp(testTs, version: testVer)

        #expect(UpdateChecker.lastInstalledRollingTimestamp == testTs)
        #expect(UserDefaults.standard.string(forKey: UpdateChecker.lastInstalledVersionKey) == testVer)
    }
}



