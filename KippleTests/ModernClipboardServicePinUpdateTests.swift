//
//  ModernClipboardServicePinUpdateTests.swift
//  Kipple
//
//  Created by Codex on 2025/09/23.
//

import XCTest
@testable import Kipple

final class ModernClipboardServicePinUpdateTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        service = ModernClipboardService.shared
        await service.resetForTesting()
        adapter = ModernClipboardServiceAdapter.shared

        // Clear history before each test
        await service.clearAllHistory()
        await service.flushPendingSaves()
        await adapter.clearHistory(keepPinned: false)
    }

    @MainActor
    override func tearDown() async throws {
        await service.clearAllHistory()
        await service.flushPendingSaves()
        try await super.tearDown()
    }

    @MainActor
    func testPinToggleUpdatesUI() async throws {
        // Given: Add an item
        await service.copyToClipboard("Test Item", fromEditor: false)
        try? await Task.sleep(for: .seconds(0.2))

        // Get initial history
        let initialHistory = adapter.history
        guard let item = initialHistory.first else {
            XCTFail("No item in history")
            return
        }

        XCTAssertFalse(item.isPinned)

        // When: Toggle pin
        let pinResult = adapter.togglePin(for: item)
        XCTAssertTrue(pinResult)

        // Give time for async refresh
        try? await Task.sleep(for: .seconds(0.6))

        // Then: UI should reflect change
        let updatedHistory = adapter.history
        XCTAssertTrue(updatedHistory.first?.isPinned == true)
    }

    @MainActor
    func testClearAllHistoryPreservesPinned() async throws {
        // Given: Add items with some pinned
        await service.copyToClipboard("Regular 1", fromEditor: false)
        await service.copyToClipboard("Pinned 1", fromEditor: false)
        await service.copyToClipboard("Regular 2", fromEditor: false)
        await service.copyToClipboard("Pinned 2", fromEditor: false)

        // Pin some items
        let history = await service.getHistory()
        if let pinned1 = history.first(where: { $0.content == "Pinned 1" }) {
            _ = await service.togglePin(for: pinned1)
        }
        if let pinned2 = history.first(where: { $0.content == "Pinned 2" }) {
            _ = await service.togglePin(for: pinned2)
        }

        // When: Clear all history
        await service.clearAllHistory()

        // Then: Only pinned items should remain
        let clearedHistory = await service.getHistory()
        XCTAssertEqual(clearedHistory.count, 2)
        XCTAssertTrue(clearedHistory.allSatisfy { $0.isPinned })
        XCTAssertTrue(clearedHistory.contains { $0.content == "Pinned 1" })
        XCTAssertTrue(clearedHistory.contains { $0.content == "Pinned 2" })
    }

    @MainActor
    func testClearHistoryKeepPinnedOption() async throws {
        // Given: Add items with some pinned
        await service.copyToClipboard("Regular Item", fromEditor: false)
        await service.copyToClipboard("Pinned Item", fromEditor: false)

        let history = await service.getHistory()
        if let pinnedItem = history.first(where: { $0.content == "Pinned Item" }) {
            _ = await service.togglePin(for: pinnedItem)
        }

        // When: Clear history keeping pinned
        await service.clearHistory(keepPinned: true)

        // Then: Only pinned item remains
        let remainingHistory = await service.getHistory()
        XCTAssertEqual(remainingHistory.count, 1)
        XCTAssertEqual(remainingHistory.first?.content, "Pinned Item")
        XCTAssertTrue(remainingHistory.first?.isPinned == true)

        // When: Clear history without keeping pinned
        await service.clearHistory(keepPinned: false)

        // Then: All items removed
        let emptyHistory = await service.getHistory()
        XCTAssertEqual(emptyHistory.count, 0)
    }

    @MainActor
    func testAdapterRefreshAlwaysUpdatesHistory() async throws {
        // Given: Add item
        await service.copyToClipboard("Test", fromEditor: false)

        let initialCount = adapter.history.count

        // When: Add another item
        await service.copyToClipboard("Test 2", fromEditor: false)

        // Wait for periodic refresh
        try? await Task.sleep(for: .seconds(0.6))

        // Then: Adapter should have updated history
        XCTAssertGreaterThan(adapter.history.count, initialCount)
    }

    @MainActor
    func testMetadataChangesReflectInUI() async throws {
        // Given: Create item with metadata
        await service.copyToClipboard("Editor Item", fromEditor: true)

        // Wait for refresh
        try? await Task.sleep(for: .seconds(0.6))

        // Then: Metadata should be present
        let history = adapter.history
        guard let item = history.first else {
            XCTFail("No item in history")
            return
        }

        XCTAssertEqual(item.sourceApp, "Kipple")
        XCTAssertEqual(item.windowTitle, "Quick Editor")
        XCTAssertTrue(item.isFromEditor ?? false)
    }
}
