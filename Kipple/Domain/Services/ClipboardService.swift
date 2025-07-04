//
//  ClipboardService.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Cocoa
import Foundation
import Combine

class ClipboardService: ObservableObject, ClipboardServiceProtocol {
    static let shared = ClipboardService()
    
    @Published var history: [ClipItem] = []
    var pinnedItems: [ClipItem] {
        history.filter { $0.isPinned }
    }
    var onHistoryChanged: ((ClipItem) -> Void)?
    var onPinnedItemsChanged: (([ClipItem]) -> Void)?
    
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let repository = ClipboardRepository()
    private let serialQueue = DispatchQueue(label: "com.nissy.Kipple.clipboard", qos: .userInitiated)
    private var timerRunLoop: RunLoop?
    private var timerThread: Thread?
    private var isInternalCopy: Bool = false
    
    // パフォーマンス最適化: 高速な重複チェック用
    private var recentContentHashes: Set<Int> = []
    private let maxRecentHashes = 50
    
    // デバウンス用
    private let saveSubject = PassthroughSubject<[ClipItem], Never>()
    private var saveSubscription: AnyCancellable?
    
    private init() {
        // Load saved history
        history = repository.load()
        
        // ハッシュセットを初期化
        initializeRecentHashes()
        
        // デバウンス設定（1秒後に保存）
        saveSubscription = saveSubject
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] items in
                self?.saveHistoryToRepository(items)
            }
    }
    
    func startMonitoring() {
        // Prevent duplicate timers
        stopMonitoring()
        
        lastChangeCount = NSPasteboard.general.changeCount
        
        // タイマーを専用スレッドで実行
        timerThread = Thread { [weak self] in
            guard let self = self else { return }
            
            self.timerRunLoop = RunLoop.current
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                self.checkClipboard()
            }
            
            // RunLoopを実行（停止可能な方法で）
            while !Thread.current.isCancelled && self.timerRunLoop != nil {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
            }
        }
        timerThread?.start()
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        timerRunLoop = nil
        timerThread?.cancel()
        timerThread = nil
    }
    
    private func checkClipboard() {
        let currentChangeCount = NSPasteboard.general.changeCount
        
        if currentChangeCount != lastChangeCount {
            lastChangeCount = currentChangeCount
            
            // 内部コピーの場合はフラグをリセット
            if isInternalCopy {
                isInternalCopy = false
            }
            
            if let content = NSPasteboard.general.string(forType: .string),
               !content.isEmpty {
                addToHistory(content)
            }
        }
    }
    
    private func addToHistory(_ content: String) {
        // サイズ検証（10MBを上限）
        let maxContentSize = 10 * 1024 * 1024
        guard content.utf8.count <= maxContentSize else {
            Logger.shared.warning("Clipboard content too large, skipping: \(content.utf8.count) bytes")
            return
        }
        
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 現在のアプリケーション名を取得（バックグラウンドで）
            let sourceApp = self.getActiveAppName()
            
            // 履歴の更新と保存
            DispatchQueue.main.async {
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
                    let newItem = ClipItem(content: content, sourceApp: sourceApp)
                    self.history.insert(newItem, at: 0)
                    
                    // ハッシュセットを更新
                    self.recentContentHashes.insert(contentHash)
                    if self.recentContentHashes.count > self.maxRecentHashes {
                        // 古いハッシュを削除（最も古いアイテムのハッシュを削除）
                        if self.history.count > self.maxRecentHashes,
                           let oldestContent = self.history[self.maxRecentHashes...].first?.content {
                            self.recentContentHashes.remove(oldestContent.hashValue)
                        }
                    }
                    
                    Logger.shared.debug("Added new item to history from app: \(sourceApp ?? "unknown")")
                }
                
                // 履歴の上限を設定
                self.cleanupHistory()
                
                // 履歴をデバウンスして保存
                self.saveSubject.send(self.history)
            }
        }
    }
    
    func copyToClipboard(_ content: String, fromEditor: Bool = false) {
        // エディタからのコピーでない場合のみ内部コピーフラグを設定
        if !fromEditor {
            isInternalCopy = true
        }
        
        // クリップボードには常にコピーする
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
    
    func togglePin(for item: ClipItem) {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            let isPinning = !history[index].isPinned
            
            // ピン留めする場合、最大数をチェック
            if isPinning {
                let maxPinnedItems = UserDefaults.standard.integer(forKey: "maxPinnedItems")
                let currentPinnedCount = history.filter { $0.isPinned }.count
                
                if currentPinnedCount >= (maxPinnedItems > 0 ? maxPinnedItems : 10) {
                    // 最大数に達している場合は何もしない
                    return
                }
            }
            
            history[index].isPinned.toggle()
            
            // ピン留めする場合は一番下に移動
            if history[index].isPinned {
                let pinnedItem = history.remove(at: index)
                // 既存のピン留めアイテムの最後に追加
                let pinnedItems = history.filter { $0.isPinned }
                let unpinnedItems = history.filter { !$0.isPinned }
                history = pinnedItems + [pinnedItem] + unpinnedItems
            }
            
            saveSubject.send(history)
        }
    }
    
    private func cleanupHistory() {
        // より効率的な実装：1回のパスで分類
        var pinnedItems: [ClipItem] = []
        var unpinnedItems: [ClipItem] = []
        
        for item in history {
            if item.isPinned {
                pinnedItems.append(item)
            } else {
                unpinnedItems.append(item)
            }
        }
        
        // UserDefaultsから最大数を取得
        let maxHistoryItems = UserDefaults.standard.integer(forKey: "maxHistoryItems")
        let maxPinnedItems = UserDefaults.standard.integer(forKey: "maxPinnedItems")
        let historyLimit = maxHistoryItems > 0 ? maxHistoryItems : 100 // デフォルトは100
        let pinnedLimit = maxPinnedItems > 0 ? maxPinnedItems : 10 // デフォルトは10
        
        // ピン留めアイテムと通常アイテムをそれぞれ制限
        let limitedPinnedItems = Array(pinnedItems.prefix(pinnedLimit))
        let limitedUnpinnedItems = Array(unpinnedItems.prefix(historyLimit))
        
        history = limitedPinnedItems + limitedUnpinnedItems
    }
    
    func clearAllHistory() {
        // ピン留めされたアイテムのみを保持
        history = history.filter { $0.isPinned }
        
        // ハッシュセットを再初期化
        initializeRecentHashes()
        
        saveSubject.send(history)
    }
    
    func deleteItem(_ item: ClipItem) {
        // ハッシュセットから削除
        recentContentHashes.remove(item.content.hashValue)
        
        history.removeAll { $0.id == item.id }
        saveSubject.send(history)
    }
    
    func reorderPinnedItems(_ newOrder: [ClipItem]) {
        // 現在の非ピン留めアイテムを保持
        let unpinnedItems = history.filter { !$0.isPinned }
        
        // 新しい順序のピン留めアイテムと非ピン留めアイテムを結合
        history = newOrder + unpinnedItems
        saveSubject.send(history)
    }
    
    // MARK: - Helper Methods
    
    private func saveHistoryToRepository(_ items: [ClipItem]) {
        serialQueue.async { [weak self] in
            self?.repository.save(items)
        }
    }
    
    private func getActiveAppName() -> String? {
        // フロントモストアプリケーションを取得
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            return frontApp.localizedName
        }
        return nil
    }
    
    private func initializeRecentHashes() {
        // 最近のアイテムのハッシュをSetに追加
        let recentItems = history.prefix(maxRecentHashes)
        recentContentHashes = Set(recentItems.map { $0.content.hashValue })
    }
    
    deinit {
        stopMonitoring()
    }
}
