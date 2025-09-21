import XCTest
import SwiftData
@testable import Kipple

@available(macOS 14.0, *)
final class SwiftDataRepositoryTests: XCTestCase {
    private var repository: SwiftDataRepository!
    private var modelContainer: ModelContainer!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory container for testing
        let schema = Schema([ClipItemModel.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        repository = try await MainActor.run {
            try SwiftDataRepository(container: modelContainer)
        }
    }

    override func tearDown() async throws {
        repository = nil
        modelContainer = nil
        try await super.tearDown()
    }

    func testSaveAndLoad() async throws {
        // Given
        let items = [
            ClipItem(content: "Test 1", isPinned: false),
            ClipItem(content: "Test 2", isPinned: true),
            ClipItem(content: "Test 3", isPinned: false)
        ]

        // When
        try await repository.save(items)
        let loaded = try await repository.load(limit: 10)

        // Then
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.first?.content, "Test 3") // Most recent first
        XCTAssertEqual(loaded[1].content, "Test 2")
        XCTAssertEqual(loaded[2].content, "Test 1")
    }

    func testLoadWithLimit() async throws {
        // Given
        let items = (1...10).map { ClipItem(content: "Item \($0)", isPinned: false) }
        try await repository.save(items)

        // When
        let loaded = try await repository.load(limit: 5)

        // Then
        XCTAssertEqual(loaded.count, 5)
        XCTAssertEqual(loaded.first?.content, "Item 10") // Most recent
        XCTAssertEqual(loaded.last?.content, "Item 6")
    }

