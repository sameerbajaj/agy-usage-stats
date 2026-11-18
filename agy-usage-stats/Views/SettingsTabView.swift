//
//  SettingsTabView.swift
//  agy-usage-stats
//

import SwiftUI
import AppKit

struct SettingsTabView: View {
    @Bindable var viewModel: AgyStatsViewModel
    @Environment(\.colorScheme) var colorScheme
    @State private var isEditingDir = false
    @State private var tempDir = ""
    
    @State private var isHoveredQuota = false
    @State private var isHoveredAccounts = false
    @State private var isHoveredSpend = false
    @State private var isHoveredAppearance = false
    @State private var isHoveredSystem = false
    
    private var theme: ThemeColors { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme) }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Live Menu Bar Preview Mini-Card
                menuBarPreviewSection

                // Subscription Accounts & Credit Status
                subscriptionAccountsSection

                // Card 1: Subscription Quota
                subscriptionQuotaSection
                
                // Card 2: Cloud & API Spend
                cloudAndSpendSection

                // Card 3: Popover & Appearance
                popoverAppearanceSection
                
                // Card 4: CLI Data Path & Updates
                systemSection
            }
            .padding(12)
        }
        .background(theme.surfacePrimary)
    }
    
    // MARK: - Live Menu Bar Preview
    private var menuBarPreviewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("live menu bar preview")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text("real-time")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.costGreen)
            }
            .padding(.horizontal, 4)

            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(nsImage: viewModel.makeMenuBarImage())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.5 : 0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18), lineWidth: 0.75)
                        )
                )
                Spacer()
            }
            .padding(.vertical, 8)
            .themedCardStyle(theme: theme, isHovered: false)
        }
    }

    // MARK: - Subscription Accounts & Credit Status
    private var subscriptionAccountsSection: some View {
        let summaries = viewModel.subscriptionAccountSummaries

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("subscription accounts & credit status")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                if !summaries.isEmpty {
                    Text("\(summaries.count) account\(summaries.count == 1 ? "" : "s")")
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 9) {
                if summaries.isEmpty {
                    Text("No subscription accounts detected yet. Run agy /login in terminal to connect an account.")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                        if index > 0 {
                            Rectangle().fill(theme.divider).frame(height: 0.75)
                        }
                        SubscriptionAccountRowView(
                            summary: summary,
                            viewModel: viewModel,
                            theme: theme
                        )
                    }
                }

                Rectangle().fill(theme.divider).frame(height: 0.75)

                Text("Switch accounts anytime in terminal via agy /login — active quota & spend attribution switch automatically.")
                    .font(.system(size: 8.5, weight: .regular))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .themedCardStyle(theme: theme, isHovered: isHoveredAccounts)
            .onHover { h in isHoveredAccounts = h }
        }
    }
    
    // MARK: - Card 1: Subscription Quota
    private var subscriptionQuotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("menu bar — subscription quota")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Remaining %")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.85))
                        Text("Display percentage text alongside the icon")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.showModelUsageInIcon.animation(.easeInOut(duration: 0.2)))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }

                Rectangle().fill(theme.divider).frame(height: 0.75)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tracked Model")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.85))
                        Text("Targeted model group for icon gauge & %")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $viewModel.selectedModelForIcon) {
                        ForEach(IconModelSelection.primaryCases) { sel in
                            Text(sel.rawValue).tag(sel)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }

                Rectangle().fill(theme.divider).frame(height: 0.75)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Percentage Number")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.85))
                        Text("Window period for percentage number text")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $viewModel.iconQuotaLimitTarget) {
                        ForEach(IconQuotaLimitTarget.allCases) { sel in
                            Text(sel.rawValue).tag(sel)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }

                Rectangle().fill(theme.divider).frame(height: 0.75)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Circle Ring Gauge")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.85))
                        Text("Gauge metric rendered around the A-icon")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Picker("", selection: $viewModel.iconCircleFillMetric) {
                        ForEach(IconCircleFillMetric.allCases) { sel in
                            Text(sel.rawValue).tag(sel)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }
            }
            .padding(10)
            .themedCardStyle(theme: theme, isHovered: isHoveredQuota)
            .onHover { h in isHoveredQuota = h }
        }
    }

    // MARK: - Card 2: Cloud & API Spend
    private var cloudAndSpendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("menu bar — cloud & api spend")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Spend in Menu Bar")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.85))
                        Text("Display spend badge next to quota icon")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.showMenuBarSpend.animation(.easeInOut(duration: 0.2)))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }

                if viewModel.showMenuBarSpend {
                    Rectangle().fill(theme.divider).frame(height: 0.75)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Spend Metric")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(theme.textPrimary.opacity(0.85))
                            Text("Source of spend calculation in menu bar")
                                .font(.system(size: 8.5, weight: .regular))
                                .foregroundStyle(theme.textSecondary)
                        }
                        Spacer()
                        Picker("", selection: $viewModel.menuBarSpendSource) {
                            ForEach(MenuBarSpendSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                }

                Rectangle().fill(theme.divider).frame(height: 0.75)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GCP Remaining Credit ($)")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.85))
                        if viewModel.gcpCreditPool > 0 && viewModel.gcpCostSinceBaseline > 0 {
                            Text(String(format: "$%.2f left ($%.2f used since baseline)", viewModel.gcpCreditRemaining, viewModel.gcpCostSinceBaseline))
                                .font(.system(size: 8.5, weight: .regular))
                                .foregroundStyle(theme.costGreen)
                        } else {
                            Text("0 = unlimited spend tracking (no pool bar)")
                                .font(.system(size: 8.5, weight: .regular))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                    Spacer()
                    TextField("0", value: $viewModel.gcpCreditPool, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10.5, design: .monospaced))
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                        .controlSize(.small)
                }
            }
            .padding(10)
            .themedCardStyle(theme: theme, isHovered: isHoveredSpend)
            .onHover { h in isHoveredSpend = h }
        }
    }

    // MARK: - Card 3: Popover & Appearance
    private var popoverAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("popover & appearance")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                HStack {
                    Text("Theme")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.textPrimary.opacity(0.85))
                    Spacer()
                    Picker("", selection: $viewModel.selectedTheme) {
                        ForEach(AppTheme.allCases) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }

                Rectangle().fill(theme.divider).frame(height: 0.75)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Cost Breakdown")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.85))
                        Text("Render model token cost breakdown card in popover")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.showCostSummary)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }

                Rectangle().fill(theme.divider).frame(height: 0.75)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Tool Executions")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(theme.textPrimary.opacity(0.85))
                        Text("Render agent tool calling activity in popover")
                            .font(.system(size: 8.5, weight: .regular))
                            .foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Toggle("", isOn: $viewModel.showToolBreakdown)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }
            .padding(10)
            .themedCardStyle(theme: theme, isHovered: isHoveredAppearance)
            .onHover { h in isHoveredAppearance = h }
        }
    }
    
    // MARK: - Card 4: Data Path & App Updates Settings
    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("cli data path & application updates")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                // CLI Path
                if isEditingDir {
                    HStack(spacing: 8) {
                        TextField("path", text: $tempDir)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(theme.textPrimary)
                            .controlSize(.small)
                        
                        Button("save") {
                            viewModel.cliDir = tempDir
                            isEditingDir = false
                        }
                        .font(.system(size: 9.5, weight: .bold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        Button("cancel") {
                            isEditingDir = false
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.textSecondary)
                        .font(.system(size: 9.5, weight: .medium))
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(viewModel.cliDir)
                            .font(.system(size: 10).monospaced())
                            .foregroundStyle(theme.textPrimary.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Button("edit") {
                            tempDir = viewModel.cliDir
                            isEditingDir = true
                        }
                        .font(.system(size: 9.5, weight: .bold))
                        .controlSize(.mini)
                    }
                }
                
                HStack {
                    Button(action: viewModel.revealInFinder) {
                        HStack(spacing: 3) {
                            Image(systemName: "folder")
                            Text("show in finder")
                        }
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.linkBlue)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                }
                .padding(.top, 2)

                Rectangle().fill(theme.divider).frame(height: 0.75)

                // Application Updates
                HStack {
                    HStack(spacing: 4) {
                        Text("version")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                        Text("v\(UpdateChecker.currentVersion)")
                            .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                            .foregroundStyle(theme.textPrimary.opacity(0.75))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        Task {
                            await viewModel.checkForUpdates(showUpToDateFeedback: true)
                        }
                    }) {
                        if viewModel.isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Text("check now")
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        }
                    }
                    .disabled(viewModel.isCheckingForUpdates)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.linkBlue)
                }
                
                if let update = viewModel.availableUpdate {
                    Rectangle().fill(theme.divider).frame(height: 0.75)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(update.isRolling ? "New build available" : "Version v\(update.version) is available")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(theme.costGreen)
                        
                        if let notes = update.releaseNotes, !notes.isEmpty {
                            Text(notes)
                                .font(.system(size: 9))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(2)
                        }
                        
                        switch viewModel.selfUpdateState {
                        case .idle:
                            HStack(spacing: 8) {
                                Button(action: { viewModel.installUpdate() }) {
                                    Text("install")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(theme.costGreen))
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { viewModel.dismissUpdate() }) {
                                    Text("ignore")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(theme.textSecondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                            
                        case .downloading(let progress):
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Downloading (\(Int(progress * 100))%)...")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(theme.textPrimary.opacity(0.7))
                                
                                ProgressView(value: progress)
                                    .progressViewStyle(.linear)
                                    .tint(theme.costGreen)
                            }
                            
                        case .installing:
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Installing & relaunching...")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(theme.textPrimary)
                            }
                            
                        case .failed(let errorMsg):
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Update Failed")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(theme.dangerRed)
                                Text(errorMsg)
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                } else if let msg = viewModel.updateCheckMessage {
                    Rectangle().fill(theme.divider).frame(height: 0.75)
                    
                    HStack {
                        Text(msg.lowercased())
                            .font(.system(size: 9))
                            .foregroundStyle(theme.costGreen)
                        Spacer()
                    }
                }
            }
            .padding(10)
            .themedCardStyle(theme: theme, isHovered: isHoveredSystem)
            .onHover { h in isHoveredSystem = h }
        }
    }
}

