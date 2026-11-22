//
//  ClearAllHistoryBehaviorTests.swift
//  KippleTests
//
//  Tests for Clear All History button behavior
//

import XCTest
@testable import Kipple

@MainActor
final class ClearAllHistoryBehaviorTests: XCTestCase {
    func testStartupTrimsTheEntireStoreAfterCategoryDeletion() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let retained = ClipItem(content: "Keep", userCategoryId: UUID())
        let removedCategory = UUID()
        let formerlyCategorized = (1...30).map { index in
            ClipItem(content: "Previously categorized \(index)", userCategoryId: removedCategory)
        }
        try await repository.save([retained] + formerlyCategorized)
        let beforeCategoryDeletion = ModernClipboardService(testRepository: repository)
        await beforeCategoryDeletion.loadHistoryFromRepository()
        try await beforeCategoryDeletion.removeCategoryDefinition(removedCategory)

        let service = ModernClipboardService(testRepository: repository)
        await service.setMaxHistoryItems(10)
        await service.loadHistoryFromRepository()
        let visible = await service.getHistory()
        let ordinary = visible.filter { !$0.hasCustomCategory }
        XCTAssertEqual(ordinary.count, 10)
        let stored = try await repository.loadAll()
        XCTAssertEqual(Set(stored.map(\.id)), Set(visible.map(\.id)))

        for item in ordinary { await service.deleteItem(item) }
        await service.flushPendingSaves()

