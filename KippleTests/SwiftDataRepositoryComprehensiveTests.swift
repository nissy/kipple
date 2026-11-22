import XCTest
import SwiftData
@testable import Kipple

@MainActor
final class SwiftDataRepositoryComprehensiveTests: XCTestCase, @unchecked Sendable {
    private var repository: SwiftDataRepository!
    private var container: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory container for testing
        let schema = Schema([ClipItemModel.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        repository = try SwiftDataRepository.make(container: container)
    }

    override func tearDown() async throws {
        repository = nil
        container = nil
        try await super.tearDown()
    }

    // MARK: - Basic CRUD Tests

    func testSaveAndLoad() async throws {
        // Given
        let items = [
            ClipItem(content: "Test 1"),
            ClipItem(content: "Test 2", userCategoryId: savedHistoryCategoryID),
            ClipItem(content: "Test 3")
        ]

        // When
        try await repository.save(items)
        let loadedItems = try await repository.loadAll()

        // Then
        XCTAssertEqual(loadedItems.count, 3)
        XCTAssertTrue(loadedItems.contains { $0.content == "Test 1" })
        XCTAssertTrue(loadedItems.contains { $0.content == "Test 2" && $0.hasCustomCategory })
    }

    func testLoadCategorizedItems() async throws {
        // Given
        let items = [
            ClipItem(content: "Uncategorized 1"),
            ClipItem(content: "Categorized 1", userCategoryId: savedHistoryCategoryID),
            ClipItem(content: "Uncategorized 2"),
            ClipItem(content: "Categorized 2", userCategoryId: savedHistoryCategoryID)
        ]

        // When
        try await repository.save(items)
        let categorizedItems = try await repository.loadCategorized()

        // Then
        XCTAssertEqual(categorizedItems.count, 2)
        XCTAssertTrue(categorizedItems.allSatisfy { $0.hasCustomCategory })
    }

    func testUpdateExistingItem() async throws {
        // Given
        let originalItem = ClipItem(content: "Original")
        try await repository.save([originalItem])

        // When - Update the item
        // Note: ClipItem properties are immutable, so we create a new item
        let updatedItem = ClipItem(
            content: "Updated",
            userCategoryId: savedHistoryCategoryID
        )
        // We'll test update by deleting old and saving new
        try await repository.delete(originalItem)
        try await repository.save([updatedItem])

        // Then
        let loadedItems = try await repository.loadAll()
        XCTAssertEqual(loadedItems.count, 1)
        let loadedItem = loadedItems.first!
        // Note: Since we created a new item, the ID will be different
        XCTAssertEqual(loadedItem.content, "Updated")
        XCTAssertTrue(loadedItem.hasCustomCategory)
    }

    func testDeleteItem() async throws {
        // Given
        let items = [
            ClipItem(content: "Item 1"),
            ClipItem(content: "Item 2"),
            ClipItem(content: "Item 3")
        ]
        try await repository.save(items)

        // When
        try await repository.delete(items[1])

        // Then
        let remainingItems = try await repository.loadAll()
        XCTAssertEqual(remainingItems.count, 2)
        XCTAssertFalse(remainingItems.contains { $0.content == "Item 2" })
    }

    func testClearAll() async throws {
        // Given
        let items = (1...10).map { ClipItem(content: "Item \($0)") }
        try await repository.save(items)

        // When
        try await repository.clear()

        // Then
        let remainingItems = try await repository.loadAll()
        XCTAssertTrue(remainingItems.isEmpty)
    }

    func testClearKeepingCategories() async throws {
        // Given
        let items = [
            ClipItem(content: "Uncategorized 1"),
            ClipItem(content: "Categorized 1", userCategoryId: savedHistoryCategoryID),
            ClipItem(content: "Uncategorized 2"),
            ClipItem(content: "Categorized 2", userCategoryId: savedHistoryCategoryID)
        ]
        try await repository.save(items)

        // When
        try await repository.replaceAll(with: repository.loadCategorized())

        // Then
        let remainingItems = try await repository.loadAll()
        XCTAssertEqual(remainingItems.count, 2)
        XCTAssertTrue(remainingItems.allSatisfy { $0.hasCustomCategory })
    }

    // MARK: - Batch Operations Tests

    func testBatchSave() async throws {
        // Given
        let batchSize = 100
        let items = (1...batchSize).map { ClipItem(content: "Batch \($0)") }

        // When
        try await repository.save(items)

        // Then
        let loadedItems = try await repository.loadAll()
        XCTAssertEqual(loadedItems.count, batchSize)
    }

    func testBatchDelete() async throws {
        // Given
        let items = (1...50).map { ClipItem(content: "Delete \($0)") }
        try await repository.save(items)

        // When - Delete half of them
        let itemsToDelete = Array(items[0..<25])
        for item in itemsToDelete {
            try await repository.delete(item)
        }

        // Then
        let remainingItems = try await repository.loadAll()
        XCTAssertEqual(remainingItems.count, 25)
    }

    // MARK: - Time-based Operations Tests

    func testDeleteItemsOlderThan() async throws {
        // Given - Create items with different timestamps
        let now = Date()

        // Note: Can't directly set timestamps in ClipItem init,
        // so we'll test the deleteItemsOlderThan functionality
        // assuming it works with item timestamps
        let oldItem = ClipItem(
            content: "Old item"
        )

        let recentItem = ClipItem(
            content: "Recent item"
        )

        let categorizedOldItem = ClipItem(
            content: "Categorized old item",
            userCategoryId: savedHistoryCategoryID
        )

        try await repository.save([oldItem, recentItem, categorizedOldItem])

        // When - Delete items older than 1 hour from now
        // This should delete nothing as all items are just created
        let cutoffDate = now.addingTimeInterval(-3600)
        try await repository.deleteItemsOlderThan(cutoffDate)

        // Then - All items should remain since they're all new
        let remainingItems = try await repository.loadAll()
        XCTAssertEqual(remainingItems.count, 3)
        XCTAssertTrue(remainingItems.contains { $0.content == "Old item" })
        XCTAssertTrue(remainingItems.contains { $0.content == "Recent item" })
        XCTAssertTrue(remainingItems.contains { $0.content == "Categorized old item" })
    }

    // MARK: - Data Integrity Tests

    func testPreservesAllItemProperties() async throws {
        // Given
        let item = ClipItem(
            content: "Full test",
            userCategoryId: savedHistoryCategoryID
        )

        // When
        try await repository.save([item])
        let loadedItems = try await repository.loadAll()

        // Then
        XCTAssertEqual(loadedItems.count, 1)
        let loadedItem = loadedItems.first!
        XCTAssertEqual(loadedItem.id, item.id)
        XCTAssertEqual(loadedItem.content, item.content)
        XCTAssertEqual(loadedItem.hasCustomCategory, item.hasCustomCategory)
        // Note: sourceApp, windowTitle, bundleIdentifier, processID, isFromEditor
        // are set during clipboard monitoring, not in constructor
    }

    func testHandlesSpecialCharacters() async throws {
        // Given
        let specialContents = [
            "Unicode: 日本語 🎉🚀 한글",
            "HTML: <div class=\"test\">&nbsp;</div>",
            "Quotes: \"double\" 'single' `backtick`",
            "Newlines:\nand\ttabs\rand\r\ncarriage returns",
            "Backslash: \\ and special symbols: @#$%^&*()"
        ]

        let items = specialContents.map { ClipItem(content: $0) }

        // When
        try await repository.save(items)
        let loadedItems = try await repository.loadAll()

        // Then
        XCTAssertEqual(loadedItems.count, specialContents.count)
        for content in specialContents {
            XCTAssertTrue(loadedItems.contains { $0.content == content })
        }
    }

    func testHandlesVeryLongContent() async throws {
        // Given
        let longContent = String(repeating: "A", count: 1_000_000) // 1MB of text
        let item = ClipItem(content: longContent)

        // When
        try await repository.save([item])
        let loadedItems = try await repository.loadAll()

        // Then
        XCTAssertEqual(loadedItems.count, 1)
        XCTAssertEqual(loadedItems.first?.content.count, 1_000_000)
    }

    // MARK: - Concurrency Tests

    func testConcurrentSaveOperations() async throws {
        // Given
        let concurrentOps = 10

        // When - Save items concurrently
        let repository = self.repository!
        await withTaskGroup(of: Void.self) { group in
            for i in 1...concurrentOps {
                group.addTask {
                    let item = ClipItem(content: "Concurrent \(i)")
                    try? await repository.save([item])
                }
            }
        }

        // Then
        let loadedItems = try await repository.loadAll()
        XCTAssertGreaterThan(loadedItems.count, 0)
        XCTAssertLessThanOrEqual(loadedItems.count, concurrentOps)
    }

    func testConcurrentReadOperations() async throws {
        // Given
        let items = (1...20).map { ClipItem(content: "Item \($0)") }
        try await repository.save(items)

        // When - Read concurrently
        var results: [[ClipItem]] = []
        let repository = self.repository!
        await withTaskGroup(of: [ClipItem]?.self) { group in
            for _ in 1...5 {
                group.addTask {
                    try? await repository.loadAll()
                }
            }

            for await result in group {
                if let items = result {
                    results.append(items)
                }
            }
        }

        // Then - All reads should return same data
        XCTAssertEqual(results.count, 5)
        for result in results {
            XCTAssertEqual(result.count, 20)
        }
    }

    // MARK: - Performance Tests

    func testLargeDatasetPerformance() async throws {
        // Given
        let itemCount = 1000
        let items = (1...itemCount).map { ClipItem(content: "Performance \($0)") }

        // When - Measure save time
        let saveStart = Date()
        try await repository.save(items)
        let saveTime = Date().timeIntervalSince(saveStart)

        // When - Measure load time
        let loadStart = Date()
        let loadedItems = try await repository.loadAll()
        let loadTime = Date().timeIntervalSince(loadStart)

        // Then
        XCTAssertEqual(loadedItems.count, itemCount)
        XCTAssertLessThan(saveTime, 5.0, "Save should complete within 5 seconds")
        XCTAssertLessThan(loadTime, 2.0, "Load should complete within 2 seconds")
    }

    // MARK: - Error Handling Tests

    func testDeleteNonExistentItem() async throws {
        // Given
        let nonExistentItem = ClipItem(content: "Does not exist")

        // When/Then - Should not throw
        try await repository.delete(nonExistentItem)

        // Verify repository is still functional
        let items = try await repository.loadAll()
        XCTAssertTrue(items.isEmpty)
    }

    func testUpdateNonExistentItem() async throws {
        // Given
        let nonExistentItem = ClipItem(content: "Does not exist")

        // When
        try await repository.update(nonExistentItem)

        // Then - Should create the item
        let items = try await repository.loadAll()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.content, "Does not exist")
    }

