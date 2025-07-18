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
    let repository: any ClipboardRepositoryProtocol = CoreDataClipboardRepository()
    let serialQueue = DispatchQueue(label: "com.nissy.Kipple.clipboard", qos: .userInitiated)
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
    let hashLock = NSLock()
    var internalRecentContentHashes: Set<Int> = []
    var recentContentHashes: Set<Int> {
        get {
            hashLock.lock()
            defer { hashLock.unlock() }
            return internalRecentContentHashes
        }
        set {
            hashLock.lock()
            defer { hashLock.unlock() }
            internalRecentContentHashes = newValue
        }
    }
    let maxRecentHashes = 50
    
    // デバウンス用
    let saveSubject = PassthroughSubject<[ClipItem], Never>()
    var saveSubscription: AnyCancellable?
    
    // アプリ切り替え監視用
    var appActivationObserver: NSObjectProtocol?
    struct LastActiveApp {
        let name: String?
        let bundleId: String?
        let pid: Int32?
    }
    var lastActiveNonKippleApp: LastActiveApp?
    
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
                // 内部コピーの場合でも現在のクリップボード内容は更新する
                if let content = NSPasteboard.general.string(forType: .string),
                   !content.isEmpty {
                    Task { @MainActor [weak self] in
                        self?.currentClipboardContent = content
                        // 自動クリアタイマーをリセット
                        if AppSettings.shared.enableAutoClear {
                            self?.restartAutoClearTimer()
                        }
                    }
                }
                return // 内部コピーは履歴に追加しない
            }
            
            if let content = NSPasteboard.general.string(forType: .string),
               !content.isEmpty {
                // 現在のクリップボード内容を更新
                Task { @MainActor [weak self] in
                    self?.currentClipboardContent = content
                    // 自動クリアタイマーをリセット
                    if AppSettings.shared.enableAutoClear {
                        self?.restartAutoClearTimer()
                    }
                }
                addToHistoryWithAppInfo(content, appInfo: appInfo, isFromEditor: fromEditor)
            }
        }
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
    
    deinit {
        stopMonitoring()
    }
}