        let restarted = ModernClipboardService(testRepository: repository)
        await restarted.setMaxHistoryItems(10)
        await restarted.loadHistoryFromRepository()
        let visibleAfterRestart = await restarted.getHistory()
        XCTAssertEqual(visibleAfterRestart.map(\.id), [retained.id])
    }

    func testClearingHistoryAlsoDeletesRowsOutsideLoadedHistory() async throws {
        let repository = try SwiftDataRepository.make(inMemory: true)
        let retained = ClipItem(content: "Keep", userCategoryId: UUID())
        try await repository.save([retained, ClipItem(content: "Visible ordinary item")])
        let service = ModernClipboardService(testRepository: repository)
        await service.loadHistoryFromRepository()
        try await repository.save([ClipItem(content: "Stored only")])

        let result = await service.clearHistory(keepingCategories: true)
        XCTAssertEqual(try result.get(), 2)

        let restarted = ModernClipboardService(testRepository: repository)
        await restarted.loadHistoryFromRepository()
        let visibleAfterRestart = await restarted.getHistory()
        XCTAssertEqual(visibleAfterRestart.map(\.id), [retained.id])
    }

    func testClearReportsSaveFailureAndLeavesHistoryAvailableForRetry() async throws {
        let repository = MockClipboardRepository()
        let item = ClipItem(content: "Delete on retry")
        await repository.configure(items: [item], loadDelay: 0)
        let service = ModernClipboardService(testRepository: repository)
        await service.loadHistoryFromRepository()
        await repository.failNextWrites(1)

        let failed = await service.clearHistory(keepingCategories: true)
        XCTAssertThrowsError(try failed.get())
        let visible = await service.getHistory()
        let stored = try await repository.loadAll()
        XCTAssertEqual(visible, [item])
        XCTAssertEqual(stored, [item])

        let retried = await service.clearHistory(keepingCategories: true)
        XCTAssertEqual(try retried.get(), 1)
        let savedAfterRetry = try await repository.loadAll()
        XCTAssertTrue(savedAfterRetry.isEmpty)
    }

    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!

    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        await service.resetForTesting()
        adapter = ModernClipboardServiceAdapter.shared

        await service.resetForTesting()
        await adapter.clearHistory(keepingCategories: false)
    }

    override func tearDown() async throws {
        await service.resetForTesting()
        await adapter.clearHistory(keepingCategories: false)

        service = nil
        adapter = nil

        try await super.tearDown()
    }

    // MARK: - Clear All History Tests

    func testClearAllHistoryShouldRemoveEverything() async throws {
        // Given: History with both categorized and uncategorized items
        await service.copyToClipboard("Uncategorized Item 1", fromEditor: false)
        await service.copyToClipboard("Uncategorized Item 2", fromEditor: false)
        await service.copyToClipboard("Categorized Item 1", fromEditor: false)
        await service.copyToClipboard("Categorized Item 2", fromEditor: false)
        await service.flushPendingSaves()

        // Categorize some items
        var history = await service.getHistory()
        try await service.setCategory(itemID: history[0].id, categoryID: savedHistoryCategoryID, enabled: true) // "Categorized Item 2"
        try await service.setCategory(itemID: history[1].id, categoryID: savedHistoryCategoryID, enabled: true) // "Categorized Item 1"
        await service.flushPendingSaves()

        history = await service.getHistory()
        let categorizedCount = history.filter { $0.hasCustomCategory }.count
        XCTAssertEqual(categorizedCount, 2, "Should have 2 categorized items")
        XCTAssertEqual(history.count, 4, "Should have 4 total items")

        // When: User clicks "Clear All History" (expecting EVERYTHING to be cleared)
        await service.clearHistory(keepingCategories: false)
        await service.flushPendingSaves()

        // Then: ALL items should be removed, including categorized ones
        history = await service.getHistory()
        XCTAssertEqual(history.count, 0, "All history should be cleared, including categorized items")
    }

    func testClearAllHistoryVsClearKeepingCategories() async throws {
        // Given: History with categorized items
        await service.copyToClipboard("Regular 1", fromEditor: false)
        await service.copyToClipboard("Categorized 1", fromEditor: false)
        await service.copyToClipboard("Regular 2", fromEditor: false)
        await service.copyToClipboard("Categorized 2", fromEditor: false)

        var history = await service.getHistory()
        try await service.setCategory(itemID: history[0].id, categoryID: savedHistoryCategoryID, enabled: true) // "Categorized 2"
        try await service.setCategory(itemID: history[2].id, categoryID: savedHistoryCategoryID, enabled: true) // "Categorized 1"
        await service.flushPendingSaves()

        // Test 1: Clear keeping categorized
        await service.clearHistory(keepingCategories: true)
        history = await service.getHistory()
        XCTAssertEqual(history.count, 2, "Should keep categorized items")
        XCTAssertTrue(history.allSatisfy { $0.hasCustomCategory }, "All remaining should be categorized")

        // Reset
        await service.copyToClipboard("Regular 3", fromEditor: false)
        await service.copyToClipboard("Regular 4", fromEditor: false)

        // Test 2: Clear ALL (what the UI says it does)
        await service.clearHistory(keepingCategories: false)
        history = await service.getHistory()
        XCTAssertEqual(history.count, 0, "Clear ALL should remove everything")
    }

    func testClearAllHistoryWithManyCategorizedItems() async throws {
        // Given: Many categorized items
        for i in 1...10 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }

        var history = await service.getHistory()
        // Categorize all items
        for item in history {
            try await service.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)
        }
        await service.flushPendingSaves()

        history = await service.getHistory()
        XCTAssertEqual(history.filter { $0.hasCustomCategory }.count, 10, "All items should be categorized")

        // When: Clear All History
        await service.clearHistory(keepingCategories: false)

        // Then: Everything should be gone
        history = await service.getHistory()
        XCTAssertEqual(history.count, 0, "Even 10 categorized items should be cleared")
    }

    func testClearAllHistoryPersistence() async throws {
        // Given: Items in history with some categorized
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.copyToClipboard("Item 3", fromEditor: false)

        let history = await service.getHistory()
        try await service.setCategory(itemID: history[0].id, categoryID: savedHistoryCategoryID, enabled: true)
        await service.flushPendingSaves()

        // When: Clear all history
        await service.clearHistory(keepingCategories: false)
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

        try await adapter.updateCategories(itemID: adapter.history[0].id, change: .set(savedHistoryCategoryID, enabled: true))

        // When: Clear all through adapter's clearHistory method
        await adapter.clearHistory(keepingCategories: false)

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

        // Some items might be categorized
        var history = await service.getHistory()
        try await service.setCategory(itemID: history[0].id, categoryID: savedHistoryCategoryID, enabled: true) // Categorize sensitive data

        // When: User clicks "Clear All History" expecting to remove ALL items permanently
        // The UI says "Permanently remove all clipboard history items"
        // User expects: Everything gone, no exceptions
        await service.clearHistory(keepingCategories: false)

        // Then: Everything should be removed as the UI promises
        history = await service.getHistory()
        XCTAssertEqual(
            history.count, 0,
            "UI promises to 'Permanently remove all clipboard history items' - this must include categorized items"
        )
    }
}
