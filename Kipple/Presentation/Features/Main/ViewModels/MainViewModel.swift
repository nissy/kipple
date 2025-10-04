//
//  MainViewModel.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class MainViewModel: ObservableObject, MainViewModelProtocol {
    @Published var editorText: String {
        didSet {
            // パフォーマンス最適化：デバウンスを使用して保存処理を遅延
            saveDebouncer.send(editorText)
        }
    }
    
    private let saveDebouncer = PassthroughSubject<String, Never>()
    
    let clipboardService: any ClipboardServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var serviceCancellables = Set<AnyCancellable>()
    
    @Published var history: [ClipItem] = []
    @Published var pinnedItems: [ClipItem] = []
    @Published var filteredHistory: [ClipItem] = []
    @Published var pinnedHistory: [ClipItem] = []
    @Published var searchText: String = "" {
        didSet {
            applyFilters()
        }
    }
    @Published var showOnlyURLs: Bool = false
    @Published var showOnlyPinned: Bool = false {
        didSet {
            applyFilters()
        }
    }
    @Published var selectedCategory: ClipItemCategory?
    @Published var isPinnedFilterActive: Bool = false
    
    // 現在のクリップボードコンテンツを公開
    @Published var currentClipboardContent: String?

    // 自動消去タイマーの残り時間
    @Published var autoClearRemainingTime: TimeInterval?

    // ページネーション関連
    @Published private(set) var hasMoreHistory: Bool = false
    private let pageSize: Int
    private var currentHistoryLimit: Int = 0
    private var isLoadingMore = false

    init(clipboardService: (any ClipboardServiceProtocol)? = nil, pageSize: Int = 50) {
        self.pageSize = max(1, pageSize)
        // 保存されたエディタテキストを読み込む（なければ空文字）
        self.editorText = UserDefaults.standard.string(forKey: "lastEditorText") ?? ""
        // Use provided service or get default service
        if let service = clipboardService {
            self.clipboardService = service
        } else {
            // Fallback to default service
            self.clipboardService = ClipboardServiceProvider.resolve()
        }

        // デバウンスされた保存処理を設定
        saveDebouncer
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] text in
                if !text.isEmpty {
                    UserDefaults.standard.set(text, forKey: "lastEditorText")
                } else {
                    UserDefaults.standard.removeObject(forKey: "lastEditorText")
                }
            }
            .store(in: &cancellables)
        
        subscribeToClipboardService()
        
        // 特定の設定値の変更のみを監視（パフォーマンス最適化）
        // 注: UserDefaultsの変更通知は特定のキーを識別できないため、
        // debounceのみで処理頻度を制限
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // 設定値が変更されたら再フィルタリング
                self.updateFilteredItems(self.clipboardService.history)
            }
            .store(in: &cancellables)

        // 初回読み込み
        updateFilteredItems(self.clipboardService.history)
        currentClipboardContent = self.clipboardService.currentClipboardContent
    }

    private func subscribeToClipboardService() {
        if let modernService = clipboardService as? ModernClipboardServiceAdapter {
            bindModernService(modernService)
        }
    }

        private func bindModernService(_ service: ModernClipboardServiceAdapter) {
        serviceCancellables.removeAll()

        service.$history
            .sink { [weak self] items in
                guard let self = self else { return }
                self.updateFilteredItems(items)
            }
            .store(in: &serviceCancellables)

        service.$currentClipboardContent
            .sink { [weak self] content in
                self?.currentClipboardContent = content
            }
            .store(in: &serviceCancellables)

        service.$autoClearRemainingTime
            .sink { [weak self] remainingTime in
                self?.autoClearRemainingTime = remainingTime
            }
            .store(in: &serviceCancellables)
    }
    
    func loadHistory() {
        let items = clipboardService.history
        updateFilteredItems(items)
    }

    func copyToClipboard(_ item: ClipItem) {
        clipboardService.copyToClipboard(item.content, fromEditor: false)
    }

    func clearHistory(keepPinned: Bool) async {
        if keepPinned {
            await clipboardService.clearAllHistory()
        } else {
            await clipboardService.clearHistory(keepPinned: false)
        }
        loadHistory()
    }

    func deleteItem(_ item: ClipItem) async {
        await clipboardService.deleteItem(item)
        loadHistory()
    }

    func togglePin(for item: ClipItem) async {
        _ = clipboardService.togglePin(for: item)
        loadHistory()
    }

    private func applyFilters() {
        updateFilteredItems(clipboardService.history)
    }

    func updateFilteredItems(_ items: [ClipItem]) {
        // Separate pinned items
        pinnedHistory = items.filter { $0.isPinned }

        // Apply filters
        var filtered = items

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { item in
                item.content.localizedCaseInsensitiveContains(searchText) ||
                (item.sourceApp?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Apply category filter with alias handling
        if let category = selectedCategory {
            filtered = filtered.filter { item in
                // Handle category aliases
                switch (category, item.category) {
                case (.url, .url), (.url, .urls), (.urls, .url), (.urls, .urls):
                    return true
                case (.email, .email), (.email, .emails), (.emails, .email), (.emails, .emails):
                    return true
                case (.filePath, .filePath), (.filePath, .files), (.files, .filePath), (.files, .files):
                    return true
                default:
                    return item.category == category
                }
            }
        }

        // URL filter
        if showOnlyURLs {
            filtered = filtered.filter { $0.kind == .url }
        }

        // Apply pinned filter
        if showOnlyPinned || isPinnedFilterActive {
            filtered = filtered.filter { $0.isPinned }
        }

        updatePagination(with: filtered)
    }

    func loadMoreHistoryIfNeeded(currentItem: ClipItem) {
        guard history.count < filteredHistory.count else { return }
        guard !isLoadingMore else { return }
        guard let lastItem = history.last, lastItem.id == currentItem.id else { return }

        isLoadingMore = true
        let newLimit = min(history.count + pageSize, filteredHistory.count)
        currentHistoryLimit = newLimit
        history = Array(filteredHistory.prefix(currentHistoryLimit))
        hasMoreHistory = history.count < filteredHistory.count
        isLoadingMore = false
    }

    private func updatePagination(with filtered: [ClipItem]) {
        filteredHistory = filtered

        let shouldPaginate = searchText.isEmpty && !isPinnedFilterActive && !showOnlyPinned
        if shouldPaginate {
            currentHistoryLimit = min(pageSize, filtered.count)
        } else {
            currentHistoryLimit = filtered.count
        }

        history = Array(filtered.prefix(currentHistoryLimit))
        hasMoreHistory = history.count < filtered.count

        if isPinnedFilterActive {
            pinnedItems = filtered
        } else {
            pinnedItems = []
        }
    }
    
    func copyEditor() {
        if !editorText.isEmpty {
            clipboardService.copyToClipboard(editorText, fromEditor: true)
            // コピー後にテキストをクリア
            editorText = ""
            UserDefaults.standard.removeObject(forKey: "lastEditorText")
        }
    }
    
    func clearEditor() {
        editorText = ""
        UserDefaults.standard.removeObject(forKey: "lastEditorText")
    }
    
    // These are now async methods above, keeping for backward compatibility
    func togglePinSync(for item: ClipItem) -> Bool {
        return clipboardService.togglePin(for: item)
    }

    func deleteItemSync(_ item: ClipItem) {
        clipboardService.deleteItem(item)
    }
    
    // MARK: - Editor Insert Functions
    
    /// エディタに内容を挿入（既存内容をクリア）
    func insertToEditor(content: String) {
        // 同期的に処理（非同期は不要）
        editorText = content
    }
    
    /// 設定された修飾キーを取得
    func getEditorInsertModifiers() -> NSEvent.ModifierFlags {
        let rawValue = UserDefaults.standard.integer(forKey: "editorInsertModifiers")
        return NSEvent.ModifierFlags(rawValue: UInt(rawValue))
    }
    
    /// 現在の修飾キーがエディタ挿入用かチェック
    func shouldInsertToEditor() -> Bool {
        let currentModifiers = NSEvent.modifierFlags
        let requiredModifiers = getEditorInsertModifiers()
        // None(=0) のときは無効
        if requiredModifiers.isEmpty { return false }
        // 必要な修飾キーがすべて押されているかチェック
        return currentModifiers.intersection(requiredModifiers) == requiredModifiers
    }
    
    /// 履歴アイテム選択（修飾キー検出対応）
    func selectHistoryItem(_ item: ClipItem, forceInsert: Bool = false) {
        if forceInsert || shouldInsertToEditor() {
            insertToEditor(content: item.content)
        } else {
            clipboardService.recopyFromHistory(item)
        }
    }
    
    /// カテゴリフィルタの切り替え
    func toggleCategoryFilter(_ category: ClipItemCategory) {
        if category == .all {
            // "All" カテゴリはフィルタをクリア
            selectedCategory = nil
        } else if selectedCategory == category {
            selectedCategory = nil
        } else {
            selectedCategory = category
            // ピンフィルターをクリア
            isPinnedFilterActive = false
        }
        // フィルタを適用
        updateFilteredItems(clipboardService.history)
    }
    
    /// ピンフィルタの切り替え
    func togglePinnedFilter() {
        isPinnedFilterActive.toggle()
        // カテゴリフィルタをクリア
        if isPinnedFilterActive {
            selectedCategory = nil
        }
        // フィルタを適用
        updateFilteredItems(clipboardService.history)
    }
}
