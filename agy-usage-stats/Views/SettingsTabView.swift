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
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Connection Status")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                
                Text(historyFileExists ? "Connected to Antigravity CLI" : "CLI Directory Not Found")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Menu Bar Settings
    
    private var menuBarSettingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu Bar View")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
            
            Picker("Display Style", selection: $viewModel.menuBarDisplayMode) {
                ForEach(MenuBarDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            Text("Choose whether to display the Antigravity icon, the number of queries run today, or both in your menu bar.")
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.4))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - File Path Settings
    
    private var filePathSettingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Antigravity CLI Data Path")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
            
            if isEditingDir {
                HStack(spacing: 8) {
                    TextField("CLI Path", text: $tempDir)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                    
                    Button("Save") {
                        viewModel.cliDir = tempDir
                        isEditingDir = false
                    }
                    .font(.system(size: 10, weight: .semibold))
                    
                    Button("Cancel") {
                        isEditingDir = false
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .font(.system(size: 10))
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
                    .font(.system(size: 10, weight: .semibold))
                }
            }
            
            HStack {
                Button(action: viewModel.revealInFinder) {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text("Show in Finder")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}
