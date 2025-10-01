import XCTest
@testable import Kipple

/// Comprehensive tests for hash cleanup when deleting items

@MainActor
final class ModernClipboardHashCleanupTests: XCTestCase {
    private var service: ModernClipboardService!

    override func setUp() async throws {
        try await super.setUp()
        service = ModernClipboardService.shared
        await service.resetForTesting()

        // Stop monitoring to avoid interference
        await service.stopMonitoring()

        // Clear history completely before each test
        await service.clearHistory(keepPinned: false)
        await service.flushPendingSaves()

        // Wait a bit for everything to settle
        try? await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        await service.clearHistory(keepPinned: false)
        await service.flushPendingSaves()
        try await super.tearDown()
    }

    // MARK: - Individual Delete Tests

    /// Test that deleted item can be re-added
    func testDeletedItemCanBeReAdded() async throws {
        // Given: Add an item
        let testContent = "Item to delete and re-add"
        await service.copyToClipboard(testContent, fromEditor: false)

        // Verify it was added
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        guard let item = history.first else {
            XCTFail("No item in history")
            return
        }

        // When: Delete the item
        await service.deleteItem(item)

        // Verify it was deleted
        history = await service.getHistory()
        XCTAssertEqual(history.count, 0, "Item should be deleted")

        // Then: Should be able to add the same content again
        await service.copyToClipboard(testContent, fromEditor: false)

        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Should be able to re-add deleted content")
        XCTAssertEqual(history.first?.content, testContent)
    }

    /// Test multiple deletes and re-adds
    func testMultipleDeleteAndReAdd() async throws {
        // Given: Add multiple items
        let contents = ["First", "Second", "Third"]
        for content in contents {
            await service.copyToClipboard(content, fromEditor: false)
        }

        var history = await service.getHistory()
        XCTAssertEqual(history.count, 3)

        // When: Delete each item one by one and re-add
        for content in contents {
            // Find and delete
            history = await service.getHistory()
            if let item = history.first(where: { $0.content == content }) {
                await service.deleteItem(item)

                // Verify deleted
                history = await service.getHistory()
                XCTAssertFalse(history.contains { $0.content == content },
                              "\(content) should be deleted")

                // Re-add
                await service.copyToClipboard(content, fromEditor: false)

                // Verify re-added
                history = await service.getHistory()
                XCTAssertTrue(history.contains { $0.content == content },
                             "\(content) should be re-added")
            }
        }
    }

    // MARK: - Clear History Tests

    /// Test that cleared items can be re-added
    func testClearAllHistoryAllowsReAdd() async throws {
        // Given: Add items (mix of pinned and unpinned)
        let unpinnedContent = "Unpinned item"
        let pinnedContent = "Pinned item"

        await service.copyToClipboard(unpinnedContent, fromEditor: false)
        await service.copyToClipboard(pinnedContent, fromEditor: false)

        // Pin one item
        var history = await service.getHistory()
        if let pinnedItem = history.first(where: { $0.content == pinnedContent }) {
            _ = await service.togglePin(for: pinnedItem)
        }

        // When: Clear all history (keeps pinned)
        await service.clearAllHistory()

        // Then: Unpinned item can be re-added
        await service.copyToClipboard(unpinnedContent, fromEditor: false)

        history = await service.getHistory()
        XCTAssertTrue(history.contains { $0.content == unpinnedContent },
                     "Should be able to re-add cleared unpinned content")
        XCTAssertTrue(history.contains { $0.content == pinnedContent },
                     "Pinned content should remain")
    }

    /// Test clearHistory with keepPinned
    func testClearHistoryKeepPinnedAllowsReAdd() async throws {
        // Given: Add multiple items
        let contents = ["Item1", "Item2", "Item3"]
        for content in contents {
            await service.copyToClipboard(content, fromEditor: false)
        }

        // Pin the first item
        var history = await service.getHistory()
        if let firstItem = history.first(where: { $0.content == "Item1" }) {
            _ = await service.togglePin(for: firstItem)
        }

        // When: Clear history keeping pinned
        await service.clearHistory(keepPinned: true)

        // Then: Can re-add unpinned items
        await service.copyToClipboard("Item2", fromEditor: false)
        await service.copyToClipboard("Item3", fromEditor: false)

        history = await service.getHistory()
        XCTAssertTrue(history.contains { $0.content == "Item2" },
                     "Should be able to re-add Item2")
        XCTAssertTrue(history.contains { $0.content == "Item3" },
                     "Should be able to re-add Item3")
        XCTAssertTrue(history.contains { $0.content == "Item1" && $0.isPinned },
                     "Item1 should remain pinned")
    }

