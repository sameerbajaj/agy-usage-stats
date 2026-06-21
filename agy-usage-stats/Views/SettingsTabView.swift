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
    
    @State private var isHoveredMenu = false
    @State private var isHoveredPath = false
    @State private var isHoveredUpdates = false
    @State private var isHoveredAppearance = false
    
    private var theme: ThemeColors { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme) }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Section 0: Appearance
                appearanceSection
                
                // Section 1: Menu Bar Settings
                menuBarSection
                
                // Section 2: Data Path Settings
                dataPathSection
                
                // Section 3: Updates Settings
                updatesSection
            }
            .padding(12)
        }
        .background(theme.surfacePrimary)
    }
    
    // MARK: - Appearance Settings
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("appearance")
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
            }
            .padding(10)
            .themedCardStyle(theme: theme, isHovered: isHoveredAppearance)
            .onHover { h in isHoveredAppearance = h }
        }
    }
    
    // MARK: - Menu Bar View Settings
    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("menu bar display")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                HStack {
                    Text("Display Mode")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.textPrimary.opacity(0.85))
                    Spacer()
                    Picker("", selection: $viewModel.menuBarDisplayMode) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }
                
                Rectangle().fill(theme.divider).frame(height: 0.75)
                
                HStack {
                    Text("Show Usage % in Icon")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.textPrimary.opacity(0.85))
                    Spacer()
                    Toggle("", isOn: $viewModel.showModelUsageInIcon.animation(.easeInOut(duration: 0.2)))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                
                if viewModel.showModelUsageInIcon {
                    HStack {
                        Text("Model for Icon")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.leading, 8)
                        Spacer()
                        Picker("", selection: $viewModel.selectedModelForIcon) {
                            ForEach(IconModelSelection.allCases) { sel in
                                Text(sel.rawValue).tag(sel)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .controlSize(.small)
                    }

                    HStack {
                        Text("Quota Limit for Icon")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.leading, 8)
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

                    HStack {
                        Text("Circle Fill Completion")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(theme.textSecondary)
                            .padding(.leading, 8)
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
                
                Rectangle().fill(theme.divider).frame(height: 0.75)
                
                HStack {
                    Text("Show Weekly Limit & Reset")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(theme.textPrimary.opacity(0.85))
                    Spacer()
                    Toggle("", isOn: $viewModel.showWeeklyLimitAndReset)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }
            .padding(10)
            .themedCardStyle(theme: theme, isHovered: isHoveredMenu)
            .onHover { h in isHoveredMenu = h }
        }
    }
    
    // MARK: - Data Path Settings
    private var dataPathSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("cli data path")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
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
            }
            .padding(10)
            .themedCardStyle(theme: theme, isHovered: isHoveredPath)
            .onHover { h in isHoveredPath = h }
        }
    }
    
    // MARK: - App Updates Settings
    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("application updates")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
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
            .themedCardStyle(theme: theme, isHovered: isHoveredUpdates)
            .onHover { h in isHoveredUpdates = h }
        }
    }
}
