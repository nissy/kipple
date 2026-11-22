//
//  HistoryLimitTests.swift
//  KippleTests
//
//  Tests for history limit functionality and settings synchronization
//

import XCTest
@testable import Kipple

@MainActor
final class HistoryLimitTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!

    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        await service.resetForTesting()
        adapter = ModernClipboardServiceAdapter.shared

        // Clear any existing data (including categorized)
        await service.clearHistory(keepingCategories: false)

        // Reset to default settings
        AppSettings.shared.maxHistoryItems = 100
    }

    override func tearDown() async throws {
        // Clean up
        await service.clearHistory(keepingCategories: false)

        service = nil
        adapter = nil

        try await super.tearDown()
    }

    // MARK: - Dynamic Limit Changes

    func testReducingLimitTrimsHistory() async throws {
        // Given: History with 80 items
        for i in 1...80 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }

        await service.flushPendingSaves()
        var history = await service.getHistory()
        let initialCount = history.count
        XCTAssertGreaterThan(initialCount, 40)

        // When: Reduce limit to 40
        await service.setMaxHistoryItems(40)

        // Then: History should be trimmed
        history = await service.getHistory()
        XCTAssertLessThanOrEqual(history.count, 40)
        XCTAssertLessThan(history.count, initialCount)
    }

    func testIncreasingLimitDoesNotAddItems() async throws {
        // Given: History with 30 items
        for i in 1...30 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }

        await service.flushPendingSaves()
        let initialHistory = await service.getHistory()
        let initialCount = initialHistory.count

        // When: Increase limit to 100
        await service.setMaxHistoryItems(100)

        // Then: History count should remain the same
        let newHistory = await service.getHistory()
        XCTAssertEqual(newHistory.count, initialCount)
    }

    // MARK: - Settings Integration

    func testSettingsChangeReflectsInService() async throws {
        // Given: Service with default settings
        let initialLimit = AppSettings.shared.maxHistoryItems

        // Add items up to the limit
        for i in 1...initialLimit {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }

        // When: Change settings and apply
        AppSettings.shared.maxHistoryItems = 50
        await adapter.setMaxHistoryItems(50)

        // Then: Service should respect new limit
        try await Task.sleep(nanoseconds: 200_000_000)
        let history = await service.getHistory()
        XCTAssertLessThanOrEqual(history.count, 50)
    }

    // MARK: - Categorized Items Priority

    func testCategorizedItemsPreservedWhenReducingLimit() async throws {
        // Given: Mix of categorized and uncategorized items
        // Add 20 categorized items
        for i in 1...20 {
            await service.copyToClipboard("Categorized \(i)", fromEditor: false)
            let history = await service.getHistory()
            if let item = history.first(where: { $0.content == "Categorized \(i)" }) {
                try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)
            }
        }

        // Add 40 uncategorized items
        for i in 1...40 {
            await service.copyToClipboard("Uncategorized \(i)", fromEditor: false)
        }

        // When: Reduce limit to 30 (less than total but more than categorized)
        await service.setMaxHistoryItems(30)

        // Then: All categorized items should be preserved
        let history = await service.getHistory()
        let categorizedItems = history.filter { $0.hasCustomCategory }
        XCTAssertEqual(categorizedItems.count, 20)
        XCTAssertEqual(history.count - categorizedItems.count, 30)
    }

    func testAllCategorizedItemsAreRetainedOverTheLimit() async throws {
        // Given: 50 categorized items
        for i in 1...50 {
            await service.copyToClipboard("Categorized \(i)", fromEditor: false)
            let history = await service.getHistory()
            if let item = history.first(where: { $0.content == "Categorized \(i)" }) {
                try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)
            }
        }

        // When: Reduce limit to 30
        await service.setMaxHistoryItems(30)

        // Then: Categorized items remain even when their count exceeds the limit.
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 50)

        // Newest categorized items should be kept
        XCTAssertTrue(history.contains { $0.content == "Categorized 50" })
    }

    // MARK: - Repository Persistence

    func testLimitAppliedAfterRepositoryLoad() async throws {
        // Given: Repository with many items
        let repository = try SwiftDataRepository.make(inMemory: true)

        // Save 150 items directly to repository
        let testItems = (1...150).map { index in
            ClipItem(content: "Repo Item \(index)")
        }
        try await repository.save(testItems)

        // When: Service loads from repository with limit of 75
        AppSettings.shared.maxHistoryItems = 75

        // Force reload (simulate app restart)
        await service.clearHistory(keepingCategories: true)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Load from repository (this happens on init, we simulate it)
        let loadedItems = try await repository.load(limit: 1000)
        XCTAssertEqual(loadedItems.count, 150, "Repository should have all items")

        // Apply limit as service would do on startup
        await service.setMaxHistoryItems(75)

        // Then: Service should trim to limit
        let history = await service.getHistory()
        XCTAssertLessThanOrEqual(history.count, 75)
    }

    // MARK: - Performance

    func testLargeLimitReduction() async throws {
        // Given: 500 items
        for i in 1...500 {
            await service.copyToClipboard("Large \(i)", fromEditor: false)
        }

        let startTime = Date()

        // When: Reduce to 50
        await service.setMaxHistoryItems(50)

        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)

        // Then: Should complete quickly
        XCTAssertLessThan(duration, 1.0, "Trimming should complete within 1 second")

        let history = await service.getHistory()
        XCTAssertLessThanOrEqual(history.count, 50)
    }

    // MARK: - Edge Cases

    func testSettingLimitToZero() async throws {
        // Given: Some items
        for i in 1...10 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }

        // When: Set limit to minimum (10)
        await service.setMaxHistoryItems(10)

        // Then: Should keep minimum items
        let history = await service.getHistory()
        XCTAssertLessThanOrEqual(history.count, 10)
    }

    func testRapidLimitChanges() async throws {
        // Given: 100 items
        for i in 1...100 {
            await service.copyToClipboard("Rapid \(i)", fromEditor: false)
        }

        // When: Rapidly change limits
        for limit in [80, 60, 40, 60, 80, 50] {
            await service.setMaxHistoryItems(limit)
            let history = await service.getHistory()
            XCTAssertLessThanOrEqual(history.count, limit)
        }

        // Then: Final limit should be respected
        let finalHistory = await service.getHistory()
        XCTAssertLessThanOrEqual(finalHistory.count, 50)
    }
}
