//
//  ActivityTabView.swift
//  agy-usage-stats
//
//  Created by Antigravity on 10/17/26.
//

import SwiftUI
import AppKit

public struct ActivityTabView: View {
    @Bindable var viewModel: AgyStatsViewModel
    @Environment(\.colorScheme) var colorScheme
    
    @State private var selectedWorkspace: String? = nil
    @State private var copiedQueryID: String? = nil
    @State private var searchIsFocused = false
    
    private var isDark: Bool { colorScheme == .dark }
    private var theme: ThemeColors { ThemeColors.colors(for: viewModel.selectedTheme, colorScheme: colorScheme) }
    
    public init(viewModel: AgyStatsViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Filtered Queries
    
    private var filteredQueries: [QueryEntry] {
        var list = viewModel.stats.recentQueries
        
        // Filter by workspace
        if let ws = selectedWorkspace {
            list = list.filter {
                $0.cleanWorkspaceName == ws || $0.workspace.contains(ws)
            }
        }
        
        // Filter by search query
        if !viewModel.searchQuery.isEmpty {
            let term = viewModel.searchQuery
            list = list.filter {
                $0.display.localizedCaseInsensitiveContains(term) ||
                $0.workspace.localizedCaseInsensitiveContains(term) ||
                $0.billingBadge.localizedCaseInsensitiveContains(term) ||
                ($0.modelName?.localizedCaseInsensitiveContains(term) ?? false)
            }
        }
        
        return list
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Search Input
            searchBar
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 6)
            
            // Workspace Filter Pills
            workspaceFilterBar
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            
            Rectangle()
                .fill(theme.divider)
                .frame(height: 1)
            
            // Query Stream
            if filteredQueries.isEmpty {
                emptyState
            } else {
                queryList
            }
        }
        .background(theme.surfacePrimary)
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(searchIsFocused ? theme.linkBlue : theme.textTertiary)
            
            TextField("search queries, workspaces, models...", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.primary)
            
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(theme.searchBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(searchIsFocused ? theme.searchBorderFocused : theme.cardStroke, lineWidth: 0.75)
        )
    }
    
    // MARK: - Workspace Filter Bar
    
    private var workspaceFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // All Pill
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        selectedWorkspace = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("All")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        Text("\(viewModel.stats.recentQueries.count)")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    .foregroundStyle(selectedWorkspace == nil ? Color.primary : Color.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(selectedWorkspace == nil ? theme.cardFillHovered : theme.surfaceSecondary)
                    )
                    .overlay(
                        Capsule()
                            .stroke(selectedWorkspace == nil ? theme.geminiAccent.opacity(0.5) : Color.clear, lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)
                
                // Individual Workspaces
                ForEach(viewModel.stats.workspaces) { ws in
                    let isSelected = selectedWorkspace == ws.name
                    HStack(spacing: 3) {
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                selectedWorkspace = isSelected ? nil : ws.name
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(ws.name)
                                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                Text("\(ws.queryCount)q")
                                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 3.5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Finder reveal button
                        Button {
                            revealInFinder(path: ws.path)
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal \(ws.name) in Finder")
                    }
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(isSelected ? theme.cardFillHovered : theme.surfaceSecondary)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? theme.geminiAccent.opacity(0.5) : Color.clear, lineWidth: 0.75)
                    )
                }
            }
            .padding(.vertical, 1)
        }
    }
    
    // MARK: - Query List
    
    private var queryList: some View {
        ScrollView {
            LazyVStack(spacing: 5) {
                ForEach(filteredQueries) { query in
                    ActivityQueryRow(
                        query: query,
                        isCopied: copiedQueryID == query.id,
                        theme: theme
                    ) {
                        copyToClipboard(text: query.display, id: query.id)
                    }
                }
            }
            .padding(10)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 18))
                .foregroundStyle(theme.textTertiary)
            Text("no queries match filter")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Clipboard & Finder
    
    private func copyToClipboard(text: String, id: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            copiedQueryID = id
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedQueryID == id {
                withAnimation(.easeOut(duration: 0.2)) {
                    copiedQueryID = nil
                }
            }
        }
    }
    
    private func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}

// MARK: - Activity Query Row Component

struct ActivityQueryRow: View {
    let query: QueryEntry
    let isCopied: Bool
    let theme: ThemeColors
    let onCopy: () -> Void
    
    @State private var isHovered = false
    
    private var modelBadgeText: String {
        guard let name = query.modelName else { return "Query" }
        return canonicalModelDisplayName(from: name)
    }
    
    private var modelBadgeColor: Color {
        let lower = (query.modelName ?? "").lowercased()
        if lower.contains("argon") || lower.contains("gemini") {
            return theme.geminiAccent
        } else if lower.contains("claude") || lower.contains("opus") || lower.contains("sonnet") {
            return theme.claudeAccent
        }
        return theme.textSecondary
    }
    
    var body: some View {
        Button {
            onCopy()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // Header tags row
                HStack(spacing: 4) {
                    // Model Tag
                    Text(modelBadgeText)
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundStyle(modelBadgeColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(modelBadgeColor.opacity(0.12)))
                    
                    // Workspace Tag
                    Text(query.cleanWorkspaceName)
                        .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(theme.badgeBackground))
                    
                    Spacer()
                    
                    if isCopied {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 7, weight: .bold))
                            Text("Copied!")
                                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(theme.costGreen)
                    } else {
                        Text(formattedTime(query.timestamp))
                            .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                
                // Query Text Display
                Text(query.display)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? theme.cardFillHovered : theme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isHovered ? theme.cardStrokeHovered : theme.cardStroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
    
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    
    private func formattedTime(_ date: Date) -> String {
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
