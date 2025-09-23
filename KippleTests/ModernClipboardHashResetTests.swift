import XCTest
@testable import Kipple

/// Regression tests for duplicate detection hash clearing on history operations

@MainActor
final class ModernClipboardHashResetTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!

    override func setUp() async throws {
        try await super.setUp()
        service = ModernClipboardService.shared
        await service.resetForTesting()
        adapter = ModernClipboardServiceAdapter.shared

        // Stop monitoring to avoid interference
        await service.stopMonitoring()

        // Clear history completely before each test
        await service.clearHistory(keepPinned: false)
        await service.flushPendingSaves()

        // Wait a bit for everything to settle
        try? await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        await service.clearAllHistory()
        await service.flushPendingSaves()
        try await super.tearDown()
    }

    /// Test that same content can be added after clearAllHistory
    func testDuplicateDetectionResetAfterClearAll() async throws {
        // Given: Add some content
        let testContent = "Test content for duplicate detection"
        await service.copyToClipboard(testContent, fromEditor: false)

        // Verify it was added
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.content, testContent)

        // When: Clear all history
        await service.clearAllHistory()

        // Then: Should be able to add the same content again
        await service.copyToClipboard(testContent, fromEditor: false)

        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Should be able to add same content after clearing history")
        XCTAssertEqual(history.first?.content, testContent)
    }

    /// Test that same content can be added after clearHistory(keepPinned: false)
    func testDuplicateDetectionResetAfterClearHistory() async throws {
        // Given: Add some content
        let testContent = "Content to test after clear"
        await service.copyToClipboard(testContent, fromEditor: false)

        // Verify it was added
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 1)

        // When: Clear history without keeping pinned
        await service.clearHistory(keepPinned: false)

        // Then: Should be able to add the same content again
        await service.copyToClipboard(testContent, fromEditor: false)

        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Should be able to add same content after clearing history")
        XCTAssertEqual(history.first?.content, testContent)
    }

    /// Test that same content can be added after clearHistory(keepPinned: true)
    func testDuplicateDetectionResetAfterClearHistoryKeepPinned() async throws {
        // Given: Add content and pin one item
        let pinnedContent = "Pinned content"
        let regularContent = "Regular content"

        await service.copyToClipboard(pinnedContent, fromEditor: false)
        await service.copyToClipboard(regularContent, fromEditor: false)

        // Pin the first item
        var history = await service.getHistory()
        if let pinnedItem = history.first(where: { $0.content == pinnedContent }) {
            _ = await service.togglePin(for: pinnedItem)
        }

        // When: Clear history keeping pinned
        await service.clearHistory(keepPinned: true)

        // Then: Should be able to add the regular content again
        await service.copyToClipboard(regularContent, fromEditor: false)

        history = await service.getHistory()
        XCTAssertTrue(history.contains { $0.content == regularContent },
                     "Should be able to add regular content after clearing with keepPinned")
        XCTAssertTrue(history.contains { $0.content == pinnedContent },
                     "Pinned content should remain")
    }

    /// Test that same content can be added after deleteItem
    func testDuplicateDetectionResetAfterDeleteItem() async throws {
        // Given: Add some content
        let testContent = "Content to delete and re-add"
        await service.copyToClipboard(testContent, fromEditor: false)

        // Get the item
        var history = await service.getHistory()
        guard let item = history.first else {
            XCTFail("No item in history")
            return
        }

        // When: Delete the item
        await service.deleteItem(item)

        // Then: Should be able to add the same content again
        await service.copyToClipboard(testContent, fromEditor: false)

        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Should be able to add same content after deleting it")
        XCTAssertEqual(history.first?.content, testContent)
    }

    /// Test multiple operations in sequence
    func testMultipleHistoryOperations() async throws {
        // Given: Add multiple items
        let contents = ["First", "Second", "Third"]
        for content in contents {
            await service.copyToClipboard(content, fromEditor: false)
        }

        // Clear all
        await service.clearAllHistory()

        // Should be able to add all contents again
        for content in contents {
            await service.copyToClipboard(content, fromEditor: false)
        }

        let history = await service.getHistory()
        XCTAssertEqual(history.count, 3, "Should be able to re-add all content after clear")

        // Verify all contents are present
        for content in contents {
            XCTAssertTrue(history.contains { $0.content == content },
                         "\(content) should be in history")
        }
    }

    /// Test auto-clear scenario
    func testDuplicateDetectionAfterAutoClear() async throws {
        // Given: Add content
        let testContent = "Auto-clear test content"
        await service.copyToClipboard(testContent, fromEditor: false)

        // Simulate auto-clear keeping pinned (as auto-clear does)
        await service.clearHistory(keepPinned: true)

        // Then: Should be able to add the same content again
        await service.copyToClipboard(testContent, fromEditor: false)

        let history = await service.getHistory()
        XCTAssertTrue(history.contains { $0.content == testContent },
                     "Should be able to add content after auto-clear")
    }

    /// Test that duplicate detection still works within a session
    func testDuplicateDetectionStillWorks() async throws {
        // Given: Add content
        let testContent = "Duplicate test"
        await service.copyToClipboard(testContent, fromEditor: false)

        // When: Try to add the same content again without clearing
        let historyBefore = await service.getHistory()
        await service.copyToClipboard(testContent, fromEditor: false)
        let historyAfter = await service.getHistory()

        // Then: Should not duplicate (item just moves to top)
        XCTAssertEqual(historyBefore.count, historyAfter.count,
                      "Duplicate detection should still prevent duplicates")
    }
}
