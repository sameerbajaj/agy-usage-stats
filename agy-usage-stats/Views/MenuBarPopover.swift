//
//  MenuBarPopover.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import SwiftUI
import AppKit

public enum PopoverTab: String, CaseIterable, Identifiable {
    case stats = "Stats"
    case workspaces = "Workspaces"
    case history = "History"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .stats: return "chart.bar.fill"
        case .workspaces: return "folder.fill"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct MenuBarPopover: View {
    @Bindable public var viewModel: AgyStatsViewModel
    @State private var selectedTab: PopoverTab = .stats
    
    public init(viewModel: AgyStatsViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            header
            
            Group {
                switch selectedTab {
                case .stats:
                    StatsTabView(viewModel: viewModel)
                case .workspaces:
                    WorkspacesTabView(viewModel: viewModel)
                case .history:
                    HistoryTabView(viewModel: viewModel)
                case .settings:
                    SettingsTabView(viewModel: viewModel)
                }
            }
            .frame(height: 380)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
            
            Divider()
                .background(Color.white.opacity(0.12))
            
            footer
        }
        .frame(width: 350)
        .background(Color(red: 0.08, green: 0.08, blue: 0.10))
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.setup()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Logo & Title
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.55, green: 0.25, blue: 0.95), // Purple
                                             Color(red: 0.25, green: 0.65, blue: 1.0)], // Blue
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 28, height: 28)
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Antigravity")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                        Text("CLI Usage Stats")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                
                Spacer()
                
                // Refresh controls
                HStack(spacing: 8) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.white.opacity(0.7))
                    } else {
                        Button {
                            Task {
                                await viewModel.refresh()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .frame(width: 22, height: 22)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Refresh metrics")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            // Segmented Picker
            tabPicker
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            
            Divider()
                .background(Color.white.opacity(0.12))
        }
        .background(Color.white.opacity(0.02))
    }
    
    // MARK: - Tab Picker
    
    private var tabPicker: some View {
        HStack(spacing: 2) {
            ForEach(PopoverTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(
                        selectedTab == tab
                            ? Color.white
                            : Color.white.opacity(0.50)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                selectedTab == tab
                                    ? Color.white.opacity(0.12)
                                    : Color.clear
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.06))
        )
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            if let last = viewModel.stats.lastQueryAt {
                Text("Last active: \(formattedTime(last))")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.4))
            } else {
                Text("No queries recorded")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            
            Spacer()
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit App")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.red.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.01))
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
