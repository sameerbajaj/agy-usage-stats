//
//  HistoryTabView.swift
//  agy-usage-stats
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
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(searchIsFocused ? .blue : Color.primary.opacity(0.3))
                    .animation(.easeInOut(duration: 0.15), value: searchIsFocused)
                
                TextField("search history...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary)
                
                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(searchIsFocused ? Color.blue.opacity(0.25) : Color.primary.opacity(0.04), lineWidth: 0.75)
            )
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
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
            
            if filteredQueries.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass.bubble")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    Text("no matching queries found")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
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
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(query.display)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                    
                    if isHovered || copiedQueryID == query.id {
                        ZStack {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.green)
                                .scaleEffect(copiedQueryID == query.id ? 1.0 : 0.001)
                                .opacity(copiedQueryID == query.id ? 1.0 : 0.0)
                            
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .scaleEffect(copiedQueryID == query.id ? 0.001 : 1.0)
                                .opacity(copiedQueryID == query.id ? 0.0 : 1.0)
                        }
                        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: copiedQueryID == query.id)
                    }
                }
                
                HStack(spacing: 4) {
                    Text(query.cleanWorkspaceName)
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue.opacity(0.8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.blue.opacity(0.06)))
                    
                    if let type = query.type {
                        Text(type.lowercased())
                            .font(.system(size: 7.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.purple.opacity(0.8))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.purple.opacity(0.06)))
                    }
                    
                    Spacer()
                    
                    Text(formattedTime(query.timestamp))
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(isHovered ? 0.03 : 0.01))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(isHovered ? 0.05 : 0.02), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
