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
    }
    
    func updateFilteredItems(_ items: [ClipItem]) {
        // 変更がない場合は早期リターン（パフォーマンス最適化）
        if items.isEmpty && history.isEmpty && pinnedItems.isEmpty {
            return
        }
        
        // UserDefaultsから設定を直接取得（デフォルトtrue）
        let defaults = UserDefaults.standard
        let filterCategoryURL = defaults.object(forKey: "filterCategoryURL") as? Bool ?? true
        let filterCategoryEmail = defaults.object(forKey: "filterCategoryEmail") as? Bool ?? true
        let filterCategoryCode = defaults.object(forKey: "filterCategoryCode") as? Bool ?? true
        let filterCategoryFilePath = defaults.object(forKey: "filterCategoryFilePath") as? Bool ?? true
        let filterCategoryShortText = defaults.object(forKey: "filterCategoryShortText") as? Bool ?? true
        let filterCategoryLongText = defaults.object(forKey: "filterCategoryLongText") as? Bool ?? true
        let filterCategoryGeneral = defaults.object(forKey: "filterCategoryGeneral") as? Bool ?? true
        
        // 1回のループで分類（パフォーマンス最適化）
        var unpinnedItems: [ClipItem] = []
        var pinnedItems: [ClipItem] = []
        unpinnedItems.reserveCapacity(items.count)
        pinnedItems.reserveCapacity(min(items.count, 10))
        
        for item in items {
            // カテゴリフィルタ（すべてのアイテムに適用）
            if let selectedCategory = selectedCategory {
                var shouldFilter = false
                
                switch selectedCategory {
                case .url:
                    shouldFilter = filterCategoryURL
                case .email:
                    shouldFilter = filterCategoryEmail
                case .code:
                    shouldFilter = filterCategoryCode
                case .filePath:
                    shouldFilter = filterCategoryFilePath
                case .shortText:
                    shouldFilter = filterCategoryShortText
                case .longText:
                    shouldFilter = filterCategoryLongText
                case .general:
                    shouldFilter = filterCategoryGeneral
                }
                
                if shouldFilter && item.category != selectedCategory {
                    continue
                }
            }
            
            // フィルタを通過したアイテムを振り分け
            if item.isPinned {
                pinnedItems.append(item)
            } else {
                unpinnedItems.append(item)
            }
        }
        
        // 変更がある場合のみ更新
        if self.history != unpinnedItems {
            self.history = unpinnedItems
        }
        if self.pinnedItems != pinnedItems {
            self.pinnedItems = pinnedItems
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
    
    func togglePin(for item: ClipItem) {
        clipboardService.togglePin(for: item)
    }
    
    func deleteItem(_ item: ClipItem) {
        clipboardService.deleteItem(item)
    }
    
    func reorderPinnedItems(_ newOrder: [ClipItem]) {
        clipboardService.reorderPinnedItems(newOrder)
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
        }
        // フィルタを適用
        updateFilteredItems(clipboardService.history)
    }
}
