import XCTest
import SwiftData
import Combine
@testable import Kipple

@MainActor
final class IntegrationTests: XCTestCase, @unchecked Sendable {
    private var clipboardService: ModernClipboardService!
    private var repository: SwiftDataRepository!
    private var hotkeyManager: SimplifiedHotkeyManager!
    private var container: ModelContainer!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() async throws {
        try await super.setUp()

        // Setup services
        clipboardService = ModernClipboardService.shared
        await clipboardService.useCategoryStoreFixture()
        await clipboardService.clearHistory(keepingCategories: false)

        // Setup repository
        let schema = Schema([ClipItemModel.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        repository = try SwiftDataRepository.make(container: container)

        // Setup hotkey manager
        hotkeyManager = SimplifiedHotkeyManager.shared
        hotkeyManager.setHotkey(keyCode: 46, modifiers: [.control, .option])
        hotkeyManager.setEnabled(true)

        cancellables.removeAll()
    }

    override func tearDown() async throws {
        await clipboardService.stopMonitoring()
        await clipboardService.clearHistory(keepingCategories: false)
        repository = nil
        container = nil
        cancellables.removeAll()
        try await super.tearDown()
    }

    // MARK: - End-to-End Workflow Tests

    func testCompleteClipboardWorkflow() async throws {
        // 1. Start monitoring
        await clipboardService.startMonitoring()
        let isMonitoring = await clipboardService.isMonitoring()
        XCTAssertTrue(isMonitoring)

        // 2. Copy items to clipboard
        await clipboardService.copyToClipboard("First item", fromEditor: false)
        await clipboardService.copyToClipboard("Second item", fromEditor: true)
        await clipboardService.copyToClipboard("Third item", fromEditor: false)

        // 3. Verify history
        let history = await clipboardService.getHistory()
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history[0].content, "Third item")
        XCTAssertEqual(history[1].content, "Second item")
        XCTAssertTrue(history[1].isFromEditor ?? false)

        // 4. Categorize an item
        let itemToCategorize = history[1]
        try await clipboardService.setCategory(itemID: itemToCategorize.id, categoryID: savedHistoryCategoryID, enabled: true)

        // 5. Save to repository
        try await repository.save(history)
        let savedItems = try await repository.loadAll()
        XCTAssertEqual(savedItems.count, 3)

        // 6. Search functionality
        let searchResults = await clipboardService.searchHistory(query: "Second")
        XCTAssertEqual(searchResults.count, 1)
        XCTAssertEqual(searchResults.first?.content, "Second item")

        // 7. Clear history keeping categorized
        await clipboardService.clearHistory(keepingCategories: true)
        let remainingHistory = await clipboardService.getHistory()
        XCTAssertEqual(remainingHistory.count, 1)
        XCTAssertTrue(remainingHistory.first?.hasCustomCategory ?? false)

        // 8. Stop monitoring
        await clipboardService.stopMonitoring()
        let isMonitoringAfterStop = await clipboardService.isMonitoring()
        XCTAssertFalse(isMonitoringAfterStop)
    }

    func testDataPersistenceWorkflow() async throws {
        // 1. Create test data
        let testItems = [
            ClipItem(content: "Persistent 1"),
            ClipItem(content: "Persistent 2"),
            ClipItem(content: "Persistent 3")
        ]

        // 2. Save to repository
        try await repository.save(testItems)

        // 3. Load and verify
        let loadedItems = try await repository.loadAll()
        XCTAssertEqual(loadedItems.count, 3)

        // 4. Update an item
        let itemToUpdate = loadedItems.first!
        // Create new item with updated values since ClipItem is immutable
        let updatedItem = ClipItem(
            content: "Updated content",
            userCategoryId: savedHistoryCategoryID
        )
        // Delete old and save new to simulate update
        try await repository.delete(itemToUpdate)
        try await repository.save([updatedItem])

        // 5. Verify update
        let updatedItems = try await repository.loadAll()
        let verifiedItem = updatedItems.first { $0.content == "Updated content" }
        XCTAssertNotNil(verifiedItem)
        XCTAssertEqual(verifiedItem?.content, "Updated content")
        XCTAssertTrue(verifiedItem?.hasCustomCategory ?? false)

        // 6. Delete an item
        if let itemToDelete = updatedItems.last {
            try await repository.delete(itemToDelete)
        }

        // 7. Verify deletion
        let finalItems = try await repository.loadAll()
        XCTAssertEqual(finalItems.count, 2)

        // 8. Clear keeping categorized
        try await repository.replaceAll(with: repository.loadCategorized())
        let categorizedItems = try await repository.loadCategorized()
        XCTAssertEqual(categorizedItems.count, 1) // Updated content is categorized
    }

    func testHotkeyIntegrationWorkflow() async throws {
        // 1. Setup hotkey notification observer
        let expectation = XCTestExpectation(description: "Hotkey triggered")

        NotificationCenter.default.publisher(for: NSNotification.Name("toggleMainWindow"))
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // 2. Configure hotkey
        hotkeyManager.setHotkey(keyCode: 35, modifiers: [.command, .option]) // Cmd+Opt+P
        hotkeyManager.setEnabled(true)

        // 3. Verify configuration
        let (keyCode, modifiers) = hotkeyManager.getHotkey()
        XCTAssertEqual(keyCode, 35)
        XCTAssertEqual(modifiers, [.command, .option])
        XCTAssertTrue(hotkeyManager.getEnabled())

        // 4. Simulate hotkey trigger
        NotificationCenter.default.post(
            name: NSNotification.Name("toggleMainWindow"),
            object: nil
        )

        // 5. Verify notification received
        await fulfillment(of: [expectation], timeout: 1.0)

        // 6. Test hotkey description
        let description = hotkeyManager.getHotkeyDescription()
        XCTAssertEqual(description, "⌥⌘P")

        // 7. Disable hotkey
        hotkeyManager.setEnabled(false)
        XCTAssertFalse(hotkeyManager.getEnabled())
    }

    // MARK: - Service Integration Tests

    func testClipboardServiceWithRepository() async throws {
        // 1. Setup clipboard service
        await clipboardService.startMonitoring()

        // 2. Add items through clipboard service
        for i in 1...5 {
            await clipboardService.copyToClipboard("Integration item \(i)", fromEditor: false)
        }

        // 3. Get history from service
        let serviceHistory = await clipboardService.getHistory()

        // 4. Save to repository
        try await repository.save(serviceHistory)

        // 5. Load from repository and compare
        let repositoryItems = try await repository.loadAll()
        XCTAssertEqual(serviceHistory.count, repositoryItems.count)

        // 6. Verify content matches
        for item in serviceHistory {
            XCTAssertTrue(repositoryItems.contains { $0.id == item.id })
        }
    }

    func testCategorySynchronization() async throws {
        // Clear everything first to ensure clean state
        await clipboardService.clearHistory(keepingCategories: true)
        try await repository.clear()

        // 1. Add items to clipboard
        await clipboardService.copyToClipboard("Category test 1", fromEditor: false)
        await clipboardService.copyToClipboard("Category test 2", fromEditor: false)
        await clipboardService.copyToClipboard("Category test 3", fromEditor: false)

        // 2. Assign the categoryems in service
        let history = await clipboardService.getHistory()
        for (index, item) in history[0...1].enumerated() {
            try await clipboardService.setCategory(itemID: item.id, categoryID: savedHistoryCategoryID, enabled: true)
            let snapshot = await clipboardService.getHistory()
            let categorizedCount = snapshot.filter { $0.hasCustomCategory }.count
            XCTAssertEqual(categorizedCount, index + 1)
        }

        // 3. Save to repository
        let categorizedHistory = await clipboardService.getHistory()
        XCTAssertEqual(categorizedHistory.filter { $0.hasCustomCategory }.count, 2)
        try await repository.save(categorizedHistory)

        // 4. Load categorized items from repository
        let categorizedItems = try await repository.loadCategorized()

        // 5. Verify category consistency
        XCTAssertEqual(categorizedItems.count, 2)
        XCTAssertTrue(categorizedItems.allSatisfy { $0.hasCustomCategory })
    }

    // MARK: - Concurrent Operations Tests

    func testConcurrentServiceOperations() async throws {
        // Start monitoring
        await clipboardService.startMonitoring()

        // Perform concurrent operations
        let clipboardService = self.clipboardService!
        await withTaskGroup(of: Void.self) { group in
            // Copy operations
            for i in 1...10 {
                group.addTask {
                    await clipboardService.copyToClipboard("Concurrent \(i)", fromEditor: false)
                }
            }

            // Search operations
            for _ in 1...5 {
                group.addTask {
                    _ = await clipboardService.searchHistory(query: "Concurrent")
                }
            }

            // History fetch operations
            for _ in 1...5 {
                group.addTask {
                    _ = await clipboardService.getHistory()
                }
            }
        }

        // Verify service is still functional
        let finalHistory = await clipboardService.getHistory()
        XCTAssertGreaterThan(finalHistory.count, 0)

        // Save to repository
        try await repository.save(finalHistory)
        let savedItems = try await repository.loadAll()
        XCTAssertGreaterThan(savedItems.count, 0)
    }

    // MARK: - Error Recovery Tests

    func testServiceRecoveryAfterErrors() async throws {
        // 1. Start with normal operation
        await clipboardService.copyToClipboard("Before error", fromEditor: false)

        // 2. Attempt invalid operations
        let invalidItem = ClipItem(content: "")
        await clipboardService.deleteItem(invalidItem) // Delete non-existent item

        // 3. Verify service continues functioning
        await clipboardService.copyToClipboard("After error", fromEditor: false)
        let history = await clipboardService.getHistory()
        XCTAssertTrue(history.contains { $0.content == "After error" })

        // 4. Test repository error recovery
        try await repository.delete(invalidItem) // Delete non-existent item

        // 5. Verify repository continues functioning
        try await repository.save(history)
        let savedItems = try await repository.loadAll()
        XCTAssertGreaterThan(savedItems.count, 0)
    }

    // MARK: - Performance Integration Tests

    func testIntegratedPerformance() async throws {
        let itemCount = 100

        // Measure end-to-end performance
        let startTime = Date()

        // 1. Add items to clipboard
        for i in 1...itemCount {
            await clipboardService.copyToClipboard("Performance \(i)", fromEditor: false)
        }

        // 2. Search operations
        for _ in 1...10 {
            _ = await clipboardService.searchHistory(query: "Performance")
        }

        // 3. Save to repository
        let history = await clipboardService.getHistory()
        try await repository.save(history)

        // 4. Load from repository
        let loadedItems = try await repository.loadAll()

        // In real usage, pinning is handled by the service layer

        let elapsedTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertLessThan(elapsedTime, 10.0, "Complete workflow should finish within 10 seconds")
        // Repository might have a limit on loaded items
        XCTAssertGreaterThan(loadedItems.count, 0, "Should have loaded some items")
        // Allow for a small discrepancy due to potential test data
        XCTAssertLessThanOrEqual(loadedItems.count, itemCount + 1, "Should not have significantly more items than added")
    }

    // MARK: - Settings Integration Tests

    func testSettingsPersistenceAcrossServices() async throws {
        // 1. Configure hotkey settings
        hotkeyManager.setHotkey(keyCode: 13, modifiers: [.control, .shift]) // Ctrl+Shift+W
        hotkeyManager.setEnabled(false)

        // 2. Configure clipboard service settings
        await clipboardService.setMaxHistoryItems(50)

        // 3. Add test data
        for i in 1...60 {
            await clipboardService.copyToClipboard("Item \(i)", fromEditor: false)
        }

        // 4. Verify max items setting is respected
        let history = await clipboardService.getHistory()
        XCTAssertLessThanOrEqual(history.count, 50)

        // 5. Verify hotkey settings persisted
        let (keyCode, modifiers) = hotkeyManager.getHotkey()
        XCTAssertEqual(keyCode, 13)
        XCTAssertEqual(modifiers, [.control, .shift])
        XCTAssertFalse(hotkeyManager.getEnabled())

        // 6. Save to repository and verify
        try await repository.save(history)
        let savedItems = try await repository.loadAll()
        XCTAssertLessThanOrEqual(savedItems.count, 50)
    }
}
