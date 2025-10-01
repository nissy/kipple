//
//  SearchAndFilterTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/11.
//
//  SPECS.md準拠: フィルタリング機能のテスト
//  - カテゴリフィルター（8種類）
//  - ピン留めフィルター
//  注意: 検索機能はMainViewHistorySectionに実装されているため、
//        このテストではカテゴリとピンフィルターのみをテストする

import XCTest
import Combine
@testable import Kipple

@MainActor
final class SearchAndFilterTests: XCTestCase, @unchecked Sendable {
    var viewModel: MainViewModel!
    var mockClipboardService: MockClipboardService!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        mockClipboardService = MockClipboardService()
        viewModel = MainViewModel(clipboardService: mockClipboardService)
        cancellables.removeAll()

        // テスト用の履歴データを設定
        setupTestHistory()

        // MockクラスがClipboardServiceでないため、手動でupdateFilteredItemsを呼ぶ
        viewModel.updateFilteredItems(mockClipboardService.history)
    }

    override func tearDown() {
        mockClipboardService?.reset()
        viewModel = nil
        mockClipboardService = nil
        cancellables.removeAll()
        super.tearDown()
    }

    private func setupTestHistory() {
        // SPECS.md: 8種類のカテゴリをカバーするテストデータ
        mockClipboardService.history = [
            ClipItem(content: "https://example.com", isPinned: false),                    // URL
            ClipItem(content: "test@example.com", isPinned: true),                       // Email (pinned)
            ClipItem(content: "func test() { return true }", isPinned: false),          // Code
            ClipItem(content: "/Users/test/file.txt", isPinned: false),                 // File Path
            ClipItem(content: "Short text", isPinned: true),                            // Short Text (pinned)
            ClipItem(content: "This is a very long text that exceeds the typical short text limit and contains multiple sentences. It should be categorized as long text in the filter.", isPinned: false), // Long Text
            ClipItem(content: "42", isPinned: false),                                   // Number
            ClipItem(content: "{\"key\": \"value\"}", isPinned: false)                    // JSON
        ]
    }

    // MARK: - Category Filter Tests

    @MainActor
    func testCategoryFilterURL() {
        // When: URLフィルターを適用
        viewModel.toggleCategoryFilter(.urls)

        // Then: URLアイテムのみが表示される
        XCTAssertEqual(viewModel.filteredHistory.count, 1, "URLフィルター適用時は1件のみ表示")
        XCTAssertTrue(viewModel.filteredHistory.first!.content.contains("https://"))
        XCTAssertEqual(viewModel.selectedCategory, .urls)
    }

    @MainActor
    func testCategoryFilterEmail() {
        // When: Emailフィルターを適用
        viewModel.toggleCategoryFilter(.emails)

        // Then: Emailアイテムのみが表示される
        XCTAssertEqual(viewModel.filteredHistory.count, 1, "Emailフィルター適用時は1件のみ表示")
        XCTAssertTrue(viewModel.filteredHistory.first!.content.contains("@"))
        XCTAssertEqual(viewModel.selectedCategory, .emails)
    }

    @MainActor
    func testCategoryFilterKipple() {
        // When: Kippleフィルターを適用（Editor由来のアイテム）
        viewModel.toggleCategoryFilter(.kipple)

        // Then: Editorからコピーされたアイテムのみ（今回は0件）
        XCTAssertEqual(viewModel.filteredHistory.count, 0, "Kippleフィルター適用時はEditor由来のアイテムのみ")
    }

    @MainActor
    func testCategoryFilterAll() {
        // Given: カテゴリフィルターを設定
        viewModel.toggleCategoryFilter(.urls)
        XCTAssertEqual(viewModel.history.count, 1)

        // When: allカテゴリを選択
        viewModel.toggleCategoryFilter(.all)

        // Then: すべてのアイテムが表示される
        XCTAssertEqual(viewModel.filteredHistory.count, mockClipboardService.history.count)
        XCTAssertNil(viewModel.selectedCategory)
    }

    // MARK: - Pinned Filter Tests

    @MainActor
    func testPinnedFilter() {
        // When: ピン留めフィルターを適用
        viewModel.showOnlyPinned = true

        // Then: ピン留めアイテムのみが表示される（2件）
        XCTAssertEqual(viewModel.filteredHistory.count, 2, "ピン留めフィルター適用時は2件表示")
        XCTAssertTrue(viewModel.filteredHistory.allSatisfy { $0.isPinned })
    }

    @MainActor
    func testCombinedCategoryAndPinnedFilter() {
        // Given: URLカテゴリフィルターを適用
        viewModel.toggleCategoryFilter(.urls)
        XCTAssertEqual(viewModel.filteredHistory.count, 1)

        // When: ピン留めフィルターも適用
        viewModel.showOnlyPinned = true

        // Then: URLかつピン留めされたアイテムのみ（0件）
        XCTAssertEqual(viewModel.filteredHistory.count, 0, "URLかつピン留めのアイテムは存在しない")

        // When: Emailカテゴリに変更
        viewModel.toggleCategoryFilter(.emails)

        // Then: Emailかつピン留めされたアイテム（1件）
        XCTAssertEqual(viewModel.filteredHistory.count, 1, "Emailかつピン留めのアイテムは1件")
        XCTAssertTrue(viewModel.filteredHistory.first!.content.contains("@"))
        XCTAssertTrue(viewModel.filteredHistory.first!.isPinned)
    }

    // MARK: - Filter Toggle Tests

    @MainActor
    func testTogglePinnedFilter() {
        // When: ピン留めフィルターをON
        viewModel.showOnlyPinned = true
        XCTAssertEqual(viewModel.filteredHistory.count, 2)

        // When: ピン留めフィルターをOFF
        viewModel.showOnlyPinned = false

        // Then: 全アイテムが表示される
        XCTAssertEqual(viewModel.filteredHistory.count, mockClipboardService.history.count)
    }

    @MainActor
    func testToggleCategoryFilter() {
        // When: 同じカテゴリを2回選択（トグル）
        viewModel.toggleCategoryFilter(.urls)
        XCTAssertEqual(viewModel.selectedCategory, .urls)
        XCTAssertEqual(viewModel.filteredHistory.count, 1)

        viewModel.toggleCategoryFilter(.urls)

        // Then: フィルターが解除される
        XCTAssertNil(viewModel.selectedCategory)
        XCTAssertEqual(viewModel.filteredHistory.count, mockClipboardService.history.count)
    }

    // MARK: - Performance Tests

    @MainActor
    func testCategoryFilterPerformance() {
        // Given: 大量のアイテムを追加
        for i in 0..<1000 {
            mockClipboardService.history.append(
                ClipItem(content: "Item \(i)", isPinned: i % 10 == 0)
            )
        }

        // Measure: フィルター適用のパフォーマンス
        measure {
            viewModel.updateFilteredItems(mockClipboardService.history)
            viewModel.toggleCategoryFilter(.urls)
            viewModel.showOnlyPinned = true
            viewModel.showOnlyPinned = false
            viewModel.toggleCategoryFilter(.all)
        }
    }
}
