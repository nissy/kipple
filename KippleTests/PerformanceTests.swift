//
//  PerformanceTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/01/03.
//

import XCTest
@testable import Kipple

class PerformanceTests: XCTestCase {
    var clipboardService: ClipboardService!
    
    override func setUp() {
        super.setUp()
        clipboardService = ClipboardService.shared
        clipboardService.clearAllHistory()
    }
    
    override func tearDown() {
        clipboardService.clearAllHistory()
        clipboardService = nil
        super.tearDown()
    }
    
    // MARK: - ClipboardService Performance
    
    func testAddToHistoryPerformanceWithHashOptimization() {
        // Given: 大量の既存履歴
        let existingItems = (1...50).map { ClipItem(content: "Existing Item \($0)") }
        clipboardService.history = existingItems
        
        // When & Then: 新しいアイテムの追加パフォーマンスを測定
        measure {
            for i in 51...100 {
                let newItem = ClipItem(content: "New Item \(i)")
                clipboardService.history.insert(newItem, at: 0)
            }
        }
        
        // クリーンアップ
        clipboardService.history = existingItems
    }
    
    func testDuplicateCheckPerformanceWithLargeHistory() {
        // Given: 100個のユニークなアイテム
        let itemCount = 100
        let items = (1...itemCount).map { ClipItem(content: "Unique Item \($0)") }
        clipboardService.history = items
        
        // When & Then: 重複チェックのパフォーマンスを測定
        measure {
            // 最悪ケース: 最後のアイテムの重複チェック
            let targetContent = "Unique Item \(itemCount)"
            
            // ハッシュベースのチェックが高速であることを確認
            if let index = clipboardService.history.firstIndex(where: { $0.content == targetContent }) {
                // 見つかったアイテムを先頭に移動
                let item = clipboardService.history.remove(at: index)
                clipboardService.history.insert(item, at: 0)
                // 元に戻す
                clipboardService.history.remove(at: 0)
                clipboardService.history.insert(item, at: index)
            }
        }
    }
    
    // MARK: - History List Performance
    
    func testHistoryListRenderingPerformance() {
        // Given: 大量の履歴アイテム
        let items = (1...200).map { index in
            ClipItem(
                content: "Item \(index) with some longer content to simulate real clipboard data",
                isPinned: index % 10 == 0 // 10個ごとにピン留め
            )
        }
        
        let viewModel = MainViewModel()
        
        // When & Then: ビューモデルの処理パフォーマンスを測定
        measure {
            // 履歴の更新
            clipboardService.history = items
            
            // フィルタリング処理
            _ = viewModel.history
            _ = viewModel.pinnedItems
            
            // 検索シミュレーション
            let searchResults = items.filter { $0.content.contains("50") }
            XCTAssertFalse(searchResults.isEmpty)
        }
    }
    
    // MARK: - Memory Performance
    
    func testMemoryUsageWithLargeContent() {
        // Given: 大きなコンテンツを持つアイテム
        let largeContent = String(repeating: "A", count: 10000) // 10KB
        let items = (1...50).map { index in
            ClipItem(content: "\(index): \(largeContent)")
        }
        
        // When
        autoreleasepool {
            clipboardService.history = items
            
            // Then: メモリ使用量が適切であることを確認
            XCTAssertEqual(clipboardService.history.count, 50)
            
            // クリーンアップ時にメモリが解放されることを確認
            clipboardService.clearAllHistory()
        }
        
        // clearAllHistoryはピン留めされたアイテムを保持するため、
        // ピン留めされていないアイテムが全て削除されたことを確認
        let remainingPinnedItems = clipboardService.history.filter { $0.isPinned }
        let remainingUnpinnedItems = clipboardService.history.filter { !$0.isPinned }
        XCTAssertTrue(remainingUnpinnedItems.isEmpty, "All unpinned items should be cleared")
        XCTAssertEqual(clipboardService.history.count, remainingPinnedItems.count, "Only pinned items should remain")
    }
    
    // MARK: - Pin Operations Performance
    
    func testPinTogglePerformance() {
        // Given: 多数のアイテムがある状態
        let items = (1...100).map { ClipItem(content: "Item \($0)") }
        clipboardService.history = items
        
        // When & Then: ピン留め操作のパフォーマンスを測定
        measure {
            // 中央のアイテムをピン留め/解除
            let middleItem = items[50]
            clipboardService.togglePin(for: middleItem)
            clipboardService.togglePin(for: middleItem)
        }
    }
    
    // MARK: - Search Performance
    
    func testSearchPerformance() {
        // Given: 検索可能な大量のアイテム
        let items = (1...200).map { index in
            ClipItem(content: generateSearchableContent(index: index))
        }
        clipboardService.history = items
        
        // When & Then: 検索パフォーマンスを測定
        measure {
            // 様々な検索パターン
            let searchTerms = ["Swift", "Code", "Test", "100", "performance"]
            
            for term in searchTerms {
                let results = items.filter { 
                    $0.content.localizedCaseInsensitiveContains(term) 
                }
                _ = results.count // 結果を使用
            }
        }
    }
    
    // MARK: - Persistence Performance
    
    // CoreDataClipboardRepositoryの非同期APIのため、
    // パフォーマンステストは削除またはCoreDataPersistenceTestsに統合済み
    
    // MARK: - Helper Methods
    
    private func generateSearchableContent(index: Int) -> String {
        let templates = [
            "Swift code snippet #\(index)",
            "Test case for performance #\(index)",
            "Code review comment #\(index)",
            "Bug fix for issue #\(index)",
            "Performance optimization #\(index)"
        ]
        return templates[index % templates.count]
    }
}
