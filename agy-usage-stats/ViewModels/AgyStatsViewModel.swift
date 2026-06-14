//
//  AgyStatsViewModel.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import Foundation
import SwiftUI
import Observation
import AppKit

public enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable {
    case iconOnly = "Icon Only"
    case queriesToday = "Queries Today"
    case both = "Icon & Queries"
    
    public var id: String { rawValue }
}

@Observable
public final class AgyStatsViewModel {
    // Persistent settings using UserDefaults stored properties
    public var cliDir: String {
        didSet {
            UserDefaults.standard.set(cliDir, forKey: "agy_cliDir")
            restartWatcher()
            Task { await refresh() }
        }
    }
    
    public var menuBarDisplayMode: MenuBarDisplayMode {
        didSet {
            UserDefaults.standard.set(menuBarDisplayMode.rawValue, forKey: "agy_menuBarDisplayMode")
        }
    }
    
    // UI States
    public var stats: AgyUsageStats = .empty
    public var settings: AgySettings = .default
    public var isRefreshing = false
    public var searchQuery = String()
    
    // File Watcher
    private let watcher = AgyFileWatcher()
    
    public init() {
        // Load default values or fallback
        let savedCliDir = UserDefaults.standard.string(forKey: "agy_cliDir")
        self.cliDir = savedCliDir ?? AgyStatsService.getDefaultCliDir()
        
        let savedModeStr = UserDefaults.standard.string(forKey: "agy_menuBarDisplayMode")
        if let savedModeStr, let mode = MenuBarDisplayMode(rawValue: savedModeStr) {
            self.menuBarDisplayMode = mode
        } else {
            self.menuBarDisplayMode = .both
        }
    }
    
    public func setup() {
        // Start watching for file changes
        watcher.cliDirOverride = cliDir
        watcher.onFileChanged = { [weak self] in
            Task { [weak self] in
                await self?.refresh()
            }
        }
        watcher.start()
        
        // Initial load
        Task {
            await refresh()
        }
    }
    
    public func refresh() async {
        guard !isRefreshing else { return }
        
        await MainActor.run {
            isRefreshing = true
        }
        
        let (loadedStats, loadedSettings) = await AgyStatsService.loadStats(cliDir: cliDir)
        
        await MainActor.run {
            self.stats = loadedStats
            self.settings = loadedSettings
            self.isRefreshing = false
        }
    }
    
    private func restartWatcher() {
        watcher.stop()
        watcher.cliDirOverride = cliDir
        watcher.start()
    }
    
    deinit {
        watcher.stop()
    }
    
    // Helper actions
    public func revealInFinder() {
        let expanded = cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        let url = URL(fileURLWithPath: expanded)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }
}
