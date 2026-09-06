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
    
    private struct FileWatcherSignature: Equatable {
        let histMod: Date?
        let histSize: Int64?
        let dirMod: Date?
    }
    
    private let queue = DispatchQueue(label: "com.antigravity.agy-usage-stats.filewatcher", qos: .utility)
    private var timerSource: DispatchSourceTimer?
    private var historySource: DispatchSourceFileSystemObject?
    private var convDirSource: DispatchSourceFileSystemObject?
    private var historyFd: Int32 = -1
    private var convDirFd: Int32 = -1
    private var lastSignature: FileWatcherSignature?
    private var debounceWorkItem: DispatchWorkItem?
    
    public var historyFilePath: String {
        let cliDir = cliDirOverride ?? AgyStatsService.getDefaultCliDir()
        let expanded = cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        return (expanded as NSString).appendingPathComponent("history.jsonl")
    }
    
    public var conversationsDirPath: String {
        let cliDir = cliDirOverride ?? AgyStatsService.getDefaultCliDir()
        let expanded = cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
        return (expanded as NSString).appendingPathComponent("conversations")
    }
    
    public init() {}
    
    public func start() {
        guard !isWatching else { return }
        isWatching = true
        
        queue.async { [weak self] in
            guard let self = self else { return }
            self.lastSignature = self.currentSignature()
            
            // 1. Kernel-level kqueue notifications for history.jsonl
            let histPath = self.historyFilePath
            let hFd = open(histPath, O_EVTONLY)
            if hFd >= 0 {
                self.historyFd = hFd
                let hSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: hFd, eventMask: [.write, .extend, .attrib], queue: self.queue)
                hSource.setEventHandler { [weak self] in
                    self?.checkFile()
                }
                hSource.setCancelHandler {
                    close(hFd)
                }
                self.historySource = hSource
                hSource.resume()
            }
            
            // 2. Kernel-level kqueue notifications for conversations directory
            let dirPath = self.conversationsDirPath
            let dFd = open(dirPath, O_EVTONLY)
            if dFd >= 0 {
                self.convDirFd = dFd
                let dSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dFd, eventMask: [.write, .extend, .attrib, .link], queue: self.queue)
                dSource.setEventHandler { [weak self] in
                    self?.checkFile()
                }
                dSource.setCancelHandler {
                    close(dFd)
                }
                self.convDirSource = dSource
                dSource.resume()
            }
            
            // 3. Low-overhead background fallback timer (4.0s)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 4.0, repeating: 4.0)
            timer.setEventHandler { [weak self] in
                self?.checkFile()
            }
            self.timerSource = timer
            timer.resume()
        }
    }
    
    public func stop() {
        isWatching = false
        queue.async { [weak self] in
            self?.timerSource?.cancel()
            self?.timerSource = nil
            self?.historySource?.cancel()
            self?.historySource = nil
            self?.convDirSource?.cancel()
            self?.convDirSource = nil
            self?.historyFd = -1
            self?.convDirFd = -1
            self?.debounceWorkItem?.cancel()
            self?.debounceWorkItem = nil
        }
    }
    
    private func checkFile() {
        let current = currentSignature()
        if current != lastSignature {
            lastSignature = current
            debounceWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                DispatchQueue.main.async {
                    self?.onFileChanged?()
                }
            }
            debounceWorkItem = workItem
            queue.asyncAfter(deadline: .now() + 1.5, execute: workItem)
        }
    }
    
    private func currentSignature() -> FileWatcherSignature {
        let fm = FileManager.default
        let histAttrs = try? fm.attributesOfItem(atPath: historyFilePath)
        let histMod = histAttrs?[.modificationDate] as? Date
        let histSize = (histAttrs?[.size] as? NSNumber)?.int64Value
        
        let dirAttrs = try? fm.attributesOfItem(atPath: conversationsDirPath)
        let dirMod = dirAttrs?[.modificationDate] as? Date
        
        return FileWatcherSignature(histMod: histMod, histSize: histSize, dirMod: dirMod)
    }
}
