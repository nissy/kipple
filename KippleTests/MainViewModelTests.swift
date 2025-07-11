//
//  MainViewModelTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/01/03.
//

import XCTest
import SwiftUI
@testable import Kipple

class MainViewModelTests: XCTestCase {
    var viewModel: MainViewModel!
    var mockClipboardService: MockClipboardService!
    
    override func setUp() {
        super.setUp()
        mockClipboardService = MockClipboardService()
        viewModel = MainViewModel(clipboardService: mockClipboardService)
    }
    
    override func tearDown() {
        viewModel = nil
        mockClipboardService = nil
        super.tearDown()
    }
    
    // MARK: - Editor Tests
    
    func testEditorTextBinding() {
        // Given
        let testText = "Test Editor Content"
        
        // When
        viewModel.editorText = testText
        
        // Then
        XCTAssertEqual(viewModel.editorText, testText)
    }
    
    func testCopyEditor() {
        // Given
        let testText = "Test Copy Content"
        viewModel.editorText = testText
        
        // When
        viewModel.copyEditor()
        
        // Then
        XCTAssertEqual(mockClipboardService.lastCopiedContent, testText)
        XCTAssertTrue(mockClipboardService.copyToClipboardCalled)
        XCTAssertTrue(mockClipboardService.fromEditor)
    }
    
    func testClearEditor() {
        // Given
        viewModel.editorText = "Some content"
        
        // When
        viewModel.clearEditor()
        
        // Then
        XCTAssertEqual(viewModel.editorText, "")
    }
    
    // MARK: - History Selection Tests
    
    func testSelectHistoryItem() {
        // Given
        let item = ClipItem(content: "History Item")
        
        // When
        viewModel.selectHistoryItem(item)
        
        // Then
        XCTAssertEqual(mockClipboardService.lastCopiedContent, item.content)
        XCTAssertFalse(mockClipboardService.fromEditor)
    }
    
    // MARK: - Editor Insert Tests
    
    func testIsEditorInsertEnabled() {
        // Given
        let userDefaults = UserDefaults.standard
        
        // When: デフォルト状態
        userDefaults.set(false, forKey: "enableEditorInsert")
        
        // Then
        XCTAssertFalse(viewModel.isEditorInsertEnabled())
        
        // When: 有効化
        userDefaults.set(true, forKey: "enableEditorInsert")
        
        // Then
        XCTAssertTrue(viewModel.isEditorInsertEnabled())
    }
    
    func testShouldInsertToEditor() {
        // Given
        let userDefaults = UserDefaults.standard
        userDefaults.set(true, forKey: "enableEditorInsert")
        userDefaults.set(Int(NSEvent.ModifierFlags.shift.rawValue), forKey: "editorInsertModifiers")
        
        // When: エディタ挿入モードが有効な場合
        // 注: 実際のNSEventはテストで作成できないため、この部分は統合テストで確認
        
        // Then
        // メソッドが存在することを確認
        _ = viewModel.shouldInsertToEditor()
    }
    
    func testInsertToEditor() {
        // Given
        viewModel.editorText = "Existing text"
        let insertText = "New content"
        
        // When
        viewModel.insertToEditor(content: insertText)
        
        // Then
        // insertToEditorは既存の内容を置き換える（クリアしてから挿入）
        XCTAssertEqual(viewModel.editorText, "New content")
    }
    
    // MARK: - Pin Tests
    
    func testTogglePin() {
        // Given
        let item = ClipItem(content: "Pin Test", isPinned: false)
        
        // When
        viewModel.togglePin(for: item)
        
        // Then
        XCTAssertTrue(mockClipboardService.togglePinCalled)
        XCTAssertEqual(mockClipboardService.lastToggledItem?.id, item.id)
    }
    
    // MARK: - Delete Tests
    
    func testDeleteItem() {
        // Given
        let item = ClipItem(content: "Delete Test")
        
        // When
        viewModel.deleteItem(item)
        
        // Then
        XCTAssertTrue(mockClipboardService.deleteItemCalled)
        XCTAssertEqual(mockClipboardService.lastDeletedItem?.id, item.id)
    }
    
    // MARK: - Partial Update Tests
    
    func testHistoryUpdatesDoNotAffectEditor() {
        // Given
        let initialEditorText = "Editor Content"
        viewModel.editorText = initialEditorText
        
        // When: 履歴を更新
        mockClipboardService.history = [
            ClipItem(content: "New Item 1"),
            ClipItem(content: "New Item 2")
        ]
        
        // ビューモデルの履歴を更新
        viewModel.objectWillChange.send()
        
        // Then: エディタのテキストは変更されない
        XCTAssertEqual(viewModel.editorText, initialEditorText)
    }
    
    func testPinnedItemsUpdate() {
        // Given
        let unpinnedItem = ClipItem(content: "Unpinned", isPinned: false)
        let pinnedItem = ClipItem(content: "Pinned", isPinned: true)
        
        // When
        mockClipboardService.history = [unpinnedItem, pinnedItem]
        
        // ViewModelは内部でClipboardServiceの変更を監視している
        // テストでは直接pinnedItemsプロパティを確認
        let pinnedItems = mockClipboardService.pinnedItems
        
        // Then
        XCTAssertEqual(pinnedItems.count, 1)
        XCTAssertEqual(pinnedItems.first?.content, "Pinned")
    }
    
    // MARK: - Performance Tests
    
    func testLargeHistoryPerformance() {
        // Given: 大量の履歴アイテム
        let items = (1...100).map { ClipItem(content: "Item \($0)") }
        
        // When & Then: パフォーマンスを測定
        measure {
            mockClipboardService.history = items
            _ = viewModel.history
            _ = viewModel.pinnedItems
        }
    }
}

// MockClipboardServiceは削除され、
// MockClipboardServiceに統合されました（Helpers/MockClipboardService.swift）
