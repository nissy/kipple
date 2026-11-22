import XCTest
@testable import Kipple

/// Regression tests for SwiftData persistence to ensure updates and deletions work correctly
@MainActor
final class SwiftDataPersistenceTests: XCTestCase {
    private var repository: SwiftDataRepository!

    override func setUp() async throws {
        try await super.setUp()
        // Create in-memory repository for testing
        repository = try SwiftDataRepository.make(inMemory: true)
    }

    override func tearDown() async throws {
        repository = nil
        try await super.tearDown()
    }

    // MARK: - Deletion Tests

    /// Test that deleted items don't resurrect after save and reload
    func testDeletedItemsDoNotResurrect() async throws {
        // Given: Add some items
        let item1 = ClipItem(content: "Item 1")
        let item2 = ClipItem(content: "Item 2")
        let item3 = ClipItem(content: "Item 3")

        var items = [item1, item2, item3]
        try await repository.replaceAll(with: items)

        // Verify all items are saved
        var loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 3, "Should have 3 items initially")

        // When: Remove item2 and save
        items.removeAll { $0.id == item2.id }
        try await repository.replaceAll(with: items)

        // Then: Item2 should not be in the repository
        loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 2, "Should have 2 items after deletion")
        XCTAssertFalse(loaded.contains { $0.id == item2.id },
                      "Deleted item should not resurrect")
        XCTAssertTrue(loaded.contains { $0.id == item1.id },
                     "Item1 should still exist")
        XCTAssertTrue(loaded.contains { $0.id == item3.id },
                     "Item3 should still exist")
    }

    /// Test that clearing history actually removes items
    func testClearHistoryRemovesItems() async throws {
        // Given: Add items
        let items = [
            ClipItem(content: "Clear Test 1"),
            ClipItem(content: "Clear Test 2"),
            ClipItem(content: "Clear Test 3")
        ]
        try await repository.save(items)

        // When: Clear by saving empty array
        try await repository.replaceAll(with: [])

        // Then: Repository should be empty
        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 0,
                      "Repository should be empty after clearing")
    }

    // MARK: - Update Tests

    /// Test that category changes persist
    func testCategoryChangePersists() async throws {
        // Given: Add an uncategorized item
        var item = ClipItem(content: "Category Test")
        try await repository.save([item])

        // Verify initial state
        var loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertFalse(loaded.first!.hasCustomCategory, "Should be uncategorized initially")

        // When: Add a category state and save
        item.setCategory(savedHistoryCategoryID, enabled: true)
        try await repository.save([item])

        // Then: Category should be updated
        loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertTrue(loaded.first!.hasCustomCategory,
                     "Category change should persist")
    }

    /// Test that metadata updates persist
    func testMetadataUpdatesPersist() async throws {
        // Given: Add item with initial metadata
        let item = ClipItem(
            content: "Metadata Test",
            sourceApp: "Initial App",
            windowTitle: "Initial Window"
        )
        try await repository.save([item])

        // When: Update metadata and save
        let updatedItem = ClipItem(
            id: item.id,
            content: item.content,
            timestamp: item.timestamp,
            kind: item.kind,
            sourceApp: "Updated App",
            windowTitle: "Updated Window",
            bundleIdentifier: item.bundleIdentifier,
            processID: item.processID,
            isFromEditor: item.isFromEditor,
            userCategoryId: savedHistoryCategoryID
        )
        try await repository.save([updatedItem])

        // Then: All changes should persist
        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 1)
        let loadedItem = loaded.first!
        XCTAssertEqual(loadedItem.sourceApp, "Updated App",
                      "Source app should be updated")
        XCTAssertEqual(loadedItem.windowTitle, "Updated Window",
                      "Window title should be updated")
        XCTAssertTrue(loadedItem.hasCustomCategory, "Category should be updated")
    }

    // MARK: - Mixed Operations Tests

    /// Test adding, updating, and deleting in a single save
    func testMixedOperations() async throws {
        // Given: Initial items
        let item1 = ClipItem(content: "Keep")
        var item2 = ClipItem(content: "Update")
        let item3 = ClipItem(content: "Delete")

        try await repository.save([item1, item2, item3])

        // When: Keep item1, update item2, delete item3, add item4
        item2.setCategory(savedHistoryCategoryID, enabled: true)
        let item4 = ClipItem(content: "New", userCategoryId: savedHistoryCategoryID)

        try await repository.replaceAll(with: [item1, item2, item4])

        // Then: Verify all operations worked
        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 3, "Should have 3 items")

        // Check item1 unchanged
        XCTAssertTrue(loaded.contains { $0.id == item1.id && !$0.hasCustomCategory },
                     "Item1 should be unchanged")

        // Check item2 updated
        XCTAssertTrue(loaded.contains { $0.id == item2.id && $0.hasCustomCategory },
                     "Item2 should be updated")

        // Check item3 deleted
        XCTAssertFalse(loaded.contains { $0.id == item3.id },
                      "Item3 should be deleted")

        // Check item4 added
        XCTAssertTrue(loaded.contains { $0.id == item4.id && $0.hasCustomCategory },
                     "Item4 should be added")
    }

    /// Test that history limit is enforced by deletion
    func testHistoryLimitEnforcement() async throws {
        // Given: Add 5 items
        var items: [ClipItem] = []
        for i in 1...5 {
            items.append(ClipItem(content: "Item \(i)"))
        }
        try await repository.save(items)

        // When: Enforce limit of 3 by keeping only first 3
        let limitedItems = Array(items.prefix(3))
        try await repository.replaceAll(with: limitedItems)

        // Then: Only 3 items should remain
        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 3,
                      "Should only have 3 items after limit enforcement")

        // Verify correct items remain
        let loadedIds = Set(loaded.map { $0.id })
        for item in limitedItems {
            XCTAssertTrue(loadedIds.contains(item.id),
                         "Item \(item.content) should remain")
        }
    }

    // MARK: - Edge Cases

    /// Test saving empty array clears all items
    func testSaveEmptyArrayClearsAll() async throws {
        // Given: Repository with items
        let items = [
            ClipItem(content: "Will be deleted 1"),
            ClipItem(content: "Will be deleted 2")
        ]
        try await repository.save(items)

        // When: Save empty array
        try await repository.replaceAll(with: [])

        // Then: Repository should be empty
        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 0,
                      "Saving empty array should clear all items")
    }

    /// Test that same ID with different content updates correctly
    func testSameIdDifferentContent() async throws {
        // Given: Add initial item
        let id = UUID()
        let item1 = ClipItem(
            id: id,
            content: "Original content",
            timestamp: Date(),
            kind: .text,
            sourceApp: nil,
            windowTitle: nil,
            bundleIdentifier: nil,
            processID: nil,
            isFromEditor: nil
        )
        try await repository.save([item1])

        // When: Save item with same ID but different content
        let item2 = ClipItem(
            id: id,
            content: "Updated content",
            timestamp: Date(),
            kind: .text,
            sourceApp: nil,
            windowTitle: nil,
            bundleIdentifier: nil,
            processID: nil,
            isFromEditor: nil,
            userCategoryId: savedHistoryCategoryID
        )
        try await repository.save([item2])

        // Then: Content should be updated
        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 1, "Should still have only one item")
        XCTAssertEqual(loaded.first?.id, id, "ID should remain the same")
        XCTAssertEqual(loaded.first?.content, "Updated content",
                      "Content should be updated")
        XCTAssertTrue(loaded.first?.hasCustomCategory ?? false,
                     "Category should be updated")
    }

    /// Test rapid successive saves maintain consistency
    func testRapidSuccessiveSaves() async throws {
        // Given: Initial state
        var items: [ClipItem] = []

        // When: Perform rapid operations
        for i in 1...10 {
            let item = ClipItem(content: "Rapid \(i)")
            items.append(item)

            // Keep only last 5 items
            if items.count > 5 {
                items.removeFirst()
            }

            try await repository.replaceAll(with: items)
        }

        // Then: Final state should be consistent
        let loaded = try await repository.loadAll()
        XCTAssertEqual(loaded.count, 5, "Should have exactly 5 items")

        // Verify content
        for i in 6...10 {
            XCTAssertTrue(loaded.contains { $0.content == "Rapid \(i)" },
                         "Should contain Rapid \(i)")
        }

        // Verify old items are gone
        for i in 1...5 {
            XCTAssertFalse(loaded.contains { $0.content == "Rapid \(i)" },
                          "Should not contain Rapid \(i)")
        }
    }
}
