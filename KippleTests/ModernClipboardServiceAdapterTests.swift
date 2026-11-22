import XCTest
import Combine
@testable import Kipple

@MainActor
final class ModernClipboardServiceAdapterTests: XCTestCase {
    private var adapter: ModernClipboardServiceAdapter!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        try await super.setUp()
        // Create new adapter for each test
        adapter = ModernClipboardServiceAdapter.shared
        await ModernClipboardService.shared.resetForTesting()
        // Clear history before each test
        await adapter.clearHistory(keepingCategories: false)
    }

    override func tearDown() async throws {
        cancellables.removeAll()
        adapter = nil
        try await super.tearDown()
    }

    // MARK: - Basic Functionality Tests

    func testStartStopMonitoring() async {
        // When
        adapter.startMonitoring()

        // Give it time to start
        try? await Task.sleep(for: .milliseconds(100))

        // Then
        let isMonitoring = await adapter.isMonitoring()
        XCTAssertTrue(isMonitoring)

        // When
        adapter.stopMonitoring()

        // Give it time to stop
        try? await Task.sleep(for: .milliseconds(100))

        // Then
        let isMonitoringAfterStop = await adapter.isMonitoring()
        XCTAssertFalse(isMonitoringAfterStop)
    }

    func testCopyToClipboard() async {
        // Given
        let content = "Test adapter content"

        // When
        adapter.copyToClipboard(content, fromEditor: false)

        // Wait for async operation
        try? await Task.sleep(for: .milliseconds(200))

        // Then
        XCTAssertFalse(adapter.history.isEmpty)
        XCTAssertEqual(adapter.history.first?.content, content)
        XCTAssertEqual(adapter.currentClipboardContent, content)
    }

    func testWriteToClipboardOnlyDoesNotRefreshHistory() async {
        // Given
        let content = "Adapter live editor content"

        // When
        adapter.writeToClipboardOnly(content)
        try? await Task.sleep(for: .milliseconds(200))

        // Then
        XCTAssertTrue(adapter.history.isEmpty)
        XCTAssertEqual(adapter.currentClipboardContent, content)
    }

    func testHistoryPublisherUpdates() async {
        // Given
        let expectation = XCTestExpectation(description: "History updated")
        var receivedHistory: [ClipItem] = []

        adapter.$history
            .dropFirst() // Skip initial empty value
            .sink { history in
                receivedHistory = history
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        adapter.copyToClipboard("Published content", fromEditor: false)

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertFalse(receivedHistory.isEmpty)
        XCTAssertEqual(receivedHistory.first?.content, "Published content")
    }

    func testDeleteItem() async {
        // Given
        adapter.copyToClipboard("Item 1", fromEditor: false)
        adapter.copyToClipboard("Item 2", fromEditor: false)
        adapter.copyToClipboard("Item 3", fromEditor: false)

        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(adapter.history.count, 3)

        let itemToDelete = adapter.history[1]

        // When
        await adapter.deleteItem(itemToDelete)

        // Then
        XCTAssertEqual(adapter.history.count, 2)
        XCTAssertFalse(adapter.history.contains { $0.id == itemToDelete.id })
    }

    func testClearHistory() async {
        // Given
        adapter.copyToClipboard("Item 1", fromEditor: false)
        adapter.copyToClipboard("Item 2", fromEditor: false)

        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(adapter.history.isEmpty)

        // When
        await adapter.clearHistory(keepingCategories: false)

        // Then
        XCTAssertTrue(adapter.history.isEmpty)
    }

    func testClearHistoryKeepingCategories() async throws {
        // Given
        adapter.copyToClipboard("Uncategorized", fromEditor: false)
        adapter.copyToClipboard("To be categorized", fromEditor: false)

        try? await Task.sleep(for: .milliseconds(200))

        // Categorize one item
        let itemToCategorize = adapter.history.first { $0.content == "To be categorized" }!
        try await adapter.updateCategories(itemID: itemToCategorize.id, change: .set(savedHistoryCategoryID, enabled: true))

        try? await Task.sleep(for: .milliseconds(200))

        // When
        await adapter.clearHistory(keepingCategories: true)

        // Then
        XCTAssertEqual(adapter.history.count, 1)
        XCTAssertEqual(adapter.history.first?.content, "To be categorized")
        XCTAssertTrue(adapter.history.first?.hasCustomCategory ?? false)
    }

    func testSearchHistory() async {
        // Given
        adapter.copyToClipboard("Apple", fromEditor: false)
        adapter.copyToClipboard("Banana", fromEditor: false)
        adapter.copyToClipboard("Apple Pie", fromEditor: false)
        adapter.copyToClipboard("Cherry", fromEditor: false)

        try? await Task.sleep(for: .milliseconds(300))

        // When - Synchronous search
        let results = adapter.searchHistory("Apple")

        // Then
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.content.contains("Apple") })

        // When - Async search
        let asyncResults = await adapter.searchHistoryAsync("Apple")

        // Then
        XCTAssertEqual(asyncResults.count, 2)
    }

    func testRecopyUpdatesTimestampAndTriggersHistoryRefresh() async {
        adapter.copyToClipboard("Timestamp Test", fromEditor: false)
        try? await Task.sleep(for: .milliseconds(200))

        guard let originalItem = adapter.history.first else {
            XCTFail("Expected history item after copy")
            return
        }

        let originalTimestamp = originalItem.timestamp

        adapter.recopyFromHistory(originalItem)

        try? await Task.sleep(for: .milliseconds(200))

        guard let updatedItem = adapter.history.first else {
            XCTFail("Expected history item after recopy")
            return
        }

        XCTAssertEqual(updatedItem.id, originalItem.id)
        XCTAssertGreaterThan(updatedItem.timestamp, originalTimestamp)
    }

    func testPeriodicRefresh() async {
        // Given
        let expectation = XCTestExpectation(description: "History refreshed multiple times")
        expectation.expectedFulfillmentCount = 3

        adapter.$history
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When - Add items with delays
        adapter.copyToClipboard("Item 1", fromEditor: false)
        try? await Task.sleep(for: .milliseconds(600))

        adapter.copyToClipboard("Item 2", fromEditor: false)
        try? await Task.sleep(for: .milliseconds(600))

        adapter.copyToClipboard("Item 3", fromEditor: false)

        // Then
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testSetMaxHistoryItems() async {
        // Given
        await adapter.setMaxHistoryItems(3)

        // When - Add more items than the limit
        for i in 1...5 {
            adapter.copyToClipboard("Item \(i)", fromEditor: false)
        }

        try? await Task.sleep(for: .milliseconds(500))

        // Then
        XCTAssertLessThanOrEqual(adapter.history.count, 3)
    }
}
