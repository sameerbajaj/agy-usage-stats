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
    @State private var hoveringWorkspaceID: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Active Workspaces")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer()
                Text("\(viewModel.stats.workspaces.count) total")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.02))
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            if viewModel.stats.workspaces.isEmpty {
                Spacer()
                Text("No workspaces tracked yet")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.3))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.stats.workspaces) { ws in
                            HStack(spacing: 12) {
                                // Folder icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.blue.opacity(0.12))
                                        .frame(width: 28, height: 28)
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.blue)
                                }
                                
                                // Text details
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ws.name)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    
                                    Text(ws.path)
                                        .font(.system(size: 9))
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
                                    Text("\(ws.queryCount) q")
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(Color.white.opacity(0.7))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(Color.white.opacity(0.06))
                                        )
                                    
                                    Button {
                                        revealInFinder(path: ws.path)
                                    } label: {
                                        Image(systemName: "arrow.right.circle.fill")
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.blue.opacity(hoveringWorkspaceID == ws.id ? 1.0 : 0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Reveal folder in Finder")
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(hoveringWorkspaceID == ws.id ? 0.04 : 0.015))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(hoveringWorkspaceID == ws.id ? 0.08 : 0.04), lineWidth: 1)
                            )
                            .onHover { isHovering in
                                withAnimation(.easeOut(duration: 0.1)) {
                                    hoveringWorkspaceID = isHovering ? ws.id : nil
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}
