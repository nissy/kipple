//
//  ModernClipboardServiceStartupTests.swift
//  KippleTests
//
//  Tests for ModernClipboardService startup behavior and settings application
//

import XCTest
@testable import Kipple

@MainActor
final class ModernClipboardServiceStartupTests: XCTestCase {
    private var repository: ClipboardRepositoryProtocol!

    override func setUp() async throws {
        try await super.setUp()

        // Use in-memory repository for testing
        repository = try SwiftDataRepository.make(inMemory: true)
        await ModernClipboardService.shared.useTestingRepository(repository)
        await ModernClipboardService.shared.resetForTesting()

        // Reset settings to defaults
        AppSettings.shared.maxHistoryItems = 100
        await ModernClipboardService.shared.setMaxHistoryItems(100)
    }

    override func tearDown() async throws {
        RepositoryProvider.useTestingRepository(nil)
        repository = nil
        await ModernClipboardService.shared.resetForTesting()

        // Reset settings
        AppSettings.shared.maxHistoryItems = 300

        try await super.tearDown()
    }

    // MARK: - Startup Limit Tests

    func testMaxHistoryItemsRespectedOnStartup() async throws {
        // Given: Repository has more items than the limit
        let testItems = (1...150).map { index in
            ClipItem(
                content: "Item \(index)"
            )
        }
        try await repository.save(testItems)

        // When: Create a new service instance (simulating app startup)
        let service = ModernClipboardService.shared
        await service.loadHistoryFromRepository()

        // Then: History should be trimmed to maxHistoryItems
        let history = await service.getHistory()
        XCTAssertLessThanOrEqual(history.count, AppSettings.shared.maxHistoryItems,
                                  "History should be trimmed to maxHistoryItems on startup")

        // Verify the newest items are kept
        if !history.isEmpty {
            XCTAssertEqual(history.first?.content, "Item 150",
                          "Newest items should be preserved")
        }
    }

    func testStartupReloadLoadsPersistedHistory() async throws {
#if DEBUG
        // Given: Persisted items exist before the service loads them
        let persistedItems = (1...5).map { index in
            ClipItem(content: "Persisted Item \(index)")
        }
        try await repository.save(persistedItems)

        // When: Simulate startup reload sequence
        await ModernClipboardService.shared.reloadHistoryForTesting()

        // Then: History should contain all persisted items in newest-first order
        let history = await ModernClipboardService.shared.getHistory()
        XCTAssertEqual(history.count, persistedItems.count,
                       "Startup reload should hydrate all persisted items")
        XCTAssertEqual(history.first?.content, persistedItems.last?.content,
                       "Newest persisted item should appear at the top")
#else
        throw XCTSkip("Requires DEBUG configuration")
#endif
    }

    func testCategorizedItemsPreservedDuringStartupTrim() async throws {
        // Given: Repository has mix of categorized and uncategorized items
        var testItems: [ClipItem] = []

        // Add 10 categorized items
        for i in 1...10 {
            var item = ClipItem(
                content: "Categorized \(i)"
            )
            item.setCategory(savedHistoryCategoryID, enabled: true)
            testItems.append(item)
        }

        // Add 140 uncategorized items (total 150, over limit of 100)
        for i in 1...140 {
            let item = ClipItem(
                content: "Uncategorized \(i)"
            )
            testItems.append(item)
        }

        try await repository.save(testItems)

        // Set a limit that forces trimming
        AppSettings.shared.maxHistoryItems = 50

        // When: Create service (startup)
        let service = ModernClipboardService.shared
        await service.setMaxHistoryItems(50)
        await service.loadHistoryFromRepository()

        // Then: All categorized items should be preserved
        let history = await service.getHistory()
        let categorizedInHistory = history.filter { $0.hasCustomCategory }

        XCTAssertEqual(categorizedInHistory.count, 10,
                      "All categorized items should be preserved during startup trim")
        XCTAssertEqual(history.count - categorizedInHistory.count, 50)
    }

    // MARK: - Settings Update Tests

    func testSettingsUpdateTrimsHistory() async throws {
        // Given: Service with 100 items
        let service = ModernClipboardService.shared
        await service.loadHistoryFromRepository()
        let testItems = (1...100).map { index in
            ClipItem(content: "Item \(index)")
        }

        // Directly set history (bypassing normal add flow for test)
        await service.clearHistory(keepingCategories: true)
        for item in testItems.reversed() {
            await service.copyToClipboard(item.content, fromEditor: false)
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        var history = await service.getHistory()
        XCTAssertGreaterThan(history.count, 50, "Should have items before trim")

        // When: Update max history items to lower value
        await service.setMaxHistoryItems(50)

        // Then: History should be trimmed
        history = await service.getHistory()
        XCTAssertLessThanOrEqual(history.count, 50,
                                 "History should be trimmed after settings update")
    }

    func testDataSettingsViewUpdatesService() async throws {
        // Given: Service and settings view
        let service = ModernClipboardServiceAdapter.shared

        // Add test items
        for i in 1...80 {
            service.copyToClipboard("Test \(i)", fromEditor: false)
        }

        try await Task.sleep(nanoseconds: 200_000_000)

        // When: Settings changed via DataSettingsView simulation
        AppSettings.shared.maxHistoryItems = 40
        await service.setMaxHistoryItems(40)

        // Then: Service should reflect new limit
        try await Task.sleep(nanoseconds: 200_000_000)
        let history = service.history
        XCTAssertLessThanOrEqual(history.count, 40,
                                 "Service should apply new limit from settings")
    }

    // MARK: - Edge Cases

    func testZeroItemsOnStartup() async throws {
        // Given: Empty repository

        // When: Service starts
        let service = ModernClipboardService.shared
        await service.loadHistoryFromRepository()
        try await Task.sleep(nanoseconds: 200_000_000)

        // Then: Should handle gracefully
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 0, "Should handle empty history on startup")
    }

    func testVeryLowLimitOnStartup() async throws {
        // Given: Very low limit
        AppSettings.shared.maxHistoryItems = 10

        // Add 50 items to repository
        let testItems = (1...50).map { index in
            ClipItem(content: "Item \(index)")
        }
        try await repository.save(testItems)

        // When: Service starts
        let service = ModernClipboardService.shared
        await service.resetForTesting()
        try await Task.sleep(nanoseconds: 500_000_000)

        // Then: Should trim to limit
        let history = await service.getHistory()
        XCTAssertLessThanOrEqual(history.count, 10,
                                 "Should handle very low limits on startup")
    }

    func testCategorizedItemsAreRetainedOverTheLimit() async throws {
        // Given: More categorized items than the limit
        var testItems: [ClipItem] = []
        for i in 1...30 {
            var item = ClipItem(content: "Categorized \(i)")
            item.setCategory(savedHistoryCategoryID, enabled: true)
            testItems.append(item)
        }
        try await repository.save(testItems)

        // Set limit lower than categorized count
        AppSettings.shared.maxHistoryItems = 20

        // When: Service starts
        let service = ModernClipboardService.shared
        await service.setMaxHistoryItems(20)
        await service.loadHistoryFromRepository()

        let history = await service.getHistory()
        XCTAssertEqual(history.count, 30)
        XCTAssertTrue(history.allSatisfy(\.hasCustomCategory))
    }
}
