//
//  ClearAllHistoryBehaviorTests.swift
//  KippleTests
//
//  Tests for Clear All History button behavior
//

import XCTest
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class ClearAllHistoryBehaviorTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!

    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        await service.resetForTesting()
        adapter = ModernClipboardServiceAdapter.shared

        await service.resetForTesting()
        await adapter.clearHistory(keepPinned: false)
    }

    override func tearDown() async throws {
        await service.resetForTesting()
        await adapter.clearHistory(keepPinned: false)

        service = nil
        adapter = nil

        try await super.tearDown()
    }

    // MARK: - Clear All History Tests

    func testClearAllHistoryShouldRemoveEverything() async throws {
        // Given: History with both pinned and unpinned items
        await service.copyToClipboard("Unpinned Item 1", fromEditor: false)
        await service.copyToClipboard("Unpinned Item 2", fromEditor: false)
        await service.copyToClipboard("Pinned Item 1", fromEditor: false)
        await service.copyToClipboard("Pinned Item 2", fromEditor: false)
        await service.flushPendingSaves()

        // Pin some items
        var history = await service.getHistory()
        _ = await service.togglePin(for: history[0]) // Pin "Pinned Item 2"
        _ = await service.togglePin(for: history[1]) // Pin "Pinned Item 1"
        await service.flushPendingSaves()

        history = await service.getHistory()
        let pinnedCount = history.filter { $0.isPinned }.count
        XCTAssertEqual(pinnedCount, 2, "Should have 2 pinned items")
        XCTAssertEqual(history.count, 4, "Should have 4 total items")

        // When: User clicks "Clear All History" (expecting EVERYTHING to be cleared)
        await service.clearHistory(keepPinned: false)
        await service.flushPendingSaves()

        // Then: ALL items should be removed, including pinned ones
        history = await service.getHistory()
        XCTAssertEqual(history.count, 0, "All history should be cleared, including pinned items")
    }

    func testClearAllHistoryVsClearKeepingPinned() async throws {
        // Given: History with pinned items
        await service.copyToClipboard("Regular 1", fromEditor: false)
        await service.copyToClipboard("Pinned 1", fromEditor: false)
        await service.copyToClipboard("Regular 2", fromEditor: false)
        await service.copyToClipboard("Pinned 2", fromEditor: false)

        var history = await service.getHistory()
        _ = await service.togglePin(for: history[0]) // Pin "Pinned 2"
        _ = await service.togglePin(for: history[2]) // Pin "Pinned 1"
        await service.flushPendingSaves()

        // Test 1: Clear keeping pinned
        await service.clearHistory(keepPinned: true)
        history = await service.getHistory()
        XCTAssertEqual(history.count, 2, "Should keep pinned items")
        XCTAssertTrue(history.allSatisfy { $0.isPinned }, "All remaining should be pinned")

        // Reset
        await service.copyToClipboard("Regular 3", fromEditor: false)
        await service.copyToClipboard("Regular 4", fromEditor: false)

        // Test 2: Clear ALL (what the UI says it does)
        await service.clearHistory(keepPinned: false)
        history = await service.getHistory()
        XCTAssertEqual(history.count, 0, "Clear ALL should remove everything")
    }

    func testClearAllHistoryWithManyPinnedItems() async throws {
        // Given: Many pinned items
        for i in 1...10 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }

        var history = await service.getHistory()
        // Pin all items
        for item in history {
            _ = await service.togglePin(for: item)
        }
        await service.flushPendingSaves()

        history = await service.getHistory()
        XCTAssertEqual(history.filter { $0.isPinned }.count, 10, "All items should be pinned")

        // When: Clear All History
        await service.clearHistory(keepPinned: false)

        // Then: Everything should be gone
        history = await service.getHistory()
        XCTAssertEqual(history.count, 0, "Even 10 pinned items should be cleared")
    }

    func testClearAllHistoryPersistence() async throws {
        // Given: Items in history with some pinned
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.copyToClipboard("Item 3", fromEditor: false)

        var history = await service.getHistory()
        _ = await service.togglePin(for: history[0])
        await service.flushPendingSaves()

        // When: Clear all history
        await service.clearHistory(keepPinned: false)
        await service.flushPendingSaves()

        // Then: Repository should also be empty
        let repository = try SwiftDataRepository.make(inMemory: true)
        let savedHistory = await service.getHistory()
        try await repository.save(savedHistory)

        let loaded = try await repository.load(limit: 100)
        XCTAssertEqual(loaded.count, 0, "Repository should be empty after clear all")
    }

    // MARK: - Adapter Integration

    func testClearAllHistoryThroughAdapter() async throws {
        // Given: Items through adapter
        adapter.copyToClipboard("Adapter Item 1", fromEditor: false)
        adapter.copyToClipboard("Adapter Item 2", fromEditor: false)

        // Wait for update
        try await Task.sleep(nanoseconds: 500_000_000)

        _ = adapter.togglePin(for: adapter.history[0])

        // When: Clear all through adapter's clearHistory method
        await adapter.clearHistory(keepPinned: false)

        // Wait for update
        try await Task.sleep(nanoseconds: 500_000_000)

        // Then: Should be empty
        XCTAssertEqual(adapter.history.count, 0, "Adapter should show empty history")
    }

    // MARK: - UI Expectation Tests

    func testUILabelMatchesBehavior() async throws {
        // This test documents the expected behavior based on UI text
        // "Clear All History" with description "Permanently remove all clipboard history items"

        // Given: User has sensitive data in clipboard history
        await service.copyToClipboard("Password123", fromEditor: false)
        await service.copyToClipboard("API_KEY_SECRET", fromEditor: false)
        await service.copyToClipboard("Personal Info", fromEditor: false)

        // Some items might be pinned
        var history = await service.getHistory()
        _ = await service.togglePin(for: history[0]) // Pin sensitive data

        // When: User clicks "Clear All History" expecting to remove ALL items permanently
        // The UI says "Permanently remove all clipboard history items"
        // User expects: Everything gone, no exceptions
        await service.clearHistory(keepPinned: false)

        // Then: Everything should be removed as the UI promises
        history = await service.getHistory()
        XCTAssertEqual(
            history.count, 0,
            "UI promises to 'Permanently remove all clipboard history items' - this must include pinned items"
        )
    }
}
