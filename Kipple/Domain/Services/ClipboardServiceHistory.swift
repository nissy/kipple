//
//  ClipboardServiceHistory.swift
//  Kipple
//
//  Created by Kipple on 2025/07/18.
//

import Foundation
import Combine

// MARK: - History Management
// This extension handles all history-related operations for ClipboardService
extension ClipboardService {
    
    func addToHistoryWithAppInfo(_ content: String, appInfo: AppInfo, isFromEditor: Bool = false) {
        // サイズ検証（10MBを上限）
        let maxContentSize = 10 * 1024 * 1024
        guard content.utf8.count <= maxContentSize else {
            Logger.shared.warning("Clipboard content too large, skipping: \(content.utf8.count) bytes")
            return
        }
        
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 履歴の更新と保存
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let contentHash = content.hashValue
                
                // 高速な重複チェック（O(1)）
                if self.recentContentHashes.contains(contentHash) {
                    // ハッシュが存在する場合のみ実際の内容を確認
                    if let existingIndex = self.history.firstIndex(where: { $0.content == content }) {
                        // 既存のアイテムを最新に移動
                        let existingItem = self.history.remove(at: existingIndex)
                        self.history.insert(existingItem, at: 0)
                        
                        Logger.shared.debug("Moved existing item to top")
                    }
                } else {
                    // 新しいアイテムを追加
                    let newItem = ClipItem(
                        content: content, 
                        sourceApp: isFromEditor ? "Kipple" : appInfo.appName,
                        windowTitle: isFromEditor ? "Quick Editor" : appInfo.windowTitle,
                        bundleIdentifier: isFromEditor ? Bundle.main.bundleIdentifier : appInfo.bundleId,
                        processID: isFromEditor ? ProcessInfo.processInfo.processIdentifier : appInfo.pid,
                        isFromEditor: isFromEditor
                    )
                    self.history.insert(newItem, at: 0)
                    
                    // ハッシュセットを更新
                    let updateHashes = { [weak self] in
                        guard let self = self else { return }
                        self.hashLock.lock()
                        defer { self.hashLock.unlock() }
                        self.internalRecentContentHashes.insert(contentHash)
                        if self.internalRecentContentHashes.count > self.maxRecentHashes {
                            // 古いハッシュを削除
                            if self.history.count > self.maxRecentHashes,
                               let oldestContent = self.history[self.maxRecentHashes...].first?.content {
                                self.internalRecentContentHashes.remove(oldestContent.hashValue)
                            }
                        }
                    }
                    updateHashes()
                    
                    let appName = isFromEditor ? "Kipple" : (appInfo.appName ?? "unknown")
                    Logger.shared.debug("Added new item to history from app: \(appName)")
                }
                
                // 履歴の上限を設定
                self.cleanupHistory()
                
                // 履歴をデバウンスして保存
                let count = self.history.count
                Logger.shared.debug("ClipboardService: Sending \(count) items to saveSubject for debounced save")
                self.saveSubject.send(self.history)
            }
        }
    }
    
    func togglePin(for item: ClipItem) -> Bool {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            let isPinning = !history[index].isPinned
            
            // ピン留めする場合、最大数をチェック
            if isPinning {
                let maxPinnedItems = UserDefaults.standard.integer(forKey: "maxPinnedItems")
                let currentPinnedCount = history.filter { $0.isPinned }.count
                
                if currentPinnedCount >= (maxPinnedItems > 0 ? maxPinnedItems : 10) {
                    return false
                }
            }
            
            history[index].isPinned.toggle()
            saveSubject.send(history)
            return true
        }
        return false
    }
    
    func clearAllHistory() {
        // メモリ上の履歴を即座に更新
        history = history.filter { $0.isPinned }
        
        // ハッシュセットを再初期化
        initializeRecentHashes()
        
        // Core Dataのクリアは非同期で実行
        Task {
            do {
                try await repository.clear(keepPinned: true)
                Logger.shared.log("Cleared history (kept pinned items)")
            } catch {
                Logger.shared.error("Failed to clear history: \(error)")
            }
        }
    }
    
    func deleteItem(_ item: ClipItem) {
        // ハッシュセットから削除
        hashLock.lock()
        internalRecentContentHashes.remove(item.content.hashValue)
        hashLock.unlock()
        
        // メモリから削除
        history.removeAll { $0.id == item.id }
        
        // Core Dataから削除
        Task {
            do {
                try await repository.delete(item)
                Logger.shared.debug("Deleted item from Core Data")
            } catch {
                Logger.shared.error("Failed to delete item: \(error)")
            }
        }
    }
    
    // MARK: - Private History Methods
    
    private func cleanupHistory() {
        let maxHistoryItems = UserDefaults.standard.integer(forKey: "maxHistoryItems")
        let maxPinnedItems = UserDefaults.standard.integer(forKey: "maxPinnedItems")
        let historyLimit = maxHistoryItems > 0 ? maxHistoryItems : 100
        let pinnedLimit = maxPinnedItems > 0 ? maxPinnedItems : 10
        
        var pinnedCount = 0
        var totalCount = 0
        var newHistory: [ClipItem] = []
        
        for item in history {
            if item.isPinned {
                if pinnedCount < pinnedLimit {
                    newHistory.append(item)
                    pinnedCount += 1
                }
            } else {
                if totalCount < historyLimit {
                    newHistory.append(item)
                    totalCount += 1
                }
            }
        }
        
        history = newHistory
    }
    
    func initializeRecentHashes() {
        let recentItems = history.prefix(maxRecentHashes)
        hashLock.lock()
        internalRecentContentHashes = Set(recentItems.map { $0.content.hashValue })
        hashLock.unlock()
    }
    
    func saveHistoryToRepository(_ items: [ClipItem]) {
        Logger.shared.debug("ClipboardService.saveHistoryToRepository: Called with \(items.count) items")
        Task {
            do {
                Logger.shared.debug("ClipboardService.saveHistoryToRepository: Starting save operation")
                try await repository.save(items)
                let itemCount = items.count
                let msg = "ClipboardService.saveHistoryToRepository: " +
                         "Successfully saved \(itemCount) items to repository"
                Logger.shared.debug(msg)
            } catch CoreDataError.notLoaded {
                let msg = "ClipboardService.saveHistoryToRepository: " +
                         "Core Data not loaded, items stored in memory only"
                Logger.shared.warning(msg)
            } catch {
                Logger.shared.error("ClipboardService.saveHistoryToRepository: Failed to save history: \(error)")
            }
        }
    }
    
    func loadHistory() async {
        Logger.shared.log("=== LOADING HISTORY ON STARTUP ===")
        
        // Core Data が初期化されるまで待つ
        CoreDataStack.shared.initializeAndWait()
        
        do {
            let items = try await repository.load(limit: 100)
            Logger.shared.log("Repository returned \(items.count) items")
            
            await MainActor.run {
                self.history = items
                self.initializeRecentHashes()
            }
            
            Logger.shared.log("✅ Successfully loaded \(items.count) items from Core Data")
            if let firstItem = items.first {
                Logger.shared.log("Latest item: \(String(firstItem.content.prefix(50)))...")
            }
            if items.isEmpty {
                Logger.shared.log("⚠️ No items found in Core Data on startup")
            }
        } catch {
            Logger.shared.error("❌ Failed to load history: \(error)")
        }
    }
    
    // MARK: - Public Methods for Data Persistence
    
    func flushPendingSaves() async {
        saveSubscription?.cancel()
        if !history.isEmpty {
            do {
                try await repository.save(history)
                Logger.shared.log("Flushed \(history.count) items to repository")
            } catch {
                Logger.shared.error("Failed to flush saves: \(error)")
            }
        }
    }
}
