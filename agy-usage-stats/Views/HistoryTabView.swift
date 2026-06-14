//
//  HistoryTabView.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import SwiftUI
import AppKit

struct HistoryTabView: View {
    @Bindable var viewModel: AgyStatsViewModel
    @State private var copiedQueryID: String? = nil
    @State private var searchIsFocused = false
    
    var filteredQueries: [QueryEntry] {
        if viewModel.searchQuery.isEmpty {
            return viewModel.stats.recentQueries
        } else {
            return viewModel.stats.recentQueries.filter {
                $0.display.localizedCaseInsensitiveContains(viewModel.searchQuery) ||
                $0.workspace.localizedCaseInsensitiveContains(viewModel.searchQuery)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(searchIsFocused ? .blue : Color.white.opacity(0.35))
                    .animation(.easeInOut(duration: 0.15), value: searchIsFocused)
                
                TextField("Search history...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    // Custom focus trigger in swiftui can be simulated or we can rely on standard edit state
                    // We can track focus with standard SwiftUI @FocusState, but since we are targeting a wide range, simple text field is fine.
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(searchIsFocused ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .onReceive(NotificationCenter.default.publisher(for: NSTextView.didBeginEditingNotification)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    searchIsFocused = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSTextView.didEndEditingNotification)) { _ in
                withAnimation(.easeInOut(duration: 0.15)) {
                    searchIsFocused = false
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            if filteredQueries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass.bubble")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text("No matching queries found")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(filteredQueries) { query in
                            HistoryRow(query: query, copiedQueryID: copiedQueryID) {
                                copyToClipboard(text: query.display, id: query.id)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
    
    private func copyToClipboard(text: String, id: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
        
        withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
            copiedQueryID = id
        }
        
        // Reset checkmark after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedQueryID == id {
                withAnimation(.easeOut(duration: 0.2)) {
                    copiedQueryID = nil
                }
            }
        }
    }
}

struct HistoryRow: View {
    let query: QueryEntry
    let copiedQueryID: String?
    let onCopy: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button {
            onCopy()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(query.display)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                    
                    ZStack {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.green)
                            .scaleEffect(copiedQueryID == query.id ? 1.0 : 0.001)
                            .opacity(copiedQueryID == query.id ? 1.0 : 0.0)
                        
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(isHovered ? 0.6 : 0.3))
                            .scaleEffect(copiedQueryID == query.id ? 0.001 : 1.0)
                            .opacity(copiedQueryID == query.id ? 0.0 : 1.0)
                    }
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: copiedQueryID == query.id)
                }
                
                HStack(spacing: 6) {
                    // Workspace Badge
                    HStack(spacing: 3) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 7))
                        Text(query.cleanWorkspaceName)
                    }
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.12))
                    )
                    
                    if let type = query.type {
                        Text(type.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.purple.opacity(0.12))
                            )
                    }
                    
                    Spacer()
                    
                    Text(formattedTime(query.timestamp))
                        .font(.system(size: 8))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .padding(10)
            .premiumCardStyle(isHovered: isHovered, accentColor: .blue)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