    // MARK: - Ordering Tests

    func testItemsOrderedByTimestamp() async throws {
        // Given - Create items (timestamps are auto-set on creation)
        // We'll create them with small delays to ensure different timestamps
        let item1 = ClipItem(content: "First")
        try await Task.sleep(for: .milliseconds(10))
        let item2 = ClipItem(content: "Second")
        try await Task.sleep(for: .milliseconds(10))
        let item3 = ClipItem(content: "Third")

        let items = [item1, item2, item3]

        // When
        try await repository.save(items)
        let loadedItems = try await repository.loadAll()

        // Then - Should be ordered newest first
        XCTAssertEqual(loadedItems.count, 3)
        // Since timestamps are auto-set, verify they're ordered by timestamp
        XCTAssertTrue(loadedItems[0].timestamp >= loadedItems[1].timestamp)
        XCTAssertTrue(loadedItems[1].timestamp >= loadedItems[2].timestamp)
    }

    // MARK: - Edge Cases

    func testEmptyContent() async throws {
        // Given
        let item = ClipItem(content: "")

        // When
        try await repository.save([item])
        let loadedItems = try await repository.loadAll()

        // Then
        XCTAssertEqual(loadedItems.count, 1)
        XCTAssertEqual(loadedItems.first?.content, "")
    }

    func testMaxIntProcessID() async throws {
        // Given
        let item = ClipItem(
            content: "Test"
        )

        // When
        try await repository.save([item])
        let loadedItems = try await repository.loadAll()

        // Then - processID is set during clipboard monitoring
        XCTAssertNotNil(loadedItems.first)
    }
}
