//
//  AgyFileWatcher.swift
//  agy-usage-stats
//
//  Created by Antigravity on 6/14/26.
//

import Foundation
import Observation

@Observable
public final class AgyFileWatcher {
    public var isWatching = false
    public var onFileChanged: (() -> Void)?
    public var cliDirOverride: String?
    
    private var timer: Timer?
    private var lastModified: Date?
    
    public var historyFilePath: String {
        let cliDir = cliDirOverride ?? AgyStatsService.getDefaultCliDir()
        let expanded = cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        return (expanded as NSString).appendingPathComponent("history.jsonl")
    }
    
    public init() {}
    
    public func start() {
        guard !isWatching else { return }
        isWatching = true
        lastModified = fileModificationDate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkFile()
        }
    }
    
    public func stop() {
        isWatching = false
        timer?.invalidate()
        timer = nil
    }
    
    private func checkFile() {
        let currentModified = fileModificationDate()
        if let current = currentModified, current != lastModified {
            lastModified = current
            onFileChanged?()
        }
    }
    
    private func fileModificationDate() -> Date? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: historyFilePath)
        return attrs?[.modificationDate] as? Date
    }
}
