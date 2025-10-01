//
//  RecopyRaceConditionTests.swift
//  KippleTests
//
//  Tests for recopy race condition
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class RecopyRaceConditionTests: XCTestCase {
    private var service: ModernClipboardService!
    
    override func setUp() async throws {
        try await super.setUp()
        
        service = ModernClipboardService.shared

        await service.resetForTesting()
    }

    override func tearDown() async throws {
        await service.resetForTesting()

        service = nil

        try await super.tearDown()
    }
    
    func testRecopyDoesNotCreateDuplicatesDuringMonitoring() async throws {
        // Given: Start monitoring
        await service.startMonitoring()
        
        // Add initial items
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.flushPendingSaves()
        
        // Wait for monitoring to settle
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        
        // When: Recopy an item from history
        let itemToRecopy = history[1] // Item 1
        await service.recopyFromHistory(itemToRecopy)
        await service.flushPendingSaves()
        
        // Give monitoring time to potentially detect the change
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Then: Should not have duplicates
        history = await service.getHistory()
        XCTAssertEqual(history.count, 2, "Should not create duplicates")
        XCTAssertEqual(history[0].content, "Item 1", "Item 1 should be at top")
        XCTAssertEqual(history[1].content, "Item 2")
        
        // Verify no duplicate Item 1 entries
        let item1Count = history.filter { $0.content == "Item 1" }.count
        XCTAssertEqual(item1Count, 1, "Should have only one Item 1")
        
        await service.stopMonitoring()
    }
    
    func testRapidRecopyDoesNotCauseDuplicates() async throws {
        // Given: Add items
        await service.copyToClipboard("Test Item", fromEditor: false)
        await service.copyToClipboard("Another Item", fromEditor: false)
        await service.flushPendingSaves()
        
        await service.startMonitoring()
        
        var history = await service.getHistory()
        let itemToRecopy = history[1] // Test Item
        
        // When: Rapidly recopy the same item multiple times
        for _ in 1...5 {
            await service.recopyFromHistory(itemToRecopy)
            // Minimal delay between recopies
            try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        }
        
        await service.flushPendingSaves()
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Then: Should still have only 2 items
        history = await service.getHistory()
        XCTAssertEqual(history.count, 2, "Should not create duplicates from rapid recopy")
        XCTAssertEqual(history[0].content, "Test Item")
        
        await service.stopMonitoring()
    }
    
    func testInternalCopyFlagPreventsMonitoringDetection() async throws {
        // Given: Start monitoring
        await service.startMonitoring()
        
        await service.copyToClipboard("Original", fromEditor: false)
        await service.flushPendingSaves()
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        
        // When: Set internal flag and copy to clipboard directly
        await service.setInternalOperation(true)
        
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("Should not be detected", forType: .string)
        }
        
        // Give monitoring time to potentially detect
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
        
        // Then: Should not add to history
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Internal copy should not be added to history")
        XCTAssertEqual(history[0].content, "Original")
        
        await service.stopMonitoring()
    }
}
