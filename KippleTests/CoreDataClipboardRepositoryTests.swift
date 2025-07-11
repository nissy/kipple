//
//  CoreDataClipboardRepositoryTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/11.
//

import XCTest
import CoreData
@testable import Kipple

final class CoreDataClipboardRepositoryTests: XCTestCase {
    var repository: CoreDataClipboardRepository!
    var testStack: CoreDataStack!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // テスト用のインメモリCore Dataスタックを作成
        testStack = await createTestCoreDataStack()
        repository = CoreDataClipboardRepository()
    }
    
    override func tearDown() async throws {
        // テストデータをクリア
        try await repository.clear(keepPinned: false)
        repository = nil
        testStack = nil
        try await super.tearDown()
    }
    
    func createTestCoreDataStack() async -> CoreDataStack {
        // 本番のCoreDataStackを使用（テスト用のインメモリ実装は今回は省略）
        return CoreDataStack.shared
    }
    
    func testSaveAndLoad() async throws {
        // Given
        // タイムスタンプを明示的に設定して順序を保証
        let baseDate = Date()
        let items = [
            ClipItem(
                id: UUID(),
                content: "Test 1",
                timestamp: baseDate.addingTimeInterval(-2),
                isPinned: false,
                kind: .text,
                sourceApp: nil,
                windowTitle: nil,
                bundleIdentifier: nil,
                processID: nil,
                isFromEditor: nil
            ),
            ClipItem(
                id: UUID(),
                content: "Test 2",
                timestamp: baseDate.addingTimeInterval(-1),
                isPinned: false,
                kind: .text,
                sourceApp: nil,
                windowTitle: nil,
                bundleIdentifier: nil,
                processID: nil,
                isFromEditor: nil
            ),
            ClipItem(
                id: UUID(),
                content: "Test 3",
                timestamp: baseDate,
                isPinned: false,
                kind: .text,
                sourceApp: nil,
                windowTitle: nil,
                bundleIdentifier: nil,
                processID: nil,
                isFromEditor: nil
            )
        ]
        
        // When
        try await repository.save(items)
        let loadedItems = try await repository.load(limit: 10)
        
        // Then
        XCTAssertEqual(loadedItems.count, 3)
        XCTAssertEqual(loadedItems[0].content, "Test 3") // 最新のアイテムが最初
        XCTAssertEqual(loadedItems[1].content, "Test 2")
        XCTAssertEqual(loadedItems[2].content, "Test 1")
    }
    
    func testLoadWithLimit() async throws {
        // Given
        let items = (1...10).map { ClipItem(content: "Item \($0)") }
        try await repository.save(items)
        
        // When
        let limitedItems = try await repository.load(limit: 5)
        
        // Then
        XCTAssertEqual(limitedItems.count, 5)
        XCTAssertEqual(limitedItems[0].content, "Item 10") // 最新のアイテムが最初
    }
    
    func testLoadAll() async throws {
        // Given
        let items = (1...100).map { ClipItem(content: "Item \($0)") }
        try await repository.save(items)
        
        // When
        let allItems = try await repository.loadAll()
        
        // Then
        XCTAssertEqual(allItems.count, 100)
    }
    
    func testDelete() async throws {
        // Given
        let item = ClipItem(content: "To be deleted")
        try await repository.save([item])
        
        // When
        try await repository.delete(item)
        let remaining = try await repository.load(limit: 10)
        
        // Then
        XCTAssertEqual(remaining.count, 0)
    }
    
    func testClearKeepPinned() async throws {
        // Given
        let pinnedItem = ClipItem(content: "Pinned", isPinned: true)
        let normalItems = [
            ClipItem(content: "Normal 1"),
            ClipItem(content: "Normal 2")
        ]
        try await repository.save([pinnedItem] + normalItems)
        
        // When
        try await repository.clear(keepPinned: true)
        let remaining = try await repository.load(limit: 10)
        
        // Then
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining[0].content, "Pinned")
        XCTAssertTrue(remaining[0].isPinned)
    }
    
    func testClearAll() async throws {
        // Given
        let items = [
            ClipItem(content: "Item 1", isPinned: true),
            ClipItem(content: "Item 2"),
            ClipItem(content: "Item 3")
        ]
        try await repository.save(items)
        
        // When
        try await repository.clear(keepPinned: false)
        let remaining = try await repository.load(limit: 10)
        
        // Then
        XCTAssertEqual(remaining.count, 0)
    }
    
    func testUpdateExistingItem() async throws {
        // Given
        var item = ClipItem(content: "Original")
        try await repository.save([item])
        
        // When
        item.isPinned = true
        try await repository.save([item])
        let updated = try await repository.load(limit: 1)
        
        // Then
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].content, "Original")
        XCTAssertTrue(updated[0].isPinned)
    }
    
    func testPerformanceLargeDataSet() async throws {
        // Given - 先にクリアしてクリーンな状態から開始
        try await repository.clear(keepPinned: false)
        let items = (1...1000).map { ClipItem(content: "Item \($0)") }
        
        // Measure save performance
        let saveStart = CFAbsoluteTimeGetCurrent()
        try await repository.save(items)
        let saveTime = CFAbsoluteTimeGetCurrent() - saveStart
        
        // Measure load performance
        let loadStart = CFAbsoluteTimeGetCurrent()
        let loaded = try await repository.load(limit: 100)
        let loadTime = CFAbsoluteTimeGetCurrent() - loadStart
        
        // Then
        XCTAssertEqual(loaded.count, 100)
        XCTAssertLessThan(saveTime, 5.0, "Save 1000 items should complete within 5 seconds")
        XCTAssertLessThan(loadTime, 0.5, "Load 100 items should complete within 500ms")
    }
    
    func testConcurrentOperations() async throws {
        // Given - クリーンな状態から開始
        try await repository.clear(keepPinned: false)
        
        // When: 複数の操作を並行実行
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    let items = [ClipItem(content: "Concurrent \(i)")]
                    try? await self.repository.save(items)
                }
            }
        }
        
        // Then
        let allItems = try await repository.loadAll()
        XCTAssertGreaterThanOrEqual(allItems.count, 1, "At least some items should be saved")
    }
}
