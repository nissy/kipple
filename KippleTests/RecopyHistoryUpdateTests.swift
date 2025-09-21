//
//  RecopyHistoryUpdateTests.swift
//  KippleTests
//
//  Tests for clipboard history update behavior when recopying existing items
//

import XCTest
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class RecopyHistoryUpdateTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!

    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        adapter = ModernClipboardServiceAdapter.shared

        // Clear any existing data
        await service.clearAllHistory()
        await service.stopMonitoring()
    }

    override func tearDown() async throws {
        // Clean up
        await service.clearAllHistory()
        await service.stopMonitoring()

        service = nil
        adapter = nil

        try await super.tearDown()
    }

    // MARK: - Bug Reproduction Tests

    func testRecopyExistingItemMovesToTop() async throws {
        // Given: History with several items
        await service.copyToClipboard("First Item", fromEditor: false)
        await service.copyToClipboard("Second Item", fromEditor: false)
        await service.copyToClipboard("Third Item", fromEditor: false)

        // Wait for saves to complete
        await service.flushPendingSaves()

        let initialHistory = await service.getHistory()
        XCTAssertEqual(initialHistory.count, 3, "Should have 3 items")
        XCTAssertEqual(initialHistory[0].content, "Third Item", "Most recent should be at top")
        XCTAssertEqual(initialHistory[1].content, "Second Item")
        XCTAssertEqual(initialHistory[2].content, "First Item")

        // When: Recopy the first item
        await service.copyToClipboard("First Item", fromEditor: false)
        await service.flushPendingSaves()

        // Then: First Item should move to top
        let updatedHistory = await service.getHistory()
        XCTAssertEqual(updatedHistory.count, 3, "Should still have 3 items (no duplicates)")
        XCTAssertEqual(updatedHistory[0].content, "First Item", "Recopied item should move to top")
        XCTAssertEqual(updatedHistory[1].content, "Third Item", "Previous top should move down")
        XCTAssertEqual(updatedHistory[2].content, "Second Item", "Other items should maintain order")
    }

    func testRecopyMiddleItemMovesToTop() async throws {
        // Given: History with items
        for i in 1...5 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }
        await service.flushPendingSaves()

        // When: Recopy item from middle
        await service.copyToClipboard("Item 3", fromEditor: false)
        await service.flushPendingSaves()

        // Then: Item 3 should be at top
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 5, "Should maintain count")
        XCTAssertEqual(history[0].content, "Item 3", "Recopied item should be at top")

        // Verify no duplicates
        let item3Count = history.filter { $0.content == "Item 3" }.count
        XCTAssertEqual(item3Count, 1, "Should not create duplicates")
    }

    func testRecopyPreservesMetadata() async throws {
        // Given: Item with metadata
        await service.copyToClipboard("Metadata Test", fromEditor: true)
        await service.flushPendingSaves()

        let initialHistory = await service.getHistory()
        let originalItem = initialHistory[0]
        XCTAssertTrue(originalItem.isFromEditor ?? false, "Should preserve editor flag")

        // Add more items
        await service.copyToClipboard("Other Item 1", fromEditor: false)
        await service.copyToClipboard("Other Item 2", fromEditor: false)

        // When: Recopy the same text (not from editor this time)
        await service.copyToClipboard("Metadata Test", fromEditor: false)
        await service.flushPendingSaves()

        // Then: Item should move to top with updated metadata
        let updatedHistory = await service.getHistory()
        XCTAssertEqual(updatedHistory[0].content, "Metadata Test")
        XCTAssertFalse(updatedHistory[0].isFromEditor ?? true, "Metadata should be updated")
    }

    func testRecopyPinnedItemStaysPinned() async throws {
        // Given: Pinned item
        await service.copyToClipboard("Pinned Item", fromEditor: false)
        var history = await service.getHistory()
        _ = await service.togglePin(for: history[0])

        // Add more items
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.copyToClipboard("Item 3", fromEditor: false)

        // When: Recopy the pinned item
        await service.copyToClipboard("Pinned Item", fromEditor: false)
        await service.flushPendingSaves()

        // Then: Item should move to top and stay pinned
        history = await service.getHistory()
        XCTAssertEqual(history[0].content, "Pinned Item", "Should move to top")
        XCTAssertTrue(history[0].isPinned, "Should remain pinned")
    }

    // MARK: - Edge Cases

    func testRecopyEmptyString() async throws {
        // Given: History with empty string
        await service.copyToClipboard("", fromEditor: false)
        await service.copyToClipboard("Non-empty", fromEditor: false)
        await service.flushPendingSaves()

        // When: Recopy empty string
        await service.copyToClipboard("", fromEditor: false)
        await service.flushPendingSaves()

        // Then: Should handle gracefully (empty strings might be filtered)
        let history = await service.getHistory()
        // Empty strings are typically filtered out
        XCTAssertTrue(history.allSatisfy { !$0.content.isEmpty }, "Empty strings should be filtered")
    }

    func testRecopyVeryLongText() async throws {
        // Given: Long text in history
        let longText = String(repeating: "A", count: 10000)
        await service.copyToClipboard(longText, fromEditor: false)
        await service.copyToClipboard("Short", fromEditor: false)
        await service.flushPendingSaves()

        // When: Recopy long text
        await service.copyToClipboard(longText, fromEditor: false)
        await service.flushPendingSaves()

        // Then: Should move to top
        let history = await service.getHistory()
        XCTAssertEqual(history[0].content, longText, "Long text should move to top")
        XCTAssertEqual(history.filter { $0.content == longText }.count, 1, "No duplicates")
    }

    // MARK: - Performance

    func testRecopyPerformance() async throws {
        // Given: Large history
        for i in 1...100 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }
        await service.flushPendingSaves()

        // When: Recopy oldest item
        let startTime = Date()
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.flushPendingSaves()
        let duration = Date().timeIntervalSince(startTime)

        // Then: Should complete quickly
        XCTAssertLessThan(duration, 0.5, "Recopy should be fast")

        let history = await service.getHistory()
        XCTAssertEqual(history[0].content, "Item 1", "Item should move to top")
    }

    // MARK: - Adapter Integration

    func testRecopyThroughAdapter() async throws {
        // Given: Items added through adapter
        adapter.copyToClipboard("Adapter Item 1", fromEditor: false)
        adapter.copyToClipboard("Adapter Item 2", fromEditor: false)
        adapter.copyToClipboard("Adapter Item 3", fromEditor: false)

        // Wait for updates
        try await Task.sleep(nanoseconds: 500_000_000)

        // When: Recopy through adapter
        adapter.copyToClipboard("Adapter Item 1", fromEditor: false)
        try await Task.sleep(nanoseconds: 500_000_000)

        // Then: Should update in adapter's history
        let history = adapter.history
        XCTAssertEqual(history[0].content, "Adapter Item 1", "Should move to top in adapter")
        XCTAssertEqual(history.filter { $0.content == "Adapter Item 1" }.count, 1, "No duplicates in adapter")
    }

    // MARK: - Monitoring Mode

    func testRecopyWhileMonitoring() async throws {
        // Given: Monitoring enabled with items
        await service.startMonitoring()

        await service.copyToClipboard("Monitor 1", fromEditor: false)
        await service.copyToClipboard("Monitor 2", fromEditor: false)
        await service.copyToClipboard("Monitor 3", fromEditor: false)
        await service.flushPendingSaves()

        // When: Recopy while monitoring
        await service.copyToClipboard("Monitor 1", fromEditor: false)
        await service.flushPendingSaves()

        // Then: Should update correctly
        let history = await service.getHistory()
        XCTAssertEqual(history[0].content, "Monitor 1", "Should update during monitoring")
        XCTAssertEqual(history.filter { $0.content == "Monitor 1" }.count, 1, "No duplicates")

        await service.stopMonitoring()
    }
}
