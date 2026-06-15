//
//  WorkspacesTabView.swift
//  agy-usage-stats
//

import SwiftUI
import AppKit

struct WorkspacesTabView: View {
    let viewModel: AgyStatsViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("active workspaces")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.stats.workspaces.count) total")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 6)
            
            if viewModel.stats.workspaces.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("no workspaces tracked")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
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
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(ws.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.9))
                    
                    Text(formattedTime(ws.lastActiveAt))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                
                Text(ws.path)
                    .font(.system(size: 8, weight: .medium).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Text("\(ws.queryCount)q")
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.primary.opacity(0.06))
                    )
                
                if isHovered {
                    Button {
                        onReveal()
                    } label: {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.blue.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(isHovered ? 0.03 : 0.01))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(isHovered ? 0.05 : 0.02), lineWidth: 0.5)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
