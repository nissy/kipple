import XCTest
@testable import Kipple

/// Tests for category preservation when re-copying the same content

@MainActor
final class ModernClipboardCategoryPreservationTests: XCTestCase {
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
        await service.clearHistory(keepingCategories: false)
        await service.flushPendingSaves()

        // Wait a bit for everything to settle
        try? await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        await service.clearHistory(keepingCategories: false)
        await service.flushPendingSaves()
        try await super.tearDown()
    }

    // MARK: - Category Preservation Tests

    /// Test that re-copying categorized content preserves the category
    func testRecopyingCategorizedContentPreservesCategory() async throws {
        // Given: Add content and categorize it
        let testContent = "Categorized content to re-copy"
        await service.copyToClipboard(testContent, fromEditor: false)

        // Get the item and categorize it
        var history = await service.getHistory()
        guard let item = history.first else {
            XCTFail("No item in history")
            return
        }
        XCTAssertFalse(item.hasCustomCategory, "Should not be categorized initially")

        // Assign the category
        try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)

        // Verify category
        history = await service.getHistory()
        XCTAssertTrue(history.first?.hasCustomCategory == true, "Item should be categorized")

        // When: Re-copy the same content
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: Category should be preserved
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Should still have one item")
        XCTAssertEqual(history.first?.content, testContent, "Content should match")
        XCTAssertTrue(history.first?.hasCustomCategory == true,
                     "Category should be preserved after re-copying")
    }

    /// Test that re-copying uncategorized content keeps it uncategorized
    func testReCopyingUncategorizedContentStaysUncategorized() async throws {
        // Given: Add uncategorized content
        let testContent = "Regular uncategorized content"
        await service.copyToClipboard(testContent, fromEditor: false)

        // Verify it's not categorized
        var history = await service.getHistory()
        XCTAssertFalse(history.first?.hasCustomCategory ?? true, "Should not be categorized")

        // When: Re-copy the same content
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: Should remain uncategorized
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Should still have one item")
        XCTAssertFalse(history.first?.hasCustomCategory ?? true,
                      "Should remain uncategorized after re-copying")
    }

    /// Test multiple re-copies of categorized content
    func testMultipleRecopiesPreserveCategory() async throws {
        // Given: Categorized content
        let testContent = "Content to copy multiple times"
        await service.copyToClipboard(testContent, fromEditor: false)

        // Assign the category
        var history = await service.getHistory()
        if let item = history.first {
            try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)
        }

        // When: Re-copy multiple times
        for i in 1...5 {
            await service.copyToClipboard(testContent, fromEditor: false)

            // Then: Each time, the category should be preserved
            history = await service.getHistory()
            XCTAssertTrue(history.first?.hasCustomCategory == true,
                         "The category should be preserved on copy #\(i)")
            XCTAssertEqual(history.count, 1,
                          "Should still have only one item after copy #\(i)")
        }
    }

    // MARK: - Mixed Operations

    /// Test category preservation with multiple items
    func testCategoryPreservationWithMultipleItems() async throws {
        // Given: Multiple items with different categorys
        let content1 = "Categorized item 1"
        let content2 = "Regular item"
        let content3 = "Categorized item 2"

        // Add items
        await service.copyToClipboard(content1, fromEditor: false)
        await service.copyToClipboard(content2, fromEditor: false)
        await service.copyToClipboard(content3, fromEditor: false)

        // Categorize the first and third items
        var history = await service.getHistory()
        if let item1 = history.first(where: { $0.content == content1 }) {
            try await service.setCategory(itemID: item1.id, categoryID: savedHistoryCategoryID, enabled: true)
        }
        if let item3 = history.first(where: { $0.content == content3 }) {
            try await service.setCategory(itemID: item3.id, categoryID: savedHistoryCategoryID, enabled: true)
        }

        // When: Re-copy each item
        await service.copyToClipboard(content1, fromEditor: false)
        await service.copyToClipboard(content2, fromEditor: false)
        await service.copyToClipboard(content3, fromEditor: false)

        // Then: Categorys should be preserved
        history = await service.getHistory()
        let item1After = history.first { $0.content == content1 }
        let item2After = history.first { $0.content == content2 }
        let item3After = history.first { $0.content == content3 }

        XCTAssertTrue(item1After?.hasCustomCategory == true,
                     "Content1 should remain categorized")
        XCTAssertFalse(item2After?.hasCustomCategory ?? true,
                      "Content2 should remain uncategorized")
        XCTAssertTrue(item3After?.hasCustomCategory == true,
                     "Content3 should remain categorized")
    }

    /// Test that recopying does not restore a removed category
    func testRemovingCategoryAndCopyingAgainDoesNotRestoreCategory() async throws {
        // Given: Categorized content
        let testContent = "Content with a removable category"
        await service.copyToClipboard(testContent, fromEditor: false)

        var history = await service.getHistory()
        if let item = history.first {
            try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)
        }

        // Verify it's categorized
        history = await service.getHistory()
        XCTAssertTrue(history.first?.hasCustomCategory == true, "Should be categorized")

        // When: Remove the category.
        if let item = history.first {
            try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: false)
        }

        // Verify it's uncategorized
        history = await service.getHistory()
        XCTAssertFalse(history.first?.hasCustomCategory ?? true, "Should be uncategorized")

        // And re-copy
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: Should stay uncategorized
        history = await service.getHistory()
        XCTAssertFalse(history.first?.hasCustomCategory ?? true,
                      "Should remain uncategorized after re-copy")
    }

    // MARK: - From Editor Tests

    /// Test category preservation for editor content
    func testCategoryPreservationFromEditor() async throws {
        // Given: Content from editor, categorized
        let testContent = "Categorized editor content"
        await service.copyToClipboard(testContent, fromEditor: true)

        var history = await service.getHistory()
        if let item = history.first {
            try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)
        }

        // When: Re-copy from editor
        await service.copyToClipboard(testContent, fromEditor: true)

        // Then: The category should be preserved
        history = await service.getHistory()
        XCTAssertTrue(history.first?.hasCustomCategory == true,
                     "The category should be preserved for editor content")
        XCTAssertEqual(history.first?.sourceApp, "Kipple",
                      "Should maintain editor source")
    }

    // MARK: - Clipboard Monitoring Tests

    /// Test category preservation through clipboard monitoring
    func testCategoryPreservationDuringMonitoring() async throws {
        // Given: Start monitoring and add categorized content
        await service.startMonitoring()

        let testContent = "Monitored categorized content"
        await service.copyToClipboard(testContent, fromEditor: false)

        var history = await service.getHistory()
        if let item = history.first {
            try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)
        }

        // Verify categorized
        history = await service.getHistory()
        XCTAssertTrue(history.first?.hasCustomCategory == true, "Should be categorized")

        // When: Copy same content while monitoring
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: The category should be preserved
        history = await service.getHistory()
        XCTAssertTrue(history.first?.hasCustomCategory == true,
                     "The category should be preserved during monitoring")

        await service.stopMonitoring()
    }

    // MARK: - Edge Cases

    /// Test empty content is ignored
    func testEmptyContentCategoryPreservation() async throws {
        // Given: Empty content (edge case)
        let testContent = ""
        await service.copyToClipboard(testContent, fromEditor: false)

        let history = await service.getHistory()
        XCTAssertTrue(history.isEmpty, "Empty content should be ignored")
    }

    /// Test very long content
    func testLongContentCategoryPreservation() async throws {
        // Given: Very long content
        let testContent = String(repeating: "Long ", count: 1000)
        await service.copyToClipboard(testContent, fromEditor: false)

        var history = await service.getHistory()
        if let item = history.first {
            try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)
        }

        // When: Re-copy long content
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: The category should be preserved
        history = await service.getHistory()
        XCTAssertTrue(history.first?.hasCustomCategory == true,
                     "The category should be preserved for long content")
    }
}
