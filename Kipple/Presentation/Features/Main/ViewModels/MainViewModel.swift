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
    @Published var searchText: String = ""
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
    
    init(clipboardService: (any ClipboardServiceProtocol)? = nil) {
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
        await clipboardService.clearHistory(keepPinned: keepPinned)
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

        // Update filtered results
        filteredHistory = filtered

        // Keep backward compatibility
        if isPinnedFilterActive {
            self.pinnedItems = pinnedHistory
            self.history = filtered  // Set to filtered items (which are pinned when isPinnedFilterActive is true)
        } else {
            self.history = filtered
            self.pinnedItems = []
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
    
    /// エディタ挿入機能が有効かチェック
    func isEditorInsertEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "enableEditorInsert")
    }
    
    /// 設定された修飾キーを取得
    func getEditorInsertModifiers() -> NSEvent.ModifierFlags {
        let rawValue = UserDefaults.standard.integer(forKey: "editorInsertModifiers")
        return NSEvent.ModifierFlags(rawValue: UInt(rawValue))
    }
    
    /// 現在の修飾キーがエディタ挿入用かチェック
    func shouldInsertToEditor() -> Bool {
        guard isEditorInsertEnabled() else { return false }
        
        let currentModifiers = NSEvent.modifierFlags
        let requiredModifiers = getEditorInsertModifiers()
        
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
