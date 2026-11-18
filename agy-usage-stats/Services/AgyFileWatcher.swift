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
        let convContentSig: AgyStatsService.DirectoryContentSignature
        let gcpHistMod: Date?
        let gcpHistSize: Int64?
        let gcpDirMod: Date?
        let gcpConvContentSig: AgyStatsService.DirectoryContentSignature
        let cliLogTargetPath: String?
        let activeConsumerEmail: String?
        let oauthTokenMod: Date?
    }
    
    private let queue = DispatchQueue(label: "com.antigravity.agy-usage-stats.filewatcher", qos: .utility)
    private var timerSource: DispatchSourceTimer?
    private var historySource: DispatchSourceFileSystemObject?
    private var gcpHistorySource: DispatchSourceFileSystemObject?
    private var convDirSource: DispatchSourceFileSystemObject?
    private var gcpConvDirSource: DispatchSourceFileSystemObject?
    private var logDirSource: DispatchSourceFileSystemObject?
    private var cliLogSource: DispatchSourceFileSystemObject?
    private var cliDirSource: DispatchSourceFileSystemObject?
    private var historyFd: Int32 = -1
    private var gcpHistoryFd: Int32 = -1
    private var convDirFd: Int32 = -1
    private var gcpConvDirFd: Int32 = -1
    private var logDirFd: Int32 = -1
    private var cliLogFd: Int32 = -1
    private var cliDirFd: Int32 = -1
    private var watchedCliLogTargetPath: String?
    private var lastSignature: FileWatcherSignature?
    private var debounceWorkItem: DispatchWorkItem?

    private var expandedCliDir: String {
        let cliDir = cliDirOverride ?? AgyStatsService.getDefaultCliDir()
        return cliDir.replacingOccurrences(of: "~", with: NSHomeDirectory())
    }
    
    public var historyFilePath: String {
        return (expandedCliDir as NSString).appendingPathComponent("history.jsonl")
    }
    
    public var gcpHistoryFilePath: String {
        return "\(NSHomeDirectory())/.agy-gcp-home/.gemini/antigravity-cli/history.jsonl"
    }
    
    public var conversationsDirPath: String {
        return (expandedCliDir as NSString).appendingPathComponent("conversations")
    }
    
    public var gcpConversationsDirPath: String {
        return "\(NSHomeDirectory())/.agy-gcp-home/.gemini/antigravity-cli/conversations"
    }

    public var logDirPath: String {
        return (expandedCliDir as NSString).appendingPathComponent("log")
    }

    public var cliLogFilePath: String {
        return (expandedCliDir as NSString).appendingPathComponent("cli.log")
    }

    public var oauthTokenFilePath: String {
        return (expandedCliDir as NSString).appendingPathComponent("antigravity-oauth-token")
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
            
            // 2. Kernel-level kqueue notifications for GCP box history.jsonl
            let gcpPath = self.gcpHistoryFilePath
            let gFd = open(gcpPath, O_EVTONLY)
            if gFd >= 0 {
                self.gcpHistoryFd = gFd
                let gSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: gFd, eventMask: [.write, .extend, .attrib], queue: self.queue)
                gSource.setEventHandler { [weak self] in
                    self?.checkFile()
                }
                gSource.setCancelHandler {
                    close(gFd)
                }
                self.gcpHistorySource = gSource
                gSource.resume()
            }
            
            // 3. Kernel-level kqueue notifications for conversations directory
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
            
            // 4. Kernel-level kqueue notifications for GCP conversations directory
            let gcpDirPath = self.gcpConversationsDirPath
            let gdFd = open(gcpDirPath, O_EVTONLY)
            if gdFd >= 0 {
                self.gcpConvDirFd = gdFd
                let gdSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: gdFd, eventMask: [.write, .extend, .attrib, .link], queue: self.queue)
                gdSource.setEventHandler { [weak self] in
                    self?.checkFile()
                }
                gdSource.setCancelHandler {
                    close(gdFd)
                }
                self.gcpConvDirSource = gdSource
                gdSource.resume()
            }

            // 5. Kernel-level kqueue notifications for log directory (/login & OAuth switches)
            let logPath = self.logDirPath
            let lFd = open(logPath, O_EVTONLY)
            if lFd >= 0 {
                self.logDirFd = lFd
                let lSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: lFd, eventMask: [.write, .extend, .attrib, .link], queue: self.queue)
                lSource.setEventHandler { [weak self] in
                    self?.checkFile()
                }
                lSource.setCancelHandler {
                    close(lFd)
                }
                self.logDirSource = lSource
                lSource.resume()
            }

            // 6. Kernel-level kqueue notifications for cliDir (antigravity-oauth-token / cli.log symlink updates)
            let cliRootPath = self.expandedCliDir
            let cFd = open(cliRootPath, O_EVTONLY)
            if cFd >= 0 {
                self.cliDirFd = cFd
                let cSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: cFd, eventMask: [.write, .extend, .attrib, .link], queue: self.queue)
                cSource.setEventHandler { [weak self] in
                    self?.checkFile()
                }
                cSource.setCancelHandler {
                    close(cFd)
                }
                self.cliDirSource = cSource
                cSource.resume()
            }

            // 7. Kernel-level kqueue notifications for cli.log target file
            self.rebindCliLogSourceIfNeeded()
            
            // 8. Low-overhead background fallback timer (15.0s with 3s leeway)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 15.0, repeating: 15.0, leeway: .seconds(3))
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
            self?.gcpHistorySource?.cancel()
            self?.gcpHistorySource = nil
            self?.convDirSource?.cancel()
            self?.convDirSource = nil
            self?.gcpConvDirSource?.cancel()
            self?.gcpConvDirSource = nil
            self?.logDirSource?.cancel()
            self?.logDirSource = nil
            self?.cliLogSource?.cancel()
            self?.cliLogSource = nil
            self?.cliDirSource?.cancel()
            self?.cliDirSource = nil
            self?.historyFd = -1
            self?.gcpHistoryFd = -1
            self?.convDirFd = -1
            self?.gcpConvDirFd = -1
            self?.logDirFd = -1
            self?.cliLogFd = -1
            self?.cliDirFd = -1
            self?.watchedCliLogTargetPath = nil
            self?.debounceWorkItem?.cancel()
            self?.debounceWorkItem = nil
        }
    }

    private func rebindCliLogSourceIfNeeded() {
        let resolved = URL(fileURLWithPath: cliLogFilePath).resolvingSymlinksInPath().path
        if resolved == watchedCliLogTargetPath && cliLogSource != nil {
            return
        }
        cliLogSource?.cancel()
        cliLogSource = nil
        cliLogFd = -1
        watchedCliLogTargetPath = nil

        let fd = open(resolved, O_EVTONLY)
        if fd >= 0 {
            cliLogFd = fd
            watchedCliLogTargetPath = resolved
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .attrib], queue: queue)
            source.setEventHandler { [weak self] in
                self?.checkFile()
            }
            source.setCancelHandler {
                close(fd)
            }
            cliLogSource = source
            source.resume()
        }
    }
    
    private func checkFile() {
        rebindCliLogSourceIfNeeded()
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
            queue.asyncAfter(deadline: .now() + 0.3, execute: workItem)
        }
    }
    
    private func currentSignature() -> FileWatcherSignature {
        let fm = FileManager.default
        let histAttrs = try? fm.attributesOfItem(atPath: historyFilePath)
        let histMod = histAttrs?[.modificationDate] as? Date
        let histSize = (histAttrs?[.size] as? NSNumber)?.int64Value
        
        let dirAttrs = try? fm.attributesOfItem(atPath: conversationsDirPath)
        let dirMod = dirAttrs?[.modificationDate] as? Date
        let convContentSig = AgyStatsService.directoryContentSignature(atPath: conversationsDirPath)
        
        let gcpAttrs = try? fm.attributesOfItem(atPath: gcpHistoryFilePath)
        let gcpMod = gcpAttrs?[.modificationDate] as? Date
        let gcpSize = (gcpAttrs?[.size] as? NSNumber)?.int64Value
        
        let gcpDirAttrs = try? fm.attributesOfItem(atPath: gcpConversationsDirPath)
        let gcpDirMod = gcpDirAttrs?[.modificationDate] as? Date
        let gcpConvContentSig = AgyStatsService.directoryContentSignature(atPath: gcpConversationsDirPath)

        let cliLogExists = fm.fileExists(atPath: cliLogFilePath)
        let resolvedCliLogPath = cliLogExists ? URL(fileURLWithPath: cliLogFilePath).resolvingSymlinksInPath().path : nil
        let activeConsumerEmail = AgyStatsService.resolveActiveConsumerEmail(cliDir: expandedCliDir)

        let oauthAttrs = try? fm.attributesOfItem(atPath: oauthTokenFilePath)
        let oauthTokenMod = oauthAttrs?[.modificationDate] as? Date
        
        return FileWatcherSignature(
            histMod: histMod,
            histSize: histSize,
            dirMod: dirMod,
            convContentSig: convContentSig,
            gcpHistMod: gcpMod,
            gcpHistSize: gcpSize,
            gcpDirMod: gcpDirMod,
            gcpConvContentSig: gcpConvContentSig,
            cliLogTargetPath: resolvedCliLogPath,
            activeConsumerEmail: activeConsumerEmail,
            oauthTokenMod: oauthTokenMod
        )
    }
}
