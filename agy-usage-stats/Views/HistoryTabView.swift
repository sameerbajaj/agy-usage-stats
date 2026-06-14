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
    @State private var hoveringQueryID: String? = nil
    @State private var copiedQueryID: String? = nil
    
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
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.4))
                
                TextField("Search history...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                
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
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.06))
            .cornerRadius(6)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            Divider()
                .background(Color.white.opacity(0.08))
            
            if filteredQueries.isEmpty {
                Spacer()
                Text("No matching queries found")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.3))
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(filteredQueries) { query in
                            Button {
                                copyToClipboard(text: query.display, id: query.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .top) {
                                        Text(query.display)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white)
                                            .multilineTextAlignment(.leading)
                                            .lineLimit(3)
                                            .fixedSize(horizontal: false, vertical: true)
                                        
                                        Spacer()
                                        
                                        // Copy indicator
                                        Image(systemName: copiedQueryID == query.id ? "checkmark.circle.fill" : "doc.on.doc")
                                            .font(.system(size: 10))
                                            .foregroundStyle(copiedQueryID == query.id ? Color.green : Color.white.opacity(0.35))
                                    }
                                    
                                    HStack {
                                        // Workspace folder badge
                                        Text(query.cleanWorkspaceName)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(Color.blue)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.12))
                                            .cornerRadius(4)
                                        
                                        if let type = query.type {
                                            Text(type.uppercased())
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(Color.purple)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.purple.opacity(0.12))
                                                .cornerRadius(4)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(formattedTime(query.timestamp))
                                            .font(.system(size: 8))
                                            .foregroundStyle(Color.white.opacity(0.4))
                                    }
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.white.opacity(hoveringQueryID == query.id ? 0.04 : 0.015))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(hoveringQueryID == query.id ? 0.08 : 0.04), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .onHover { isHovering in
                                hoveringQueryID = isHovering ? query.id : nil
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }
    
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func copyToClipboard(text: String, id: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        pasteboard.setString(text, forType: .string)
        
        withAnimation {
            copiedQueryID = id
        }
        
        // Reset checkmark after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedQueryID == id {
                withAnimation {
                    copiedQueryID = nil
                }
            }
        }
    }
}
