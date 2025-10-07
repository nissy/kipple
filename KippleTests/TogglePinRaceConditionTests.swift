//
//  TogglePinRaceConditionTests.swift
//  KippleTests
//
//  Tests for toggle pin race condition issues
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class TogglePinRaceConditionTests: XCTestCase, @unchecked Sendable {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!
    private var repository: ClipboardRepositoryProtocol!
    
    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        repository = try SwiftDataRepository.make(inMemory: true)
        await service.useTestingRepository(repository)
        await service.resetForTesting()
        adapter = ModernClipboardServiceAdapter.shared

        await adapter.clearHistory(keepPinned: false)
        await adapter.flushPendingSaves()
        try await Task.sleep(nanoseconds: 500_000_000)
    }
    
    override func tearDown() async throws {
        // Clean up
        await service.resetForTesting()
        await adapter.clearHistory(keepPinned: false)

        service = nil
        adapter = nil
        repository = nil
        RepositoryProvider.useTestingRepository(nil)
        
        try await super.tearDown()
    }

    private func waitForHistory(count: Int, timeout: TimeInterval = 2.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if adapter.history.count >= count {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
    
    // MARK: - Race Condition Tests
    
    func testTogglePinConsistency() async throws {
        // Given: Add multiple items
        let items = [
            ClipItem(content: "Item 1"),
            ClipItem(content: "Item 2"),
            ClipItem(content: "Item 3")
        ]
        
        for item in items {
            await service.copyToClipboard(item.content, fromEditor: false)
        }
        await service.flushPendingSaves()
        try? await Task.sleep(for: .seconds(0.3))

        // When: Toggle pin state of an item
        let historyBefore = adapter.history
        XCTAssertEqual(historyBefore.count, 3)
        
        let itemToPin = historyBefore[0]
        let isPinned = adapter.togglePin(for: itemToPin)
        
        // Give async operation time to complete
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Then: State should be consistent between adapter and service
        let serviceHistory = await service.getHistory()
        let adapterHistory = adapter.history
        
        // Both should have the same pinned state
        if let serviceItem = serviceHistory.first(where: { $0.id == itemToPin.id }),
           let adapterItem = adapterHistory.first(where: { $0.id == itemToPin.id }) {
            XCTAssertEqual(serviceItem.isPinned, adapterItem.isPinned,
                          "Pin state should be consistent between service and adapter")
            XCTAssertEqual(serviceItem.isPinned, isPinned,
                          "Returned pin state should match actual state")
        } else {
            XCTFail("Item not found in history")
        }
    }
    
    func testTogglePinMaxLimitEnforcement() async throws {
        // Given: Set max pinned items to 2
        await MainActor.run {
            AppSettings.shared.maxPinnedItems = 2
        }
        
        // Add multiple items
        for i in 1...5 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }
        await service.flushPendingSaves()
        await waitForHistory(count: 5)

        let history = adapter.history
        XCTAssertEqual(history.count, 5)
        
        // When: Pin items up to limit
        let success1 = adapter.togglePin(for: history[0])
        XCTAssertTrue(success1, "First pin should succeed")
        
        let success2 = adapter.togglePin(for: history[1])
        XCTAssertTrue(success2, "Second pin should succeed")
        
        // Try to pin beyond limit
        let success3 = adapter.togglePin(for: history[2])
        XCTAssertFalse(success3, "Third pin should fail due to limit")
        
        // Give async operations time to complete
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // Then: Only 2 items should be pinned
        let serviceHistory = await service.getHistory()
        let pinnedCount = serviceHistory.filter { $0.content.hasPrefix("Item") && $0.isPinned }.count
        XCTAssertEqual(pinnedCount, 2, "Should have exactly 2 pinned items")

        // Adapter should also show 2 pinned items
        let adapterPinnedCount = adapter.history.filter { $0.content.hasPrefix("Item") && $0.isPinned }.count
        XCTAssertEqual(adapterPinnedCount, 2, "Adapter should show 2 pinned items")
    }
    
    func testTogglePinRollbackOnFailure() async throws {
        // Given: Set max pinned items to 1
        await MainActor.run {
            AppSettings.shared.maxPinnedItems = 1
        }
        
        // Add items
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.flushPendingSaves()
        await waitForHistory(count: 2)

        // Pin first item
        let history = adapter.history
        let success1 = adapter.togglePin(for: history[1]) // Pin Item 1
        XCTAssertTrue(success1)
        
        // Wait for async operation
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // When: Try to pin second item (should fail)
        let success2 = adapter.togglePin(for: history[0]) // Try to pin Item 2
        XCTAssertFalse(success2, "Should not allow pinning beyond limit")
        
        // Wait for any rollback
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Then: Second item should not be pinned
        let finalHistory = adapter.history
        if let item2 = finalHistory.first(where: { $0.content == "Item 2" }) {
            XCTAssertFalse(item2.isPinned, "Item 2 should not be pinned after failed attempt")
        }

        // Service should also show only one pinned item
        let serviceHistory = await service.getHistory()
        let pinnedCount = serviceHistory.filter { $0.content.hasPrefix("Item") && $0.isPinned }.count
        XCTAssertEqual(pinnedCount, 1, "Service should have exactly 1 pinned item")
    }
    
    func testConcurrentTogglePin() async throws {
        // Given: Add multiple items
        for i in 1...10 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }
        await service.flushPendingSaves()
        await waitForHistory(count: 10)

        let history = adapter.history
        XCTAssertEqual(history.count, 10)
        
        // When: Toggle multiple items concurrently
        let adapter = self.adapter!
        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<5 {
                group.addTask {
                    return await MainActor.run {
                        adapter.togglePin(for: history[i])
                    }
                }
            }
        }
        
        // Wait for all operations to complete
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Then: State should be consistent
        let serviceHistory = await service.getHistory()
        let adapterHistory = adapter.history

        // Count pinned items in both
        let servicePinnedCount = serviceHistory.filter { $0.content.hasPrefix("Item") && $0.isPinned }.count
        let adapterPinnedCount = adapterHistory.filter { $0.content.hasPrefix("Item") && $0.isPinned }.count
        
        XCTAssertEqual(servicePinnedCount, adapterPinnedCount,
                      "Pinned count should be consistent between service and adapter")
        
        // Verify each item's state is consistent
        for item in adapterHistory {
            if let serviceItem = serviceHistory.first(where: { $0.id == item.id }) {
                XCTAssertEqual(item.isPinned, serviceItem.isPinned,
                              "Pin state for item \(item.content) should be consistent")
            }
        }
    }
}