private struct SubscriptionAccountRowView: View {
    let summary: SubscriptionAccountSummary
    @Bindable var viewModel: AgyStatsViewModel
    let theme: ThemeColors

    @State private var isAddingPool = false
    @State private var draftPoolText = ""

    private var compactPlanLabel: String? {
        guard let raw = summary.plan?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        if lower.contains("ultra") { return "ULTRA" }
        if lower.contains("pro") { return "PRO" }
        if lower.contains("free") { return "FREE" }
        return raw.uppercased()
    }

    private var statusBadge: (text: String, foreground: Color, background: Color) {
        if summary.isActive {
            let text = summary.hasAnyUsageToday ? "ACTIVE · IN USE" : "ACTIVE · UNTOUCHED"
            return (text, theme.costGreen, theme.costGreen.opacity(0.14))
        }
        if !summary.hasAnyHistoricalUsage {
            return ("UNUSED · $0.00", theme.textSecondary, theme.badgeBackground)
        }
        if !summary.hasAnyUsageToday {
            return ("UNUSED TODAY", theme.costGreen.opacity(0.9), theme.costGreen.opacity(0.10))
        }
        let usedText = summary.todayCost > 0.0005
            ? String(format: "USED · $%.2f TODAY", summary.todayCost)
            : "QUOTA USED"
        return (usedText, theme.claudeAccent, theme.claudeAccent.opacity(0.14))
    }

