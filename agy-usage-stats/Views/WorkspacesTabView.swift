//
//  WorkspacesTabView.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import SwiftUI
import AppKit

struct WorkspacesTabView: View {
    let viewModel: AgyStatsViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Active Workspaces")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Text("\(viewModel.stats.workspaces.count) total")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.01))
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            if viewModel.stats.workspaces.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text("No workspaces tracked yet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.stats.workspaces) { ws in
                            WorkspaceRow(ws: ws) {
                                revealInFinder(path: ws.path)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
    
    private func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}

struct WorkspaceRow: View {
    let ws: WorkspaceStats
    let onReveal: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Folder icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(isHovered ? 0.18 : 0.12))
                    .frame(width: 30, height: 30)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
                
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.blue)
                    .shadow(color: .blue.opacity(isHovered ? 0.5 : 0.0), radius: 4)
            }
            
            // Text details
            VStack(alignment: .leading, spacing: 2) {
                Text(ws.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(ws.path)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Text("Last active: \(formattedTime(ws.lastActiveAt))")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            
            Spacer()
            
            // Stats count + actions
            HStack(spacing: 8) {
                Text("\(ws.queryCount) \(ws.queryCount == 1 ? "query" : "queries")")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
                
                Button {
                    onReveal()
                } label: {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(isHovered ? Color.blue : Color.white.opacity(0.4))
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                }
                .buttonStyle(.plain)
                .help("Reveal folder in Finder")
            }
        }
        .padding(10)
        .premiumCardStyle(isHovered: isHovered, accentColor: .blue)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
