//
//  MenuBarPopover.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import SwiftUI
import AppKit

public enum PopoverTab: String, CaseIterable, Identifiable {
    case usage = "Usage & Cost"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .usage: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct MenuBarPopover: View {
    @Bindable public var viewModel: AgyStatsViewModel
    @State private var selectedTab: PopoverTab = .usage
    @State private var isRefreshHovered = false
    @State private var isGearHovered = false
    @Environment(\.colorScheme) var colorScheme
    private var theme: ThemeColors { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme) }
    
    public init(viewModel: AgyStatsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            header
            
            if let update = viewModel.availableUpdate {
                updateBanner(update)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.surfaceSecondary)
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(theme.divider),
                        alignment: .bottom
                    )
            }
            
            Group {
                switch selectedTab {
                case .usage:
                    OverviewTabView(viewModel: viewModel)
                case .settings:
                    SettingsTabView(viewModel: viewModel) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = .usage
                        }
                    }
                }
            }
            .frame(height: 540)
            .background(theme.surfacePrimary)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
            
            footer
        }
        .frame(width: 380)
        .background(theme.surfacePrimary)
        .preferredColorScheme(viewModel.selectedTheme.preferredColorScheme)
        .environment(\.colorScheme, viewModel.selectedTheme.preferredColorScheme)
        .onAppear {
            viewModel.setup()
            Task {
                await viewModel.refreshQuotaOnly(forceRefresh: true)
            }
        }
    }
    
    // MARK: - Header
    
    private var isConnected: Bool {
        viewModel.isConnected
    }
    
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Logo & Title
                HStack(spacing: 5) {
                    Circle()
                        .fill(isConnected ? theme.costGreen : theme.dangerRed)
                        .frame(width: 6, height: 6)

                    Text("AGY")
                        .font(.system(size: 11.5, weight: .black, design: .monospaced))
                        .foregroundStyle(theme.textPrimary)
                    
                    Text("usage stats")
                        .font(.system(size: 11.5, weight: .light, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                }
                
                Spacer()
                
                // Refresh & Settings Gear controls
                HStack(spacing: 4) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 24, height: 24)
                    } else {
                        Button {
                            Task {
                                await viewModel.refresh()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(isRefreshHovered ? theme.textPrimary : theme.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isRefreshHovered ? theme.surfaceSecondary : Color.clear)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .onHover { isRefreshHovered = $0 }
                        .help("Refresh telemetry")
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = (selectedTab == .settings) ? .usage : .settings
                        }
                    } label: {
                        let isSettingsActive = (selectedTab == .settings)
                        Image(systemName: isSettingsActive ? "gearshape.fill" : "gearshape")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(
                                isSettingsActive
                                    ? theme.geminiAccent
                                    : (isGearHovered ? theme.textPrimary : theme.textSecondary)
                            )
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        isSettingsActive
                                            ? theme.geminiAccent.opacity(0.14)
                                            : (isGearHovered ? theme.surfaceSecondary : Color.clear)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSettingsActive ? theme.geminiAccent.opacity(0.35) : Color.clear, lineWidth: 0.75)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .onHover { isGearHovered = $0 }
                    .help(selectedTab == .settings ? "Back to usage" : "Settings")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            
            // Theme-aware divider
            Rectangle()
                .fill(theme.divider)
                .frame(height: 1)
        }
        .background(theme.surfacePrimary)
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.divider).frame(height: 1)
            
            HStack {
                HStack(spacing: 4) {
                    Text("SYS.STATUS:")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                    
                    if let last = viewModel.stats.lastQueryAt {
                        Text(formattedTime(last).uppercased())
                            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                    } else {
                        Text("IDLE")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                
                Spacer()
                
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("SHUTDOWN")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.dangerRed)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(theme.dangerRed.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(theme.dangerRed.opacity(0.18), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(theme.surfacePrimary)
    }
    
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    
    private func formattedTime(_ date: Date) -> String {
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Update Banner View Helper
    
    private func updateBanner(_ update: UpdateInfo) -> some View {
        VStack(spacing: 0) {
            switch viewModel.selfUpdateState {
            case .idle:
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.18))
                            .frame(width: 24, height: 24)
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(update.isRolling ? "New build available" : "Update available — v\(update.version)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Installs automatically — no drag & drop")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if update.downloadURL != nil {
                        Button { viewModel.installUpdate() } label: {
                            Text("Install")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.green))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { NSWorkspace.shared.open(update.releaseURL) } label: {
                            Text("Download")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.green))
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: { viewModel.dismissUpdate() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

            case .downloading(let progress):
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Downloading update…")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.primary)
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.green)
                    }
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 28, alignment: .trailing)
                }

            case .installing:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Installing — app will relaunch…")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }

            case .failed(let message):
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Update failed")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(message)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button {
                        viewModel.selfUpdateState = .idle
                    } label: {
                        Text("Retry")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
