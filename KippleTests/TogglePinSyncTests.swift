//
//  TogglePinSyncTests.swift
//  KippleTests
//
//  Tests for toggle pin synchronization
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class TogglePinSyncTests: XCTestCase {
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
        
        // Reset max pinned items
        await MainActor.run {
            AppSettings.shared.maxPinnedItems = 10
        }
    }
    
    override func tearDown() async throws {
        await service.clearHistory(keepPinned: false)
        await service.stopMonitoring()
        
        service = nil
        adapter = nil
        
        try await super.tearDown()
    }
    
    func testTogglePinReturnsActualResult() async throws {
        // Given: Set max pinned to 2 and add items
        await MainActor.run {
            AppSettings.shared.maxPinnedItems = 2
        }
        
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.copyToClipboard("Item 3", fromEditor: false)
        await service.flushPendingSaves()

        // Wait for adapter to sync
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        let history = adapter.history
        XCTAssertEqual(history.count, 3)
        
        // When: Pin first two items
        let success1 = adapter.togglePin(for: history[0])
        XCTAssertTrue(success1, "First pin should succeed")
        
        // Wait for backend to update
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        let success2 = adapter.togglePin(for: history[1])
        XCTAssertTrue(success2, "Second pin should succeed")
        
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Then: Third pin should fail and return false immediately
        let success3 = adapter.togglePin(for: history[2])
        XCTAssertFalse(success3, "Third pin should fail due to limit")
        
        // Verify backend state matches
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        let serviceHistory = await service.getHistory()
        let pinnedCount = serviceHistory.filter { $0.isPinned }.count
        XCTAssertEqual(pinnedCount, 2, "Should have exactly 2 pinned items")
    }
    
    func testTogglePinConsistencyBetweenAdapterAndService() async throws {
        // Given: Add items
        await service.copyToClipboard("Test Item", fromEditor: false)
        await service.flushPendingSaves()

        // Wait for adapter to sync
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        let history = adapter.history
        let item = history[0]
        
        // When: Toggle pin
        let isPinned = adapter.togglePin(for: item)
        
        // Give time for backend to process
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Then: Service state should match returned value
        let serviceHistory = await service.getHistory()
        if let serviceItem = serviceHistory.first(where: { $0.id == item.id }) {
            XCTAssertEqual(serviceItem.isPinned, isPinned,
                          "Service state should match returned value")
        } else {
            XCTFail("Item not found in service history")
        }
    }
    
    func testUnpinReturnsCorrectResult() async throws {
        // Given: Add and pin an item
        await service.copyToClipboard("Item to unpin", fromEditor: false)
        await service.flushPendingSaves()

        // Wait for adapter to sync
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        let history = adapter.history
        let item = history[0]
        
        // Pin the item first
        let pinResult = adapter.togglePin(for: item)
        XCTAssertTrue(pinResult, "Should be able to pin")
        
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // When: Unpin the item
        let unpinResult = adapter.togglePin(for: item)
        XCTAssertFalse(unpinResult, "Should return false when unpinning")
        
        // Then: Verify it's actually unpinned
        try await Task.sleep(nanoseconds: 500_000_000)
        let serviceHistory = await service.getHistory()
        if let serviceItem = serviceHistory.first(where: { $0.id == item.id }) {
            XCTAssertFalse(serviceItem.isPinned, "Item should be unpinned")
        }
    }
}
