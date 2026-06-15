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
    case cost = "Cost"
    case workspaces = "Workspaces"
    case history = "History"
    case settings = "Settings"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .stats: return "chart.bar.fill"
        case .cost: return "dollarsign.circle.fill"
        case .workspaces: return "folder.fill"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        }
    }
}

public struct MenuBarPopover: View {
    @Bindable public var viewModel: AgyStatsViewModel
    @State private var selectedTab: PopoverTab = .stats
    @Namespace private var namespace
    
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
                    .background(Color.white.opacity(0.02))
                    .overlay(
                        Rectangle()
                            .frame(height: 1)
                            .foregroundStyle(Color.white.opacity(0.05)),
                        alignment: .bottom
                    )
            }
            
            Group {
                switch selectedTab {
                case .stats:
                    StatsTabView(viewModel: viewModel)
                case .cost:
                    CostTabView(viewModel: viewModel)
                case .workspaces:
                    WorkspacesTabView(viewModel: viewModel)
                case .history:
                    HistoryTabView(viewModel: viewModel)
                case .settings:
                    SettingsTabView(viewModel: viewModel)
                }
            }
            .frame(height: 370)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: selectedTab)
            
            Divider()
                .background(Color.white.opacity(0.06))
            
            footer
        }
        .frame(width: 330)
        .background(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.setup()
        }
    }
    
    // MARK: - Header
    
    private var isConnected: Bool {
        let expanded = viewModel.cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let path = (expanded as NSString).appendingPathComponent("history.jsonl")
        return FileManager.default.fileExists(atPath: path)
    }
    
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Logo & Title
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(red: 0.65, green: 0.45, blue: 1.0), Color(red: 0.28, green: 0.68, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("antigravity")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Circle()
                        .fill(isConnected ? Color.green : Color.red)
                        .frame(width: 5, height: 5)
                        .opacity(0.85)
                }
                
                Spacer()
                
                // Refresh controls
                HStack(spacing: 8) {
                    if viewModel.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Color.white.opacity(0.5))
                    } else {
                        Button {
                            Task {
                                await viewModel.refresh()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.4))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            // Segmented Picker
            tabPicker
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            
            Divider()
                .background(Color.white.opacity(0.06))
        }
    }
    
    // MARK: - Tab Picker
    
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(PopoverTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 10))
                        Text(tab.rawValue.lowercased())
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(
                        selectedTab == tab
                            ? Color.white
                            : Color.white.opacity(0.35)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            if selectedTab == tab {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.05))
                                    .matchedGeometryEffect(id: "activeTabBackground", in: namespace)
                            }
                        }
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.02))
        )
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 8))
                if let last = viewModel.stats.lastQueryAt {
                    Text(formattedTime(last))
                } else {
                    Text("idle")
                }
            }
            .font(.system(size: 8.5, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.35))
            
            Spacer()
            
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.red.opacity(0.6))
                    .padding(4)
                    .background(
                        Circle()
                            .fill(Color.red.opacity(0.05))
                    )
            }
            .buttonStyle(.plain)
            .help("Quit App")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.005))
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
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
                            .foregroundStyle(.white)
                        Text("Installs automatically — no drag & drop")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.60))
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
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                }

            case .downloading(let progress):
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Downloading update…")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.green)
                    }
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .frame(width: 28, alignment: .trailing)
                }

            case .installing:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Installing — app will relaunch…")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
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
                            .foregroundStyle(.white)
                        Text(message)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.60))
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
