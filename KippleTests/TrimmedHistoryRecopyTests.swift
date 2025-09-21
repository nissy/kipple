//
//  TrimmedHistoryRecopyTests.swift
//  KippleTests
//
//  Tests for recopy behavior after history trimming
//

import XCTest
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class TrimmedHistoryRecopyTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!
    
    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        adapter = ModernClipboardServiceAdapter.shared

        // Clear any existing data (including pinned items)
        await service.clearHistory(keepPinned: false)
        await service.stopMonitoring()
        await service.flushPendingSaves()

        // Wait for clean state
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
    }
    
    override func tearDown() async throws {
        // Clean up (including pinned items)
        await service.clearHistory(keepPinned: false)
        await service.stopMonitoring()
        
        // Reset max history items to default
        await service.setMaxHistoryItems(300)
        
        service = nil
        adapter = nil
        
        try await super.tearDown()
    }
    
    // MARK: - History Trimming Tests
    
    func testRecopyAfterHistoryTrimming() async throws {
        // Given: Set a very low max history (3 items)
        await service.setMaxHistoryItems(3)
        
        // Add 5 items to exceed the limit
        let items = [
            "First content",
            "Second content",
            "Third content",
            "Fourth content",
            "Fifth content"
        ]
        
        for content in items {
            await service.copyToClipboard(content, fromEditor: false)
        }
        await service.flushPendingSaves()
        
        // Verify only last 3 items remain
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 3, "History should be trimmed to 3 items")
        XCTAssertEqual(history[0].content, "Fifth content")
        XCTAssertEqual(history[1].content, "Fourth content")
        XCTAssertEqual(history[2].content, "Third content")
        
        // When: Re-copy the first content that was trimmed
        print("Before re-copy: \(history.map { $0.content })")
        await service.copyToClipboard("First content", fromEditor: false)
        await service.flushPendingSaves()

        // Then: First content should be added back to history
        history = await service.getHistory()
        print("After re-copy: \(history.map { $0.content })")
        XCTAssertEqual(history.count, 3, "History should still be limited to 3 items")
        XCTAssertEqual(history[0].content, "First content", "Re-copied content should be at top")
        XCTAssertEqual(history[1].content, "Fifth content")
        XCTAssertEqual(history[2].content, "Fourth content")
    }
    
    func testMultipleRecopyAfterTrimming() async throws {
        // Given: Set max history to 2
        await service.setMaxHistoryItems(2)
        
        // Add multiple items
        let items = ["A", "B", "C", "D"]
        for content in items {
            await service.copyToClipboard(content, fromEditor: false)
        }
        await service.flushPendingSaves()
        
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].content, "D")
        XCTAssertEqual(history[1].content, "C")
        
        // When: Re-copy trimmed items
        await service.copyToClipboard("A", fromEditor: false)
        await service.flushPendingSaves()
        
        history = await service.getHistory()
        XCTAssertEqual(history[0].content, "A", "Item A should be re-added")
        
        await service.copyToClipboard("B", fromEditor: false)
        await service.flushPendingSaves()
        
        history = await service.getHistory()
        XCTAssertEqual(history[0].content, "B", "Item B should be re-added")
    }
    
    func testPinnedItemsPreservedDuringTrimming() async throws {
        // Given: Set max history to 3
        await service.setMaxHistoryItems(3)
        
        // Add items and pin one
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.flushPendingSaves()
        
        var history = await service.getHistory()
        let itemToPin = history[1] // Item 1
        _ = await service.togglePin(for: itemToPin)
        
        // Add more items to trigger trimming
        await service.copyToClipboard("Item 3", fromEditor: false)
        await service.copyToClipboard("Item 4", fromEditor: false)
        await service.copyToClipboard("Item 5", fromEditor: false)
        await service.flushPendingSaves()
        
        // Then: Pinned item should be preserved
        history = await service.getHistory()
        XCTAssertEqual(history.count, 3)
        
        let pinnedItems = history.filter { $0.isPinned }
        XCTAssertEqual(pinnedItems.count, 1, "Pinned item should be preserved")
        XCTAssertEqual(pinnedItems[0].content, "Item 1")
        
        // When: Re-copy a trimmed unpinned item
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.flushPendingSaves()
        
        // Then: Should be able to add it back
        history = await service.getHistory()
        XCTAssertEqual(history[0].content, "Item 2", "Should be able to re-add trimmed item")
    }
    
    func testRecopyIdenticalContentAfterTrimming() async throws {
        // Given: Set max to 2 and add items
        await service.setMaxHistoryItems(2)
        
        let content = "Repeated content"
        await service.copyToClipboard(content, fromEditor: false)
        await service.copyToClipboard("Other 1", fromEditor: false)
        await service.copyToClipboard("Other 2", fromEditor: false)
        await service.flushPendingSaves()
        
        // Verify original content is gone
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertFalse(history.contains { $0.content == content }, "Original should be trimmed")
        
        // When: Copy the same content again
        await service.copyToClipboard(content, fromEditor: false)
        await service.flushPendingSaves()
        
        // Then: Should be added to history
        history = await service.getHistory()
        XCTAssertEqual(history[0].content, content, "Content should be re-added after trimming")
    }
    
    func testDynamicMaxHistoryChange() async throws {
        // Given: Start with max 5
        await service.setMaxHistoryItems(5)
        
        for i in 1...5 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }
        await service.flushPendingSaves()
        
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 5)
        
        // When: Reduce max to 2
        await service.setMaxHistoryItems(2)
        
        // Then: History should be trimmed
        history = await service.getHistory()
        XCTAssertEqual(history.count, 2, "History should be trimmed to new max")
        XCTAssertEqual(history[0].content, "Item 5")
        XCTAssertEqual(history[1].content, "Item 4")
        
        // And: Should be able to re-add trimmed items
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.flushPendingSaves()
        
        history = await service.getHistory()
        XCTAssertEqual(history[0].content, "Item 1", "Should be able to re-add Item 1")
    }
}
