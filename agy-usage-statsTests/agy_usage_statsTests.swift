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
}