    func testLoadAll() async throws {
        // Given
        let items = (1...20).map { ClipItem(content: "Item \($0)", isPinned: false) }
        try await repository.save(items)

        // When
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 20)
    }

    func testDelete() async throws {
        // Given
        let items = [
            ClipItem(content: "Keep 1", isPinned: false),
            ClipItem(content: "Delete Me", isPinned: false),
            ClipItem(content: "Keep 2", isPinned: false)
        ]
        try await repository.save(items)

        // When
        let deleteItem = items[1]
        try await repository.delete(deleteItem)
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 2)
        XCTAssertFalse(loaded.contains { $0.content == "Delete Me" })
        XCTAssertTrue(loaded.contains { $0.content == "Keep 1" })
        XCTAssertTrue(loaded.contains { $0.content == "Keep 2" })
    }

    func testClearAll() async throws {
        // Given
        let items = (1...5).map { ClipItem(content: "Item \($0)", isPinned: false) }
        try await repository.save(items)

        // When
        try await repository.clear()
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 0)
    }

    func testClearKeepPinned() async throws {
        // Given
        let items = [
            ClipItem(content: "Unpinned 1", isPinned: false),
            ClipItem(content: "Pinned 1", isPinned: true),
            ClipItem(content: "Unpinned 2", isPinned: false),
            ClipItem(content: "Pinned 2", isPinned: true)
        ]
        try await repository.save(items)

        // When
        try await repository.clear(keepPinned: true)
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 2)
        XCTAssertTrue(loaded.allSatisfy { $0.isPinned })
        XCTAssertTrue(loaded.contains { $0.content == "Pinned 1" })
        XCTAssertTrue(loaded.contains { $0.content == "Pinned 2" })
    }

    func testCountItems() async throws {
        // Given
        let items = (1...7).map { ClipItem(content: "Item \($0)", isPinned: false) }
        try await repository.save(items)

        // When
        let count = try await repository.countItems()

        // Then
        XCTAssertEqual(count, 7)
    }

    func testConcurrentAccess() async throws {
        // Test thread safety with concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    let item = ClipItem(content: "Concurrent \(i)", isPinned: false)
                    try? await self.repository.save([item])
                }
            }

            for _ in 1...5 {
                group.addTask {
                    _ = try? await self.repository.loadAll()
                }
            }
        }
    }

    // MARK: - Additional Comprehensive Tests

    func testUpdateExistingItem() async throws {
        // Given
        let originalItem = ClipItem(content: "Original", isPinned: false)
        try await repository.save([originalItem])

        // When - Update the same item
        var updatedItem = originalItem
        updatedItem.isPinned = true
        try await repository.update(updatedItem)
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, originalItem.id)
        XCTAssertTrue(loaded.first?.isPinned ?? false)
    }

    func testSaveDuplicateItems() async throws {
        // Given
        let item = ClipItem(content: "Duplicate Test", isPinned: false)

        // When - Save the same item twice
        try await repository.save([item])
        try await repository.save([item]) // Try to save again
        let loaded = try await repository.loadAll()

        // Then - Should not create duplicates
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "Duplicate Test")
    }

    func testLoadPinnedItems() async throws {
        // Given
        let items = [
            ClipItem(content: "Unpinned 1", isPinned: false),
            ClipItem(content: "Pinned 1", isPinned: true),
            ClipItem(content: "Unpinned 2", isPinned: false),
            ClipItem(content: "Pinned 2", isPinned: true),
            ClipItem(content: "Pinned 3", isPinned: true)
        ]
        try await repository.save(items)

        // When
        let pinnedItems = try await repository.loadPinned()

        // Then
        XCTAssertEqual(pinnedItems.count, 3)
        XCTAssertTrue(pinnedItems.allSatisfy { $0.isPinned })
    }

    func testItemWithSpecialCharacters() async throws {
        // Given - Items with special characters and emojis
        let specialItems = [
            ClipItem(content: "Test with 'quotes' and \"double quotes\"", isPinned: false),
            ClipItem(content: "Unicode: 日本語テスト 🚀🎉", isPinned: false),
            ClipItem(content: "Line\nbreaks\nand\ttabs", isPinned: false),
            ClipItem(content: "Special chars: <>&@#$%^*()", isPinned: false)
        ]

        // When
        try await repository.save(specialItems)
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 4)
        XCTAssertTrue(loaded.contains { $0.content.contains("日本語") })
        XCTAssertTrue(loaded.contains { $0.content.contains("🚀") })
    }

    func testLargeContentHandling() async throws {
        // Given - Very large content
        let largeContent = String(repeating: "Large content ", count: 10000)
        let item = ClipItem(content: largeContent, isPinned: false)

        // When
        try await repository.save([item])
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content.count, largeContent.count)
    }

    func testEmptyContentHandling() async throws {
        // Given
        let emptyItem = ClipItem(content: "", isPinned: false)

        // When
        try await repository.save([emptyItem])
        let loaded = try await repository.loadAll()

        // Then
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.content, "")
    }

    func testPerformanceOfLargeDataset() async throws {
        // Given - Large number of items
        let items = (1...1000).map { index in
            ClipItem(content: "Performance test item \(index)", isPinned: index % 10 == 0)
        }

        // When/Then - Measure performance
        let saveStart = Date()
        try await repository.save(items)
        let saveTime = Date().timeIntervalSince(saveStart)

        let loadStart = Date()
        let loaded = try await repository.loadAll()
        let loadTime = Date().timeIntervalSince(loadStart)

        XCTAssertEqual(loaded.count, 1000)
        XCTAssertLessThan(saveTime, 2.0, "Save should complete in less than 2 seconds")
        XCTAssertLessThan(loadTime, 1.0, "Load should complete in less than 1 second")
    }

    func testDataIntegrity() async throws {
        // Given
        let testDate = Date()
        let items = [
            ClipItem(
                id: UUID(),
                content: "Test Content",
                timestamp: testDate,
                isPinned: true,
                kind: .text,
                sourceApp: "TestApp",
                windowTitle: "TestWindow",
                bundleIdentifier: "com.test.app",
                processID: 12345,
                isFromEditor: true
            )
        ]

        // When
        try await repository.save(items)
        let loaded = try await repository.loadAll()

        // Then - Verify all properties are preserved
        let loadedItem = loaded.first
        XCTAssertNotNil(loadedItem)
        XCTAssertEqual(loadedItem?.content, "Test Content")
        XCTAssertEqual(loadedItem?.isPinned, true)
        XCTAssertEqual(loadedItem?.sourceApp, "TestApp")
        XCTAssertEqual(loadedItem?.windowTitle, "TestWindow")
        XCTAssertEqual(loadedItem?.bundleIdentifier, "com.test.app")
        XCTAssertEqual(loadedItem?.processID, 12345)
        XCTAssertEqual(loadedItem?.isFromEditor, true)
    }

    func testCleanupOldItems() async throws {
        // Given - Items with different timestamps
        let oldDate = Date().addingTimeInterval(-86400 * 30) // 30 days ago
        let recentDate = Date().addingTimeInterval(-3600) // 1 hour ago

        var oldItem = ClipItem(content: "Old item", isPinned: false)
        oldItem.timestamp = oldDate

        var recentItem = ClipItem(content: "Recent item", isPinned: false)
        recentItem.timestamp = recentDate

        try await repository.save([oldItem, recentItem])

        // When - Cleanup items older than 7 days
        let cutoffDate = Date().addingTimeInterval(-86400 * 7)
        try await repository.deleteItemsOlderThan(cutoffDate)
        let remaining = try await repository.loadAll()

        // Then
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.content, "Recent item")
    }
}
