//
//  AutoClearHistoryPreservationTests.swift
//  KippleTests
//
//  Tests that auto-clear preserves history
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class AutoClearHistoryPreservationTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!
    
    override func setUp() async throws {
        try await super.setUp()
        
        service = ModernClipboardService.shared
        await service.resetForTesting()
        adapter = ModernClipboardServiceAdapter.shared
        
        // Clear any existing data
        await service.clearHistory(keepPinned: false)
        await service.stopMonitoring()
        await service.flushPendingSaves()
        
        // Stop any existing auto-clear timer
        adapter.stopAutoClearTimer()
    }
    
    override func tearDown() async throws {
        // Stop auto-clear timer
        adapter.stopAutoClearTimer()
        
        // Clean up
        await service.clearHistory(keepPinned: false)
        await service.stopMonitoring()
        
        service = nil
        adapter = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Auto Clear Tests
    
    func testAutoClearPreservesHistory() async throws {
        // Given: Add items to history
        let items = [
            "First item",
            "Second item",
            "Third item"
        ]
        
        for content in items {
            await service.copyToClipboard(content, fromEditor: false)
        }
        await service.flushPendingSaves()
        
        // Verify history is populated
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 3, "Should have 3 items in history")
        
        // Copy something to system clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Test content", forType: .string)
        
        // Verify clipboard has content
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Test content")
        
        // When: Trigger auto-clear directly
        await adapter.performAutoClear()
        
        // Wait a moment for async operations
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then: History should be preserved
        history = await service.getHistory()
        XCTAssertEqual(history.count, 3, "History should still have 3 items")
        XCTAssertEqual(history[0].content, "Third item")
        XCTAssertEqual(history[1].content, "Second item")
        XCTAssertEqual(history[2].content, "First item")
        
        // And: System clipboard should be cleared
        XCTAssertNil(NSPasteboard.general.string(forType: .string), "Clipboard should be cleared")
    }
    
    func testAutoClearPreservesPinnedItems() async throws {
        // Given: Add items and pin one
        await service.copyToClipboard("Regular item 1", fromEditor: false)
        await service.copyToClipboard("Item to pin", fromEditor: false)
        await service.copyToClipboard("Regular item 2", fromEditor: false)
        await service.flushPendingSaves()
        
        var history = await service.getHistory()
        let itemToPin = history[1] // "Item to pin"
        _ = await service.togglePin(for: itemToPin)
        await service.flushPendingSaves()
        
        // Copy something to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Clipboard content", forType: .string)
        
        // When: Perform auto-clear
        await adapter.performAutoClear()
        
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then: All history including pinned items should be preserved
        history = await service.getHistory()
        XCTAssertEqual(history.count, 3, "Should still have all 3 items")
        
        let pinnedItems = history.filter { $0.isPinned }
        XCTAssertEqual(pinnedItems.count, 1, "Pinned item should be preserved")
        XCTAssertEqual(pinnedItems[0].content, "Item to pin")
        
        // And: Clipboard should be cleared
        XCTAssertNil(NSPasteboard.general.string(forType: .string), "Clipboard should be cleared")
    }
    
    func testAutoClearTimerIntegration() async throws {
        // Given: Add items to history
        await service.copyToClipboard("History item 1", fromEditor: false)
        await service.copyToClipboard("History item 2", fromEditor: false)
        await service.flushPendingSaves()
        
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        
        // Copy to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Temporary clipboard", forType: .string)
        
        // When: Start auto-clear timer with 1 second (for testing)
        adapter.autoClearRemainingTime = 1 // Set to 1 second directly for testing
        
        // Manually trigger what happens when timer reaches 0
        await adapter.performAutoClear()
        adapter.stopAutoClearTimer()
        
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then: History should be intact
        history = await service.getHistory()
        XCTAssertEqual(history.count, 2, "History should be preserved after auto-clear")
        XCTAssertEqual(history[0].content, "History item 2")
        XCTAssertEqual(history[1].content, "History item 1")
        
        // And: Clipboard should be empty
        XCTAssertNil(NSPasteboard.general.string(forType: .string), "Clipboard should be cleared")
    }
    
    func testAutoClearOnlyAffectsTextContent() async throws {
        // Given: History with items
        await service.copyToClipboard("Text item", fromEditor: false)
        await service.flushPendingSaves()
        
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        
        // Put non-text content on clipboard (e.g., file URL)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(Data(), forType: .fileURL)
        
        // When: Perform auto-clear
        await adapter.performAutoClear()
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Then: History should be preserved
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "History should be preserved")
        
        // Non-text content might still be on clipboard (auto-clear skips non-text)
        // This is expected behavior based on the implementation
    }
}