    /// Test clearHistory without keeping pinned
    func testClearHistoryNoKeepPinnedAllowsReAdd() async throws {
        // Given: Add and pin an item
        let testContent = "Pinned to be cleared"
        await service.copyToClipboard(testContent, fromEditor: false)

        var history = await service.getHistory()
        if let item = history.first {
            _ = await service.togglePin(for: item)
        }

        // When: Clear history not keeping pinned
        await service.clearHistory(keepPinned: false)

        // Then: Can re-add the same content
        await service.copyToClipboard(testContent, fromEditor: false)

        history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.content, testContent)
        XCTAssertFalse(history.first?.isPinned ?? true,
                      "Re-added content should not be pinned")
    }

    // MARK: - Update Item Tests

    /// Test that updating item content allows old content to be re-added
    func testUpdateItemContentAllowsOldContentReAdd() async throws {
        // Given: Add an item
        let originalContent = "Original content"
        await service.copyToClipboard(originalContent, fromEditor: false)

        var history = await service.getHistory()
        guard var item = history.first else {
            XCTFail("No item in history")
            return
        }

        // When: Update the item's content (this simulates editing)
        let updatedContent = "Updated content"
        item = ClipItem(
            id: item.id,
            content: updatedContent,
            timestamp: item.timestamp,
            isPinned: item.isPinned,
            kind: item.kind,
            sourceApp: item.sourceApp,
            windowTitle: item.windowTitle,
            bundleIdentifier: item.bundleIdentifier,
            processID: item.processID,
            isFromEditor: item.isFromEditor
        )
        await service.updateItem(item)

        // Then: Can re-add the original content
        await service.copyToClipboard(originalContent, fromEditor: false)

        history = await service.getHistory()
        XCTAssertTrue(history.contains { $0.content == originalContent },
                     "Should be able to re-add original content")
        XCTAssertTrue(history.contains { $0.content == updatedContent },
                     "Updated content should still exist")
    }

    // MARK: - Complex Scenarios

    /// Test rapid delete and re-add cycles
    func testRapidDeleteReAddCycles() async throws {
        let testContent = "Rapid cycle content"

        for cycle in 1...5 {
            // Add
            await service.copyToClipboard(testContent, fromEditor: false)

            var history = await service.getHistory()
            XCTAssertTrue(history.contains { $0.content == testContent },
                         "Cycle \(cycle): Content should be added")

            // Delete
            if let item = history.first(where: { $0.content == testContent }) {
                await service.deleteItem(item)
            }

            history = await service.getHistory()
            XCTAssertFalse(history.contains { $0.content == testContent },
                          "Cycle \(cycle): Content should be deleted")
        }

        // Final re-add should still work
        await service.copyToClipboard(testContent, fromEditor: false)
        let finalHistory = await service.getHistory()
        XCTAssertTrue(finalHistory.contains { $0.content == testContent },
                     "Final re-add should work")
    }

    /// Test delete with similar content
    func testDeleteWithSimilarContent() async throws {
        // Given: Add similar items
        let contents = [
            "Test content",
            "Test content with more",
            "Test content with even more"
        ]

        for content in contents {
            await service.copyToClipboard(content, fromEditor: false)
        }

        // When: Delete middle item
        var history = await service.getHistory()
        if let middleItem = history.first(where: { $0.content == contents[1] }) {
            await service.deleteItem(middleItem)
        }

        // Then: Can re-add the deleted item
        await service.copyToClipboard(contents[1], fromEditor: false)

        history = await service.getHistory()
        XCTAssertTrue(history.contains { $0.content == contents[1] },
                     "Should be able to re-add deleted middle item")

        // And all three should exist
        for content in contents {
            XCTAssertTrue(history.contains { $0.content == content },
                         "\(content) should exist in history")
        }
    }

    /// Test interaction between delete and pin
    func testDeletePinnedItemAllowsReAdd() async throws {
        // Given: Add and pin an item
        let testContent = "Pinned then deleted"
        await service.copyToClipboard(testContent, fromEditor: false)

        var history = await service.getHistory()
        guard let item = history.first else {
            XCTFail("No item in history")
            return
        }

        // Pin it
        _ = await service.togglePin(for: item)

        // When: Delete the pinned item
        await service.deleteItem(item)

        // Then: Can re-add the same content
        await service.copyToClipboard(testContent, fromEditor: false)

        history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.content, testContent)
        XCTAssertFalse(history.first?.isPinned ?? true,
                      "Re-added item should not be pinned")
    }

    /// Test that hash cleanup doesn't affect other operations
    func testHashCleanupDoesntBreakDuplicateDetection() async throws {
        // Given: Add an item
        let testContent = "Duplicate test"
        await service.copyToClipboard(testContent, fromEditor: false)

        // When: Try to add the same content again (without deleting)
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: Should not duplicate
        var history = await service.getHistory()
        XCTAssertEqual(history.filter { $0.content == testContent }.count, 1,
                      "Duplicate detection should still work")

        // When: Delete and re-add
        if let item = history.first(where: { $0.content == testContent }) {
            await service.deleteItem(item)
        }

        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: Should be able to add after delete
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.content, testContent)
    }
}
