//
//  DuplicateRecopyTests.swift
//  KippleTests
//
//  Tests for duplicate content recopy functionality
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class DuplicateRecopyTests: XCTestCase {
    private var service: ModernClipboardService!
    
    override func setUp() async throws {
        try await super.setUp()
        
        service = ModernClipboardService.shared
        
        // Clear any existing data
        await service.clearHistory(keepPinned: false)
        await service.stopMonitoring()
        await service.flushPendingSaves()
    }
    
    override func tearDown() async throws {
        await service.clearHistory(keepPinned: false)
        await service.stopMonitoring()
        
        service = nil
        
        try await super.tearDown()
    }
    
    func testSameContentCanBeRecopied() async throws {
        // Given: Copy same content multiple times
        let content = "Test Content"
        
        // First copy
        await service.copyToClipboard(content, fromEditor: false)
        await service.flushPendingSaves()
        
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].content, content)
        
        // Add other items
        await service.copyToClipboard("Other 1", fromEditor: false)
        await service.copyToClipboard("Other 2", fromEditor: false)
        await service.flushPendingSaves()
        
        history = await service.getHistory()
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].content, "Other 2")
        
        // When: Copy the same content again
        await service.copyToClipboard(content, fromEditor: false)
        await service.flushPendingSaves()
        
        // Then: Content should move to top
        history = await service.getHistory()
        XCTAssertEqual(history.count, 3, "Should not create duplicate")
        XCTAssertEqual(history[0].content, content, "Same content should move to top")
        XCTAssertEqual(history[1].content, "Other 2")
        XCTAssertEqual(history[2].content, "Other 1")
    }
    
    func testDeletedContentCanBeRecopied() async throws {
        // Given: Add and delete content
        let content = "Will be deleted"
        await service.copyToClipboard(content, fromEditor: false)
        await service.copyToClipboard("Keep this", fromEditor: false)
        await service.flushPendingSaves()
        
        var history = await service.getHistory()
        let itemToDelete = history[1] // "Will be deleted"
        await service.deleteItem(itemToDelete)
        await service.flushPendingSaves()
        
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].content, "Keep this")
        
        // When: Re-copy the deleted content
        await service.copyToClipboard(content, fromEditor: false)
        await service.flushPendingSaves()
        
        // Then: Should be added again
        history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].content, content, "Deleted content should be re-added")
    }
    
    func testTrimmedContentCanBeRecopied() async throws {
        // Given: Set low max and exceed it
        await service.setMaxHistoryItems(2)
        
        await service.copyToClipboard("First", fromEditor: false)
        await service.copyToClipboard("Second", fromEditor: false)
        await service.copyToClipboard("Third", fromEditor: false)
        await service.flushPendingSaves()
        
        // "First" should be trimmed
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertFalse(history.contains { $0.content == "First" })
        
        // When: Re-copy trimmed content
        await service.copyToClipboard("First", fromEditor: false)
        await service.flushPendingSaves()
        
        // Then: Should be added
        history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].content, "First", "Trimmed content should be re-added")
        
        // Reset max
        await service.setMaxHistoryItems(300)
    }
}
