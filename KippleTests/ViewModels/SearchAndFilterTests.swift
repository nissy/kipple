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

final class SearchAndFilterTests: XCTestCase {
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
            ClipItem(content: String(repeating: "Long ", count: 250), isPinned: false), // Long Text (1000+ chars)
            ClipItem(content: "This is a general text content", isPinned: false),       // General
            ClipItem(content: "Editor content", isPinned: false, isFromEditor: true),   // Kipple
            ClipItem(content: "https://test.com", isPinned: true),                      // URL (pinned)
            ClipItem(content: "Another short", isPinned: false)                         // Short Text
        ]
    }
    
    // MARK: - Category Filter Tests
    
    func testCategoryFilterURL() {
        // SPECS.md: URLカテゴリフィルター
        // Given
        XCTAssertEqual(viewModel.history.count, 10)
        
        // When: URLカテゴリのみ表示
        viewModel.toggleCategoryFilter(.url)
        
        // Then
        let filtered = viewModel.history
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.category == .url })
    }
    
    func testCategoryFilterEmail() {
        // When: Emailカテゴリのみ表示
        viewModel.toggleCategoryFilter(.email)
        
        // Then
        let filtered = viewModel.history
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.content, "test@example.com")
    }
    
    func testCategoryFilterKipple() {
        // SPECS.md: エディターからコピーされたテキスト（Kippleカテゴリ）
        // When
        viewModel.toggleCategoryFilter(.kipple)
        
        // Then
        let filtered = viewModel.history
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.content, "Editor content")
        XCTAssertTrue(filtered.first?.isFromEditor ?? false)
    }
    
    func testCategoryFilterAll() {
        // When: すべてのカテゴリ（フィルターなし）
        // デフォルト状態でフィルターは無効
        XCTAssertNil(viewModel.selectedCategory)
        XCTAssertFalse(viewModel.isPinnedFilterActive)
        
        // Then
        XCTAssertEqual(viewModel.history.count, 10)
    }
    
    // MARK: - Pinned Filter Tests
    
    func testPinnedFilter() {
        // SPECS.md: ピン留めフィルター
        // Given
        XCTAssertEqual(viewModel.history.count, 10)
        
        // When: ピン留めアイテムのみ表示
        viewModel.togglePinnedFilter()
        
        // Then
        let filtered = viewModel.history
        XCTAssertEqual(filtered.count, 3)
        XCTAssertTrue(filtered.allSatisfy { $0.isPinned })
    }
    
    func testCombinedCategoryAndPinnedFilter() {
        // When: URLカテゴリかつピン留めのみ
        // 注意: togglePinnedFilterはカテゴリフィルタをクリアするため、
        // 先にピンフィルタを設定してからカテゴリフィルタを設定する
        viewModel.togglePinnedFilter()
        viewModel.selectedCategory = .url
        viewModel.updateFilteredItems(mockClipboardService.history)
        
        // Then
        let filtered = viewModel.history
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.content, "https://test.com")
        XCTAssertTrue(filtered.first?.isPinned ?? false)
    }
    
    // MARK: - Search Tests
    // 検索機能はMainViewHistorySectionに実装されているため、
    // ここでは基本的なフィルタリングロジックのみをテスト
    
    // MARK: - Combined Filters Tests
    
    func testTogglePinnedFilter() {
        // togglePinnedFilterメソッドのテスト
        // When: ピンフィルターをトグル
        viewModel.togglePinnedFilter()
        
        // Then: ピンフィルターが有効になり、カテゴリフィルターがクリアされる
        XCTAssertTrue(viewModel.isPinnedFilterActive)
        XCTAssertNil(viewModel.selectedCategory)
        let filtered = viewModel.history
        XCTAssertEqual(filtered.count, 3)
        XCTAssertTrue(filtered.allSatisfy { $0.isPinned })
    }
    
    func testToggleCategoryFilter() {
        // toggleCategoryFilterメソッドのテスト
        // When: 同じカテゴリを再度選択
        viewModel.toggleCategoryFilter(.url)
        XCTAssertEqual(viewModel.selectedCategory, .url)
        
        viewModel.toggleCategoryFilter(.url)
        
        // Then: カテゴリフィルターがクリアされる
        XCTAssertNil(viewModel.selectedCategory)
        XCTAssertEqual(viewModel.history.count, 10)
    }
    
    // MARK: - Performance Tests
    
    func testCategoryFilterPerformance() {
        // Given: 各カテゴリの大量データ
        var largeHistory: [ClipItem] = []
        for i in 1...100 {
            largeHistory.append(ClipItem(content: "https://example\(i).com"))
            largeHistory.append(ClipItem(content: "test\(i)@example.com"))
            largeHistory.append(ClipItem(content: "func test\(i)() { }"))
            largeHistory.append(ClipItem(content: "/path/to/file\(i).txt"))
            largeHistory.append(ClipItem(content: "Short \(i)"))
            largeHistory.append(ClipItem(content: String(repeating: "Long \(i) ", count: 250)))
            largeHistory.append(ClipItem(content: "General text \(i)"))
            largeHistory.append(ClipItem(content: "Editor \(i)", isFromEditor: true))
        }
        mockClipboardService.history = largeHistory
        
        // Measure
        measure {
            viewModel.toggleCategoryFilter(.code)
            _ = viewModel.history
            // リセット
            viewModel.toggleCategoryFilter(.code)
        }
    }
}
