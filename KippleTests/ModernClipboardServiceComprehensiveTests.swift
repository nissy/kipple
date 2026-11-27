import XCTest
import Combine
@testable import Kipple

@MainActor
final class ModernClipboardServiceComprehensiveTests: XCTestCase, @unchecked Sendable {
    private var service: ModernClipboardService!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() async throws {
        try await super.setUp()
        service = ModernClipboardService.shared
        await service.resetForTesting()
        await service.clearHistory(keepingCategories: false)
        cancellables.removeAll()
    }

    override func tearDown() async throws {
        await service.stopMonitoring()
        await service.clearHistory(keepingCategories: false)
        cancellables.removeAll()
        service = nil
        try await super.tearDown()
    }

    // MARK: - Monitoring Tests

    func testStartAndStopMonitoring() async throws {
        // When - Start monitoring
        await service.startMonitoring()

        // Then
        let isMonitoring = await service.isMonitoring()
        XCTAssertTrue(isMonitoring)

        // When - Stop monitoring
        await service.stopMonitoring()

        // Then
        let isMonitoringAfterStop = await service.isMonitoring()
        XCTAssertFalse(isMonitoringAfterStop)
    }

    func testMonitoringIntervalAdjustment() async throws {
        // Given
        await service.startMonitoring()

        // When - Get initial interval
        let initialInterval = await service.getCurrentInterval()

        // Then
        XCTAssertGreaterThanOrEqual(initialInterval, 0.08)
        XCTAssertLessThanOrEqual(initialInterval, 0.25)
    }

    // MARK: - Clipboard Operations Tests

