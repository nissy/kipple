//
//  MainViewModel.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import Foundation
import SwiftUI
import Combine

class MainViewModel: ObservableObject {
    @Published var editorText: String {
        didSet {
            // パフォーマンス最適化：デバウンスを使用して保存処理を遅延
            saveDebouncer.send(editorText)
        }
    }
    
    private let saveDebouncer = PassthroughSubject<String, Never>()
    
    let clipboardService: ClipboardServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    
    @Published var history: [ClipItem] = []
    @Published var pinnedItems: [ClipItem] = []
    @Published var selectedCategory: ClipItemCategory?
    @Published var isPinnedFilterActive: Bool = false
    
    // 現在のクリップボードコンテンツを公開
    @Published var currentClipboardContent: String?
    
    init(clipboardService: ClipboardServiceProtocol = ClipboardService.shared) {
        // 保存されたエディタテキストを読み込む（なければ空文字）
        self.editorText = UserDefaults.standard.string(forKey: "lastEditorText") ?? ""
        self.clipboardService = clipboardService
        
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
        
        // Subscribe to clipboard service changes
        if let observableService = clipboardService as? ClipboardService {
            observableService.$history
            .sink { [weak self] items in
                guard let self = self else { return }
                self.updateFilteredItems(items)
            }
            .store(in: &cancellables)
            
            // 現在のクリップボード内容の変更を監視
            observableService.$currentClipboardContent
            .sink { [weak self] content in
                self?.currentClipboardContent = content
            }
            .store(in: &cancellables)
        }
        
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
        updateFilteredItems(clipboardService.history)
        currentClipboardContent = clipboardService.currentClipboardContent
    }
    
    func updateFilteredItems(_ items: [ClipItem]) {
        // フィルタ無しの場合は全アイテムを使用
        if !isPinnedFilterActive && selectedCategory == nil {
            self.history = items
            self.pinnedItems = []
            return
        }
        
        // フィルタありの場合
        var filteredItems: [ClipItem] = []
        
        for item in items {
            // ピンフィルタ
            if isPinnedFilterActive && !item.isPinned {
                continue
            }
            
            // カテゴリフィルタ
            if let selectedCategory = selectedCategory, item.category != selectedCategory {
                continue
            }
            
            filteredItems.append(item)
        }
        
        self.history = filteredItems
        self.pinnedItems = []
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
    
    func togglePin(for item: ClipItem) -> Bool {
        return clipboardService.togglePin(for: item)
    }
    
    func deleteItem(_ item: ClipItem) {
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
            clipboardService.copyToClipboard(item.content, fromEditor: false)
        }
    }
    
    /// カテゴリフィルタの切り替え
    func toggleCategoryFilter(_ category: ClipItemCategory) {
        if selectedCategory == category {
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