    private var quotaAndCreditsLine: String {
        guard let q = summary.quotaInfo, !q.groups.isEmpty else {
            return "Quota snapshot pending (open an agy session on this account to sync live limits)"
        }
        var line = "Quota: \(q.compactQuotaSummary)"
        if let aiCredits = summary.googleOneAiCredits {
            if aiCredits > 0 {
                let delta = summary.googleOneAiCreditsUsed > 0
                    ? " (\(summary.googleOneAiCreditsUsed) used)"
                    : " (untouched)"
                line += " · AI Credits: \(aiCredits) left\(delta)"
            } else {
                line += " · 0 overage credits"
            }
        }
        return line
    }

    private var usageLine: String {
        if summary.hasAnyHistoricalUsage {
            return String(
                format: "Usage: $%.2f today (%d q) · $%.2f 7d · $%.2f total",
                summary.todayCost,
                summary.todayQueries,
                summary.weeklyCost,
                summary.totalCost
            )
        }
        return "Usage: $0.00 · 0 queries recorded on this account"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Top line: indicator + email + plan pill + status badge
            HStack(spacing: 5) {
                Circle()
                    .fill(summary.isActive ? theme.costGreen : theme.textTertiary.opacity(0.6))
                    .frame(width: 6, height: 6)

                Text(summary.email)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let planLabel = compactPlanLabel {
                    Text(planLabel)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.geminiAccent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(theme.geminiAccent.opacity(0.14)))
                }

                Spacer(minLength: 4)

                let badge = statusBadge
                Text(badge.text)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(badge.foreground)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(badge.background))
            }

            // Second line: Quota & AI Credits
            Text(quotaAndCreditsLine)
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(summary.quotaInfo?.groups.isEmpty == false ? theme.textSecondary : theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Third line: Token Spend & Optional Credit Pool
            HStack(alignment: .center, spacing: 6) {
                Text(usageLine)
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                if summary.creditPool <= 0 && !isAddingPool {
                    Button {
                        draftPoolText = ""
                        isAddingPool = true
                    } label: {
                        Text("+ Track Credit $")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.linkBlue)
                    }
                    .buttonStyle(.plain)
                }
            }

            if summary.creditPool > 0 {
                let remainingFraction = max(0.0, min(1.0, summary.creditRemaining / summary.creditPool))
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(theme.progressTrack)
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(remainingFraction > 0.25 ? theme.costGreen : theme.claudeAccent)
                                .frame(width: max(0, geo.size.width * CGFloat(remainingFraction)))
                        }
                    }
                    .frame(height: 4)

                    HStack(spacing: 6) {
                        Text(String(format: "$%.2f left ($%.2f used)", summary.creditRemaining, summary.costSinceBaseline))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.costGreen)

                        Spacer()

                        Text("Pool $")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)

                        TextField(
                            "0",
                            value: Binding(
                                get: { summary.creditPool },
                                set: { viewModel.setAccountCreditPool($0, for: summary.email) }
                            ),
                            format: .number
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 9.5, design: .monospaced))
                        .frame(width: 56)
                        .multilineTextAlignment(.trailing)
                        .controlSize(.mini)

                        Button {
                            viewModel.resetAccountCreditBaseline(for: summary.email)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(theme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Reset credit usage baseline to now")

                        Button {
                            viewModel.setAccountCreditPool(0, for: summary.email)
                            isAddingPool = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9.5))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove credit pool tracking")
                    }
                }
                .padding(.top, 2)
            } else if isAddingPool {
                HStack(spacing: 6) {
                    Text("Credit Pool ($)")
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)

                    TextField("100", text: $draftPoolText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 9.5, design: .monospaced))
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                        .controlSize(.mini)
                        .onSubmit {
                            commitDraftPool()
                        }

                    Button("Save") {
                        commitDraftPool()
                    }
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.costGreen)
                    .buttonStyle(.plain)

                    Button("Cancel") {
                        isAddingPool = false
                    }
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    private func commitDraftPool() {
        let cleaned = draftPoolText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let val = Double(cleaned), val > 0 {
            viewModel.setAccountCreditPool(val, for: summary.email)
        }
        isAddingPool = false
    }
}