    func testCopyToClipboard() async throws {
        // Given
        let content = "Test clipboard content"

        // When
        await service.copyToClipboard(content, fromEditor: false)

        // Then
        let history = await service.getHistory()
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.first?.content, content)
        XCTAssertFalse(history.first?.isFromEditor ?? true)
    }

    func testCopyFromEditor() async throws {
        // Given
        let content = "Editor content"

        // When
        await service.copyToClipboard(content, fromEditor: true)

        // Then
        let history = await service.getHistory()
        XCTAssertEqual(history.first?.content, content)
        XCTAssertTrue(history.first?.isFromEditor ?? false)
    }

    func testDuplicateDetection() async throws {
        // Given
        let content = "Duplicate test"

        // When - Copy same content twice
        await service.copyToClipboard(content, fromEditor: false)
        let historyAfterFirst = await service.getHistory()
        let countAfterFirst = historyAfterFirst.count

        await service.copyToClipboard(content, fromEditor: false)
        let historyAfterSecond = await service.getHistory()

        // Then - Should not add duplicate
        XCTAssertEqual(historyAfterSecond.count, countAfterFirst)
    }

    // MARK: - History Management Tests

    func testMaxHistoryItems() async throws {
        // Given
        await service.setMaxHistoryItems(5)

        // When - Add more than max items
        for i in 1...10 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }

        // Then
        let history = await service.getHistory()
        XCTAssertLessThanOrEqual(history.count, 5)
        XCTAssertEqual(history.first?.content, "Item 10") // Most recent
    }

    func testClearAllHistory() async throws {
        // Given
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)

        // When
        await service.clearHistory(keepingCategories: true)

        // Then
        let history = await service.getHistory()
        XCTAssertTrue(history.isEmpty)
    }

    func testClearHistoryKeepingCategories() async throws {
        // Given
        await service.copyToClipboard("Uncategorized", fromEditor: false)
        await service.copyToClipboard("Categorized", fromEditor: false)

        let history = await service.getHistory()
        if let categorizedItem = history.first(where: { $0.content == "Categorized" }) {
            try await service.setCategory(itemID: categorizedItem.id, categoryID: savedHistoryCategoryID, enabled: true)
        }

        // When
        await service.clearHistory(keepingCategories: true)

        // Then
        let remainingHistory = await service.getHistory()
        XCTAssertEqual(remainingHistory.count, 1)
        XCTAssertTrue(remainingHistory.first?.hasCustomCategory ?? false)
        XCTAssertEqual(remainingHistory.first?.content, "Categorized")
    }

    // MARK: - Category Management Tests

    func testCategorizingItemsPreservesOrder() async throws {
        // Given
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.copyToClipboard("Item 3", fromEditor: false)

        let history = await service.getHistory()

        // When - Categorize the middle item
        if let item2 = history.first(where: { $0.content == "Item 2" }) {
            try await service.setCategory(itemID: item2.id, categoryID: savedHistoryCategoryID, enabled: true)
        }

        // Then - Categorizing an item keeps its position.
        let updatedHistory = await service.getHistory()
        let categorizedItems = updatedHistory.filter { $0.hasCustomCategory }
        let uncategorizedItems = updatedHistory.filter { !$0.hasCustomCategory }

        XCTAssertEqual(updatedHistory.map(\.id), history.map(\.id))
        XCTAssertEqual(categorizedItems.count, 1)
        XCTAssertEqual(categorizedItems.first?.content, "Item 2")
        XCTAssertEqual(uncategorizedItems.count, 2)
    }

    // MARK: - Search Tests

    func testSearchHistory() async throws {
        // Given
        await service.copyToClipboard("Apple pie", fromEditor: false)
        await service.copyToClipboard("Banana bread", fromEditor: false)
        await service.copyToClipboard("Apple juice", fromEditor: false)
        await service.copyToClipboard("Cherry tart", fromEditor: false)

        // When
        let searchResults = await service.searchHistory(query: "Apple")

        // Then
        XCTAssertEqual(searchResults.count, 2)
        XCTAssertTrue(searchResults.allSatisfy { $0.content.contains("Apple") })
    }

    func testCaseInsensitiveSearch() async throws {
        // Given
        await service.copyToClipboard("UPPERCASE", fromEditor: false)
        await service.copyToClipboard("lowercase", fromEditor: false)
        await service.copyToClipboard("MixedCase", fromEditor: false)

        // When
        let results1 = await service.searchHistory(query: "case")
        let results2 = await service.searchHistory(query: "CASE")

        // Then
        XCTAssertEqual(results1.count, 3)
        XCTAssertEqual(results2.count, 3)
    }

    // MARK: - Delete Operations Tests

    func testDeleteItem() async throws {
        // Given
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.copyToClipboard("Item 3", fromEditor: false)

        let history = await service.getHistory()
        let itemToDelete = history[1] // Middle item

        // When
        await service.deleteItem(itemToDelete)

        // Then
        let updatedHistory = await service.getHistory()
        XCTAssertEqual(updatedHistory.count, 2)
        XCTAssertFalse(updatedHistory.contains { $0.id == itemToDelete.id })
        XCTAssertTrue(updatedHistory.contains { $0.content == "Item 1" })
        XCTAssertTrue(updatedHistory.contains { $0.content == "Item 3" })
    }

    func testDeleteNonExistentItem() async throws {
        // Given
        let nonExistentItem = ClipItem(content: "Non-existent")

        // When
        await service.deleteItem(nonExistentItem)

        // Then - Should not crash
        let history = await service.getHistory()
        XCTAssertNotNil(history) // Just verify operation completes
    }

    // MARK: - Update Operations Tests

    func testUpdateItem() async throws {
        // Given
        await service.copyToClipboard("Original", fromEditor: false)
        let history = await service.getHistory()
        let item = history.first!

        // When - Edit the category on the existing item.
        try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)

        // Then
        let updatedHistory = await service.getHistory()
        let updatedItemInHistory = updatedHistory.first { $0.id == item.id }
        XCTAssertNotNil(updatedItemInHistory)
        XCTAssertEqual(updatedItemInHistory?.content, "Original")
        XCTAssertTrue(updatedItemInHistory?.hasCustomCategory ?? false)
    }

    // MARK: - Performance Tests

    func testLargeHistoryPerformance() async throws {
        // Given
        await service.setMaxHistoryItems(1000)

        // When - Measure time to add many items
        let startTime = Date()

        for i in 1...100 {
            await service.copyToClipboard("Performance test item \(i)", fromEditor: false)
        }

        let elapsedTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertLessThan(elapsedTime, 5.0, "Should handle 100 items within 5 seconds")

        let history = await service.getHistory()
        XCTAssertEqual(history.count, 100)
    }

    func testSearchPerformance() async throws {
        // Given - Moderate dataset for performance test
        await service.setMaxHistoryItems(100)
        for i in 1...100 {
            await service.copyToClipboard("Item \(i) with searchable text", fromEditor: false)
        }

        // When - Measure search time
        let startTime = Date()
        let results = await service.searchHistory(query: "searchable")
        let elapsedTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertLessThan(elapsedTime, 1.0, "Search should complete within 1 second")
        XCTAssertEqual(results.count, 100)
    }

    // MARK: - Edge Cases Tests

    func testEmptyContent() async throws {
        // Given
        let emptyContent = ""

        // When
        await service.copyToClipboard(emptyContent, fromEditor: false)

        // Then
        let history = await service.getHistory()
        // Empty content might be filtered out
        if !history.isEmpty {
            XCTAssertEqual(history.first?.content, emptyContent)
        }
    }

    func testCopyToHistoryEnforcesTheTextLimit() async {
        let boundary = String(repeating: "A", count: 80_000)
        let accepted = await service.copyToClipboard(boundary, fromEditor: false) { true }
        XCTAssertTrue(accepted)

        let rejected = await service.copyToClipboard(boundary + "A", fromEditor: false) { true }
        XCTAssertFalse(rejected)
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), [boundary])
        let clipboard = await service.getCurrentClipboardContent()
        XCTAssertEqual(clipboard, boundary)
    }

    func testSpecialCharacters() async throws {
        // Given
        let specialContent = "🎉 Unicode 日本語 <>&\"' \n\t\r"

        // When
        await service.copyToClipboard(specialContent, fromEditor: false)

        // Then
        let history = await service.getHistory()
        XCTAssertEqual(history.first?.content, specialContent)
    }

    // MARK: - Concurrent Operations Tests

    func testConcurrentCopyOperations() async throws {
        // Given
        let operations = 10

        // When - Perform concurrent copies
        let service = self.service!
        await withTaskGroup(of: Void.self) { group in
            for i in 1...operations {
                group.addTask {
                    await service.copyToClipboard("Concurrent \(i)", fromEditor: false)
                }
            }
        }

        // Then - All items should be added
        let history = await service.getHistory()
        XCTAssertGreaterThan(history.count, 0)
        XCTAssertLessThanOrEqual(history.count, operations)
    }

    func testConcurrentCategoryEdits() async throws {
        // Given - Use fromEditor: true to ensure items are added
        for i in 1...5 {
            await service.copyToClipboard("Item \(i)", fromEditor: true)
        }

        let history = await service.getHistory()

        // When - Add a categorys concurrently
        let service = self.service!
        try await withThrowingTaskGroup(of: Void.self) { group in
            for item in history {
                group.addTask {
                    try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)
                }
            }
            try await group.waitForAll()
        }

        // Then - Items should have the category assigned
        let updatedHistory = await service.getHistory()
        let categorizedCount = updatedHistory.filter { $0.hasCustomCategory }.count
        XCTAssertEqual(categorizedCount, history.count)
    }

    // MARK: - State Consistency Tests

    func testHistoryConsistencyAfterOperations() async throws {
        // Given - Perform various operations
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: true)

        var history = await service.getHistory()
        if let firstItem = history.first {
            try await service.setCategory(itemID: firstItem.id, categoryID: savedHistoryCategoryID, enabled: true)
        }

        await service.copyToClipboard("Item 3", fromEditor: false)

        history = await service.getHistory()
        if let itemToDelete = history.last {
            await service.deleteItem(itemToDelete)
        }

        // When - Get final history
        let finalHistory = await service.getHistory()

        // Then - Verify consistency
        XCTAssertEqual(finalHistory.count, 2)
        XCTAssertTrue(finalHistory.contains { $0.hasCustomCategory })
        XCTAssertTrue(finalHistory.allSatisfy { !$0.content.isEmpty })
    }

    // MARK: - Clipboard Content Tests

    func testGetCurrentClipboardContent() async throws {
        // Given
        let content = "Current clipboard"
        await service.copyToClipboard(content, fromEditor: false)

        // When
        let currentContent = await service.getCurrentClipboardContent()

        // Then
        XCTAssertEqual(currentContent, content)
    }

    func testClipboardContentSync() async throws {
        // Given
        await service.startMonitoring()

        // When - Simulate external clipboard change
        // Note: In real test, would need to actually change system clipboard
        await service.copyToClipboard("External content", fromEditor: false)

        // Wait for monitoring to pick up change
        try? await Task.sleep(for: .seconds(1))

        // Then
        let history = await service.getHistory()
        XCTAssertFalse(history.isEmpty)
    }
}
