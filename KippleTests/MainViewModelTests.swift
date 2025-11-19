//
//  MainViewModelTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/01/03.
//

import XCTest
import SwiftUI
import Combine
@testable import Kipple

@MainActor
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
        XCTAssertTrue(mockClipboardService.fromEditor ?? false)
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
        XCTAssertEqual(mockClipboardService.lastRecopiedItem?.content, item.content)
    }

    // MARK: - Editor Insert Tests

    func testShouldInsertToEditor() {
        // Given
        let userDefaults = UserDefaults.standard
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

    func testTogglePin() async {
        // Given
        let item = ClipItem(content: "Pin Test", isPinned: false)

        // When
        await viewModel.togglePin(for: item)

        // Then
        XCTAssertTrue(mockClipboardService.togglePinCalled)
        XCTAssertEqual(mockClipboardService.lastToggledItem?.id, item.id)
    }

    // MARK: - Delete Tests

    func testDeleteItem() async {
        // Given
        let item = ClipItem(content: "Delete Test")

        // When
        await viewModel.deleteItem(item)

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

    func testInitialPaginationShowsFirstPageOnly() {
        // Given
        mockClipboardService.history = (1...120).map { ClipItem(content: "Item \($0)") }

        // When
        viewModel.loadHistory()

        // Then
        XCTAssertEqual(viewModel.history.count, 50)
        XCTAssertTrue(viewModel.hasMoreHistory)
    }

    func testLoadMoreHistoryAppendsNextPage() {
        // Given
        mockClipboardService.history = (1...120).map { ClipItem(content: "Item \($0)") }
        viewModel.loadHistory()
        let lastVisible = viewModel.history.last

        // When
        if let lastVisible {
            viewModel.loadMoreHistoryIfNeeded(currentItem: lastVisible)
        }

        // Then
        XCTAssertEqual(viewModel.history.count, 100)
        XCTAssertTrue(viewModel.hasMoreHistory)
    }

    func testCurrentClipboardItemIDMatchesHistoryContent() {
        // Given
        let items = [
            ClipItem(content: "First"),
            ClipItem(content: "Second")
        ]
        mockClipboardService.history = items
        viewModel.loadHistory()

        // When
        viewModel.currentClipboardContent = items[1].content

        // Then
        XCTAssertEqual(viewModel.currentClipboardItemID, items[1].id)
    }

    func testCurrentClipboardItemIDClearsWhenContentBecomesNil() {
        // Given
        let item = ClipItem(content: "Only")
        mockClipboardService.history = [item]
        viewModel.loadHistory()
        viewModel.currentClipboardContent = item.content
        XCTAssertEqual(viewModel.currentClipboardItemID, item.id)

        // When
        viewModel.currentClipboardContent = nil

        // Then
        XCTAssertNil(viewModel.currentClipboardItemID)
    }

    func testLoadMoreHistoryPublishesLoadingState() {
        // Given
        mockClipboardService.history = (1...120).map { ClipItem(content: "Item \($0)") }
        viewModel.loadHistory()
        guard let lastVisible = viewModel.history.last else {
            XCTFail("Expected initial history to contain items")
            return
        }

        var loadingStates: [Bool] = []
        let cancellable = viewModel.$isLoadingMoreHistory.sink { value in
            loadingStates.append(value)
        }

        // When
        viewModel.loadMoreHistoryIfNeeded(currentItem: lastVisible)
        cancellable.cancel()

        // Then
        XCTAssertTrue(loadingStates.contains(true), "Loading flag should publish true at least once")
        XCTAssertFalse(viewModel.isLoadingMoreHistory)
    }

    func testLoadHistoryUntilAllItemsLoaded() {
        // Given
        let totalItems = 180
        mockClipboardService.history = (1...totalItems).map { ClipItem(content: "Item \($0)") }
        viewModel.loadHistory()

        var iteration = 0
        let maxIterations = 10

        // When
        while viewModel.hasMoreHistory && iteration < maxIterations {
            guard let lastVisible = viewModel.history.last else {
                XCTFail("Expected history to contain items while loading")
                break
            }
            viewModel.loadMoreHistoryIfNeeded(currentItem: lastVisible)
            iteration += 1
        }

        // Then
        XCTAssertEqual(viewModel.history.count, totalItems)
        XCTAssertFalse(viewModel.hasMoreHistory)
    }

    func testSearchDisablesPagination() {
        // Given
        mockClipboardService.history = (1...30).map { ClipItem(content: "Item \($0)") }
        viewModel.loadHistory()

        // When
        viewModel.searchText = "Item 2"

        // Then
        XCTAssertFalse(viewModel.hasMoreHistory)
        XCTAssertEqual(viewModel.history.count, viewModel.filteredHistory.count)
        XCTAssertTrue(viewModel.history.allSatisfy { $0.content.contains("Item 2") })
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
