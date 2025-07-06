//
//  ClipboardService.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Cocoa
import Foundation
import Combine
import ApplicationServices

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
    // Thread-safe internal copy flag
    private let internalCopyLock = NSLock()
    private var _isInternalCopy: Bool = false
    private var isInternalCopy: Bool {
        get {
            internalCopyLock.lock()
            defer { internalCopyLock.unlock() }
            return _isInternalCopy
        }
        set {
            internalCopyLock.lock()
            defer { internalCopyLock.unlock() }
            _isInternalCopy = newValue
        }
    }
    
    // パフォーマンス最適化: 高速な重複チェック用
    private var recentContentHashes: Set<Int> = []
    private let maxRecentHashes = 50
    
    // デバウンス用
    private let saveSubject = PassthroughSubject<[ClipItem], Never>()
    private var saveSubscription: AnyCancellable?
    
    // アプリ切り替え監視用
    private var appActivationObserver: NSObjectProtocol?
    private struct LastActiveApp {
        let name: String?
        let bundleId: String?
        let pid: Int32?
    }
    private var lastActiveNonKippleApp: LastActiveApp?
    
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
        
        // アプリ切り替えの監視を開始
        setupAppActivationMonitoring()
    }
    
    func startMonitoring() {
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Prevent duplicate timers
            self.stopMonitoringInternal()
            
            self.lastChangeCount = NSPasteboard.general.changeCount
            
            // アプリ切り替えの監視を開始
            DispatchQueue.main.async { [weak self] in
                self?.setupAppActivationMonitoring()
            }
            
            // タイマーを専用スレッドで実行
            self.timerThread = Thread { [weak self] in
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
            self.timerThread?.start()
        }
    }
    
    func stopMonitoring() {
        serialQueue.async { [weak self] in
            self?.stopMonitoringInternal()
        }
        
        // アプリ切り替えの監視を停止
        DispatchQueue.main.async { [weak self] in
            self?.stopAppActivationMonitoring()
        }
    }
    
    private func stopMonitoringInternal() {
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
            
            // アプリ情報を即座に取得（遅延させない）
            let appInfo = getActiveAppInfo()
            
            // 内部コピーの場合はフラグをリセット
            if isInternalCopy {
                isInternalCopy = false
                return // 内部コピーは履歴に追加しない
            }
            
            if let content = NSPasteboard.general.string(forType: .string),
               !content.isEmpty {
                addToHistoryWithAppInfo(content, appInfo: appInfo)
            }
        }
    }
    
    private func addToHistoryWithAppInfo(_ content: String, appInfo: AppInfo) {
        // サイズ検証（10MBを上限）
        let maxContentSize = 10 * 1024 * 1024
        guard content.utf8.count <= maxContentSize else {
            Logger.shared.warning("Clipboard content too large, skipping: \(content.utf8.count) bytes")
            return
        }
        
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            
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
                    let newItem = ClipItem(
                        content: content, 
                        sourceApp: appInfo.appName,
                        windowTitle: appInfo.windowTitle,
                        bundleIdentifier: appInfo.bundleId,
                        processID: appInfo.pid
                    )
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
                    
                    Logger.shared.debug("Added new item to history from app: \(appInfo.appName ?? "unknown")")
                }
                
                // 履歴の上限を設定
                self.cleanupHistory()
                
                // 履歴をデバウンスして保存
                self.saveSubject.send(self.history)
            }
        }
    }
    
    private func addToHistory(_ content: String) {
        // 廃止予定: addToHistoryWithAppInfoを使用してください
        let appInfo = getActiveAppInfo()
        addToHistoryWithAppInfo(content, appInfo: appInfo)
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
    
    private struct AppInfo {
        let appName: String?
        let windowTitle: String?
        let bundleId: String?
        let pid: Int32?
    }
    
    private func getActiveAppInfo() -> AppInfo {
        // フロントモストアプリケーションを取得
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return AppInfo(appName: nil, windowTitle: nil, bundleId: nil, pid: nil)
        }
        
        // Kipple自身の場合は、最後にアクティブだった他のアプリを取得
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return getLastActiveNonKippleApp()
        }
        
        let appName = frontApp.localizedName
        let bundleId = frontApp.bundleIdentifier
        let pid = frontApp.processIdentifier
        
        // ウィンドウタイトルを複数の方法で取得
        var windowTitle: String?
        
        // アクセシビリティ権限をチェック
        if hasAccessibilityPermission() {
            windowTitle = getWindowTitle(for: bundleId ?? "", processId: pid)
        }
        
        // CGWindowList経由でも試す（権限不要）
        if windowTitle == nil {
            windowTitle = getWindowTitleViaCGWindowList(processId: pid)
        }
        
        Logger.shared.debug("Captured app info: \(appName ?? "unknown") (\(bundleId ?? "unknown"))")
        
        return AppInfo(appName: appName, windowTitle: windowTitle, bundleId: bundleId, pid: pid)
    }
    
    private func getWindowTitle(for bundleId: String, processId: Int32) -> String? {
        // AXUIElementを使用してアクセシビリティAPIからウィンドウタイトルを取得
        let app = AXUIElementCreateApplication(processId)
        
        // まずフォーカスされたウィンドウを試す
        var value: AnyObject?
        var result = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)
        
        // フォーカスされたウィンドウがない場合、メインウィンドウを試す
        if result != .success {
            result = AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value)
        }
        
        // それでもダメな場合、すべてのウィンドウから最初のものを取得
        if result != .success {
            result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
            if result == .success, let windows = value as? [AXUIElement], !windows.isEmpty {
                value = windows[0] as AnyObject
            }
        }
        
        if result == .success, let windowValue = value {
            // Safe cast to AXUIElement
            guard CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
                return nil
            }
            let window = unsafeBitCast(windowValue, to: AXUIElement.self)
            
            var titleValue: AnyObject?
            let titleResult = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            
            if titleResult == .success, let title = titleValue as? String, !title.isEmpty {
                return title
            }
        }
        
        return nil
    }
    
    private func initializeRecentHashes() {
        // 最近のアイテムのハッシュをSetに追加
        let recentItems = history.prefix(maxRecentHashes)
        recentContentHashes = Set(recentItems.map { $0.content.hashValue })
    }
    
    // MARK: - App Activation Monitoring
    
    private func setupAppActivationMonitoring() {
        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier,
                  bundleId != Bundle.main.bundleIdentifier else { return }
            
            self?.lastActiveNonKippleApp = LastActiveApp(
                name: app.localizedName,
                bundleId: bundleId,
                pid: app.processIdentifier
            )
            
            Logger.shared.debug("Recorded non-Kipple app: \(app.localizedName ?? "unknown")")
        }
    }
    
    private func stopAppActivationMonitoring() {
        if let observer = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            appActivationObserver = nil
        }
    }
    
    private func getLastActiveNonKippleApp() -> AppInfo {
        if let lastApp = lastActiveNonKippleApp {
            Logger.shared.debug("Using last active non-Kipple app: \(lastApp.name ?? "unknown")")
            
            // 最後のアプリのウィンドウタイトルを取得
            var windowTitle: String?
            if let lastPid = lastApp.pid {
                if hasAccessibilityPermission() {
                    windowTitle = getWindowTitle(for: lastApp.bundleId ?? "", processId: lastPid)
                }
                if windowTitle == nil {
                    windowTitle = getWindowTitleViaCGWindowList(processId: lastPid)
                }
            }
            
            return AppInfo(
                appName: lastApp.name,
                windowTitle: windowTitle,
                bundleId: lastApp.bundleId,
                pid: lastApp.pid
            )
        }
        
        return AppInfo(appName: nil, windowTitle: nil, bundleId: nil, pid: nil)
    }
    
    private func hasAccessibilityPermission() -> Bool {
        return AccessibilityManager.shared.hasPermission
    }
    
    private func getWindowTitleViaCGWindowList(processId: Int32) -> String? {
        // CGWindowListでウィンドウ情報を取得（権限不要）
        let windowList = CGWindowListCopyWindowInfo([.excludeDesktopElements, .optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        
        for window in windowList {
            guard let windowPid = window[kCGWindowOwnerPID as String] as? Int32,
                  windowPid == processId,
                  let windowName = window[kCGWindowName as String] as? String,
                  !windowName.isEmpty else { continue }
            
            return windowName
        }
        
        return nil
    }
    
    deinit {
        stopMonitoring()
    }
}
