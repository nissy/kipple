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
    @Published var currentClipboardContent: String?
    var pinnedItems: [ClipItem] {
        history.filter { $0.isPinned }
    }
    var onHistoryChanged: ((ClipItem) -> Void)?
    
    private var lastChangeCount: Int = 0
    private var timer: Timer?
    private let repository: any ClipboardRepositoryProtocol = CoreDataClipboardRepository()
    private let serialQueue = DispatchQueue(label: "com.nissy.Kipple.clipboard", qos: .userInitiated)
    private var timerRunLoop: RunLoop?
    private var timerThread: Thread?
    
    // Auto-clear timer
    var autoClearTimer: Timer?
    var autoClearStartTime: Date?
    @Published var autoClearRemainingTime: TimeInterval?
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
    
    // Thread-safe editor copy flag
    private let editorCopyLock = NSLock()
    private var _isFromEditor: Bool = false
    private var isFromEditor: Bool {
        get {
            editorCopyLock.lock()
            defer { editorCopyLock.unlock() }
            return _isFromEditor
        }
        set {
            editorCopyLock.lock()
            defer { editorCopyLock.unlock() }
            _isFromEditor = newValue
        }
    }
    
    // パフォーマンス最適化: 高速な重複チェック用
    private let hashLock = NSLock()
    private var _recentContentHashes: Set<Int> = []
    private var recentContentHashes: Set<Int> {
        get {
            hashLock.lock()
            defer { hashLock.unlock() }
            return _recentContentHashes
        }
        set {
            hashLock.lock()
            defer { hashLock.unlock() }
            _recentContentHashes = newValue
        }
    }
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
        // テスト環境かどうかを検出
        let isTestEnvironment = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
                                NSClassFromString("XCTest") != nil
        
        // テスト環境では最小限の初期化のみ
        if isTestEnvironment {
            return
        }
        
        // デバウンス設定（1秒後に保存）
        saveSubscription = saveSubject
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] items in
                Logger.shared.debug("ClipboardService: Debounce fired with \(items.count) items")
                self?.saveHistoryToRepository(items)
            }
        
        // アプリ切り替えの監視を開始
        setupAppActivationMonitoring()
        
        // 現在のクリップボードの内容を初期化（同期的に設定）
        currentClipboardContent = NSPasteboard.general.string(forType: .string)
        
        // 非同期で履歴を読み込み
        Task {
            await loadHistory()
        }
    }
    
    private func loadHistory() async {
        Logger.shared.log("=== LOADING HISTORY ON STARTUP ===")
        
        // Core Data が初期化されるまで待つ
        CoreDataStack.shared.initializeAndWait()
        
        do {
            let items = try await repository.load(limit: 100)
            Logger.shared.log("Repository returned \(items.count) items")
            
            await MainActor.run {
                self.history = items
                // ハッシュセットを初期化
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
            
            // Start auto-clear timer if enabled
            Task { @MainActor [weak self] in
                self?.startAutoClearTimerIfNeeded()
            }
        }
    }
    
    func stopMonitoring() {
        serialQueue.async { [weak self] in
            self?.stopMonitoringInternal()
        }
        
        // アプリ切り替えの監視を停止
        DispatchQueue.main.async { [weak self] in
            self?.stopAppActivationMonitoring()
            self?.stopAutoClearTimer()
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
            
            // スレッドセーフにフラグを処理
            var shouldSkip = false
            var fromEditor = false
            
            if isInternalCopy {
                isInternalCopy = false
                shouldSkip = true
            } else if isFromEditor {
                fromEditor = true
                isFromEditor = false
            }
            
            if shouldSkip {
                return // 内部コピーは履歴に追加しない
            }
            
            if let content = NSPasteboard.general.string(forType: .string),
               !content.isEmpty {
                // 現在のクリップボード内容を更新
                Task { @MainActor [weak self] in
                    self?.currentClipboardContent = content
                }
                addToHistoryWithAppInfo(content, appInfo: appInfo, isFromEditor: fromEditor)
            }
        }
    }
    
    private func addToHistoryWithAppInfo(_ content: String, appInfo: AppInfo, isFromEditor: Bool = false) {
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
                        sourceApp: isFromEditor ? "Kipple" : appInfo.appName,  // エディタからの場合は "Kipple" に固定
                        windowTitle: isFromEditor ? "Quick Editor" : appInfo.windowTitle,
                        bundleIdentifier: isFromEditor ? Bundle.main.bundleIdentifier : appInfo.bundleId,
                        processID: isFromEditor ? ProcessInfo.processInfo.processIdentifier : appInfo.pid,
                        isFromEditor: isFromEditor
                    )
                    self.history.insert(newItem, at: 0)
                    
                    // ハッシュセットを更新（スレッドセーフ）
                    // NSLockは async context から直接使えないため、同期的に実行
                    let updateHashes = { [weak self] in
                        guard let self = self else { return }
                        self.hashLock.lock()
                        defer { self.hashLock.unlock() }
                        self._recentContentHashes.insert(contentHash)
                        if self._recentContentHashes.count > self.maxRecentHashes {
                            // 古いハッシュを削除（最も古いアイテムのハッシュを削除）
                            if self.history.count > self.maxRecentHashes,
                               let oldestContent = self.history[self.maxRecentHashes...].first?.content {
                                self._recentContentHashes.remove(oldestContent.hashValue)
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
    
    private func addToHistory(_ content: String) {
        // 廃止予定: addToHistoryWithAppInfoを使用してください
        let appInfo = getActiveAppInfo()
        addToHistoryWithAppInfo(content, appInfo: appInfo, isFromEditor: false)
    }
    
    func copyToClipboard(_ content: String, fromEditor: Bool = false) {
        // スレッドセーフにフラグを設定
        if !fromEditor {
            // エディタからのコピーでない場合のみ内部コピーフラグを設定
            isInternalCopy = true
            isFromEditor = false
        } else {
            // エディタからのコピーの場合、次のクリップボード項目がエディタ由来であることを記録
            isFromEditor = true
            // エディタからのコピーは内部コピーではないことを明示
            isInternalCopy = false
        }
        
        // 現在のクリップボード内容を即座に更新（同期的に）
        currentClipboardContent = content
        
        // クリップボードには常にコピーする
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        
        // 履歴からのコピーの場合、既存のアイテムを最上位に移動
        if !fromEditor {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // 既存のアイテムを探して最上位に移動
                if let existingIndex = self.history.firstIndex(where: { $0.content == content }) {
                    let existingItem = self.history.remove(at: existingIndex)
                    self.history.insert(existingItem, at: 0)
                    
                    // 変更を保存
                    self.saveSubject.send(self.history)
                    
                    Logger.shared.debug("Moved Kipple-copied item to top")
                }
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
                    // 最大数に達している場合はfalseを返す
                    return false
                }
            }
            
            history[index].isPinned.toggle()
            
            saveSubject.send(history)
            return true
        }
        return false
    }
    
    private func cleanupHistory() {
        // UserDefaultsから最大数を取得
        let maxHistoryItems = UserDefaults.standard.integer(forKey: "maxHistoryItems")
        let maxPinnedItems = UserDefaults.standard.integer(forKey: "maxPinnedItems")
        let historyLimit = maxHistoryItems > 0 ? maxHistoryItems : 100 // デフォルトは100
        let pinnedLimit = maxPinnedItems > 0 ? maxPinnedItems : 10 // デフォルトは10
        
        // ピン留めアイテムの数を制限（元の順序を維持）
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
    
    func clearAllHistory() {
        // メモリ上の履歴を即座に更新（UIの即座反映のため）
        history = history.filter { $0.isPinned }
        
        // ハッシュセットを再初期化
        initializeRecentHashes()
        
        // Core Dataのクリアは非同期で実行
        Task {
            do {
                // Core Dataからクリア（ピン留めは保持）
                try await repository.clear(keepPinned: true)
                Logger.shared.log("Cleared history (kept pinned items)")
            } catch {
                Logger.shared.error("Failed to clear history: \(error)")
            }
        }
    }
    
    func deleteItem(_ item: ClipItem) {
        // ハッシュセットから削除（スレッドセーフ）
        hashLock.lock()
        _recentContentHashes.remove(item.content.hashValue)
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
    
    // MARK: - Helper Methods
    
    private func saveHistoryToRepository(_ items: [ClipItem]) {
        Logger.shared.debug("ClipboardService.saveHistoryToRepository: Called with \(items.count) items")
        Task {
            do {
                Logger.shared.debug("ClipboardService.saveHistoryToRepository: Starting save operation")
                try await repository.save(items)
                let itemCount = items.count
                let msg = "ClipboardService.saveHistoryToRepository: Successfully saved \(itemCount) items to repository"
                Logger.shared.debug(msg)
            } catch CoreDataError.notLoaded {
                let msg = "ClipboardService.saveHistoryToRepository: Core Data not loaded, items stored in memory only"
                Logger.shared.warning(msg)
                // メモリベースのフォールバック処理
                // 履歴は既にメモリ上の配列に保存されているため、追加処理は不要
            } catch {
                Logger.shared.error("ClipboardService.saveHistoryToRepository: Failed to save history: \(error)")
                // TODO: リトライロジックの実装を検討
            }
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
        hashLock.lock()
        _recentContentHashes = Set(recentItems.map { $0.content.hashValue })
        hashLock.unlock()
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
        let windowOptions: CGWindowListOption = [.excludeDesktopElements, .optionOnScreenOnly]
        let windowList = CGWindowListCopyWindowInfo(windowOptions, kCGNullWindowID) as? [[String: Any]] ?? []
        
        for window in windowList {
            guard let windowPid = window[kCGWindowOwnerPID as String] as? Int32,
                  windowPid == processId,
                  let windowName = window[kCGWindowName as String] as? String,
                  !windowName.isEmpty else { continue }
            
            return windowName
        }
        
        return nil
    }
    
    // MARK: - Public Methods for Data Persistence
    
    func flushPendingSaves() async {
        // デバウンスをキャンセルして即座に保存
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
    
    deinit {
        stopMonitoring()
    }
}
