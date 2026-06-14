//
//  SettingsTabView.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import SwiftUI
import AppKit

struct SettingsTabView: View {
    @Bindable var viewModel: AgyStatsViewModel
    @State private var isEditingDir = false
    @State private var tempDir = ""
    
    @State private var healthCardHovered = false
    @State private var menuBarCardHovered = false
    @State private var pathCardHovered = false
    
    var historyFileExists: Bool {
        let expanded = viewModel.cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let path = (expanded as NSString).appendingPathComponent("history.jsonl")
        return FileManager.default.fileExists(atPath: path)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Section 1: Connection Health Status
                connectionHealthCard
                
                // Section 2: Menu Bar Display Settings
                menuBarSettingsCard
                
                // Section 3: File Path Settings
                filePathSettingsCard
                
                Spacer()
            }
            .padding(12)
        }
    }
    
    // MARK: - Connection Health
    
    private var connectionHealthCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(historyFileExists ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                    .frame(width: 32, height: 32)
                
                Image(systemName: historyFileExists ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(historyFileExists ? Color.green : Color.red)
                    .shadow(color: (historyFileExists ? Color.green : Color.red).opacity(healthCardHovered ? 0.6 : 0.0), radius: 4)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("CONNECTION STATUS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.45))
                
                Text(historyFileExists ? "Connected to Antigravity CLI" : "CLI Directory Not Found")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            Spacer()
        }
        .padding(12)
        .premiumCardStyle(isHovered: healthCardHovered, accentColor: historyFileExists ? .green : .red)
        .onHover { hovering in
            healthCardHovered = hovering
        }
    }
    
    // MARK: - Menu Bar Settings
    
    private var menuBarSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Menu Bar View")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Picker("", selection: $viewModel.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
            }
            
            Text("Choose whether to display the Antigravity icon, remaining quotas (Gemini & Claude), the number of queries run today, or combinations in your menu bar.")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 2)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Usage % in Icon")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Render the remaining usage % directly inside the menu bar icon.")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
                Toggle("", isOn: $viewModel.showModelUsageInIcon.animation(.easeInOut(duration: 0.2)))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
            
            if viewModel.showModelUsageInIcon {
                HStack {
                    Text("Model for Icon")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.leading, 10)
                    Spacer()
                    Picker("", selection: $viewModel.selectedModelForIcon) {
                        ForEach(IconModelSelection.allCases) { sel in
                            Text(sel.rawValue).tag(sel)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .padding(.bottom, 2)
            }
            
            Divider()
                .background(Color.white.opacity(0.08))
                .padding(.vertical, 2)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Weekly Limit & Reset")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Display the weekly quota % remaining and the time until reset in the menu bar text.")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
                Toggle("", isOn: $viewModel.showWeeklyLimitAndReset)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
        .padding(12)
        .premiumCardStyle(isHovered: menuBarCardHovered, accentColor: .blue)
        .onHover { hovering in
            menuBarCardHovered = hovering
        }
    }
    
    // MARK: - File Path Settings
    
    private var filePathSettingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Antigravity CLI Data Path")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
            
            if isEditingDir {
                HStack(spacing: 8) {
                    TextField("CLI Path", text: $tempDir)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(.white)
                    
                    Button("Save") {
                        viewModel.cliDir = tempDir
                        isEditingDir = false
                    }
                    .font(.system(size: 10, weight: .bold))
                    
                    Button("Cancel") {
                        isEditingDir = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .font(.system(size: 10, weight: .medium))
                }
            } else {
                HStack(spacing: 8) {
                    Text(viewModel.cliDir)
                        .font(.system(size: 11).monospaced())
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Button("Edit") {
                        tempDir = viewModel.cliDir
                        isEditingDir = true
                    }
                    .font(.system(size: 10, weight: .bold))
                }
            }
            
            HStack {
                Button(action: viewModel.revealInFinder) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .bold))
                        Text("Show in Finder")
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(12)
        .premiumCardStyle(isHovered: pathCardHovered, accentColor: .blue)
        .onHover { hovering in
            pathCardHovered = hovering
        }
    }
}
