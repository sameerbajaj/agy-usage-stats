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
    @State private var isHoveredSpend = false
    @State private var isHoveredAppearance = false
    @State private var isHoveredSystem = false
    
    private var theme: ThemeColors { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme) }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Live Menu Bar Preview Mini-Card
                menuBarPreviewSection

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
