import XCTest
@testable import Kipple

/// Tests for pin state preservation when re-copying the same content

@MainActor
final class ModernClipboardPinPreservationTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!

    override func setUp() async throws {
        try await super.setUp()
        service = ModernClipboardService.shared
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
        await service.clearHistory(keepPinned: false)
        await service.flushPendingSaves()
        try await super.tearDown()
    }

    // MARK: - Core Pin Preservation Tests

    /// Test that re-copying pinned content preserves the pin state
    func testReCopyingPinnedContentPreservesPin() async throws {
        // Given: Add content and pin it
        let testContent = "Pinned content to re-copy"
        await service.copyToClipboard(testContent, fromEditor: false)

        // Get the item and pin it
        var history = await service.getHistory()
        guard let item = history.first else {
            XCTFail("No item in history")
            return
        }
        XCTAssertFalse(item.isPinned, "Should not be pinned initially")

        // Pin the item
        let pinResult = await service.togglePin(for: item)
        XCTAssertTrue(pinResult, "Pin toggle should return true")

        // Verify pin state
        history = await service.getHistory()
        XCTAssertTrue(history.first?.isPinned == true, "Item should be pinned")

        // When: Re-copy the same content
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: Pin state should be preserved
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Should still have one item")
        XCTAssertEqual(history.first?.content, testContent, "Content should match")
        XCTAssertTrue(history.first?.isPinned == true,
                     "Pin state should be preserved after re-copying")
    }

    /// Test that re-copying unpinned content keeps it unpinned
    func testReCopyingUnpinnedContentStaysUnpinned() async throws {
        // Given: Add unpinned content
        let testContent = "Regular unpinned content"
        await service.copyToClipboard(testContent, fromEditor: false)

        // Verify it's not pinned
        var history = await service.getHistory()
        XCTAssertFalse(history.first?.isPinned ?? true, "Should not be pinned")

        // When: Re-copy the same content
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: Should remain unpinned
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Should still have one item")
        XCTAssertFalse(history.first?.isPinned ?? true,
                      "Should remain unpinned after re-copying")
    }

    /// Test multiple re-copies of pinned content
    func testMultipleReCopiesPreservePin() async throws {
        // Given: Pinned content
        let testContent = "Content to copy multiple times"
        await service.copyToClipboard(testContent, fromEditor: false)

        // Pin it
        var history = await service.getHistory()
        if let item = history.first {
            _ = await service.togglePin(for: item)
        }

        // When: Re-copy multiple times
        for i in 1...5 {
            await service.copyToClipboard(testContent, fromEditor: false)

            // Then: Each time, pin should be preserved
            history = await service.getHistory()
            XCTAssertTrue(history.first?.isPinned == true,
                         "Pin should be preserved on copy #\(i)")
            XCTAssertEqual(history.count, 1,
                          "Should still have only one item after copy #\(i)")
        }
    }

    // MARK: - Mixed Operations

    /// Test pin preservation with multiple items
    func testPinPreservationWithMultipleItems() async throws {
        // Given: Multiple items with different pin states
        let content1 = "Pinned item 1"
        let content2 = "Regular item"
        let content3 = "Pinned item 2"

        // Add items
        await service.copyToClipboard(content1, fromEditor: false)
        await service.copyToClipboard(content2, fromEditor: false)
        await service.copyToClipboard(content3, fromEditor: false)

        // Pin first and third
        var history = await service.getHistory()
        if let item1 = history.first(where: { $0.content == content1 }) {
            _ = await service.togglePin(for: item1)
        }
        if let item3 = history.first(where: { $0.content == content3 }) {
            _ = await service.togglePin(for: item3)
        }

        // When: Re-copy each item
        await service.copyToClipboard(content1, fromEditor: false)
        await service.copyToClipboard(content2, fromEditor: false)
        await service.copyToClipboard(content3, fromEditor: false)

        // Then: Pin states should be preserved
        history = await service.getHistory()
        let item1After = history.first { $0.content == content1 }
        let item2After = history.first { $0.content == content2 }
        let item3After = history.first { $0.content == content3 }

        XCTAssertTrue(item1After?.isPinned == true,
                     "Content1 should remain pinned")
        XCTAssertFalse(item2After?.isPinned ?? true,
                      "Content2 should remain unpinned")
        XCTAssertTrue(item3After?.isPinned == true,
                     "Content3 should remain pinned")
    }

    /// Test that unpin then re-copy doesn't re-pin
    func testUnpinThenReCopyStaysUnpinned() async throws {
        // Given: Pinned content
        let testContent = "Content to unpin"
        await service.copyToClipboard(testContent, fromEditor: false)

        var history = await service.getHistory()
        if let item = history.first {
            _ = await service.togglePin(for: item)
        }

        // Verify it's pinned
        history = await service.getHistory()
        XCTAssertTrue(history.first?.isPinned == true, "Should be pinned")

        // When: Unpin it
        if let item = history.first {
            _ = await service.togglePin(for: item)
        }

        // Verify it's unpinned
        history = await service.getHistory()
        XCTAssertFalse(history.first?.isPinned ?? true, "Should be unpinned")

        // And re-copy
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: Should stay unpinned
        history = await service.getHistory()
        XCTAssertFalse(history.first?.isPinned ?? true,
                      "Should remain unpinned after re-copy")
    }

    // MARK: - From Editor Tests

    /// Test pin preservation for editor content
    func testPinPreservationFromEditor() async throws {
        // Given: Content from editor, pinned
        let testContent = "Editor content to pin"
        await service.copyToClipboard(testContent, fromEditor: true)

        var history = await service.getHistory()
        if let item = history.first {
            _ = await service.togglePin(for: item)
        }

        // When: Re-copy from editor
        await service.copyToClipboard(testContent, fromEditor: true)

        // Then: Pin should be preserved
        history = await service.getHistory()
        XCTAssertTrue(history.first?.isPinned == true,
                     "Pin should be preserved for editor content")
        XCTAssertEqual(history.first?.sourceApp, "Kipple",
                      "Should maintain editor source")
    }

    // MARK: - Clipboard Monitoring Tests

    /// Test pin preservation through clipboard monitoring
    func testPinPreservationDuringMonitoring() async throws {
        // Given: Start monitoring and add pinned content
        await service.startMonitoring()

        let testContent = "Monitored pinned content"
        await service.copyToClipboard(testContent, fromEditor: false)

        var history = await service.getHistory()
        if let item = history.first {
            _ = await service.togglePin(for: item)
        }

        // Verify pinned
        history = await service.getHistory()
        XCTAssertTrue(history.first?.isPinned == true, "Should be pinned")

        // When: Copy same content while monitoring
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: Pin should be preserved
        history = await service.getHistory()
        XCTAssertTrue(history.first?.isPinned == true,
                     "Pin should be preserved during monitoring")

        await service.stopMonitoring()
    }

    // MARK: - Edge Cases

    /// Test empty content handling
    func testEmptyContentPinPreservation() async throws {
        // Given: Empty content (edge case)
        let testContent = ""
        await service.copyToClipboard(testContent, fromEditor: false)

        var history = await service.getHistory()
        if let item = history.first {
            _ = await service.togglePin(for: item)
        }

        // When: Re-copy empty content
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: Pin should be preserved even for empty content
        history = await service.getHistory()
        XCTAssertTrue(history.first?.isPinned == true,
                     "Pin should be preserved for empty content")
    }

    /// Test very long content
    func testLongContentPinPreservation() async throws {
        // Given: Very long content
        let testContent = String(repeating: "Long ", count: 1000)
        await service.copyToClipboard(testContent, fromEditor: false)

        var history = await service.getHistory()
        if let item = history.first {
            _ = await service.togglePin(for: item)
        }

        // When: Re-copy long content
        await service.copyToClipboard(testContent, fromEditor: false)

        // Then: Pin should be preserved
        history = await service.getHistory()
        XCTAssertTrue(history.first?.isPinned == true,
                     "Pin should be preserved for long content")
    }
}
