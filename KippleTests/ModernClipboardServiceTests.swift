import XCTest
import AppKit
@testable import Kipple

// MARK: - ModernClipboardService Tests

final class ModernClipboardServiceTests: XCTestCase, @unchecked Sendable {
    private var service: ModernClipboardService!

    override func setUp() async throws {
        try await super.setUp()
        service = ModernClipboardService.shared
        await service.resetForTesting()
    }

    override func tearDown() async throws {
        await service.stopMonitoring()
        service = nil
        try await super.tearDown()
    }

    // MARK: - Basic Functionality Tests

    func testInitialState() async {
        // Then
        let history = await service.getHistory()
        XCTAssertTrue(history.isEmpty)

        let isMonitoring = await service.isMonitoring()
        XCTAssertFalse(isMonitoring)
    }

    func testStartMonitoring() async {
        // When
        await service.startMonitoring()

        // Then
        let isMonitoring = await service.isMonitoring()
        XCTAssertTrue(isMonitoring)
    }

    func testStopMonitoring() async {
        // Given
        await service.startMonitoring()

        // When
        await service.stopMonitoring()

        // Then
        let isMonitoring = await service.isMonitoring()
        XCTAssertFalse(isMonitoring)
    }

    func testCopyToClipboard() async {
        // Given
        let content = "Test content"

        // When
        await service.copyToClipboard(content, fromEditor: false)

        // Then - Should mark as internal copy
        let clipboardValue = await MainActor.run { NSPasteboard.general.string(forType: .string) }
        XCTAssertEqual(clipboardValue, content)
    }

    func testWriteToClipboardOnlyDoesNotAddHistory() async {
        // Given
        let content = "Live editor only"

        // When
        await service.writeToClipboardOnly(content)

        // Then
        let clipboardValue = await MainActor.run { NSPasteboard.general.string(forType: .string) }
        let history = await service.getHistory()
        XCTAssertEqual(clipboardValue, content)
        XCTAssertTrue(history.isEmpty)
    }

    func testAddToHistory() async {
        // Given
        let content1 = "First item"
        let content2 = "Second item"

        // When
        await service.copyToClipboard(content1, fromEditor: false)
        await service.copyToClipboard(content2, fromEditor: true)

        // Then
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].content, content2) // Most recent first
        XCTAssertEqual(history[1].content, content1)
        XCTAssertTrue(history[0].isFromEditor ?? false)
    }

    func testDuplicateDetection() async {
        // Given
        let content = "Duplicate content"

        // When - Add same content multiple times
        await service.copyToClipboard(content, fromEditor: false)
        await service.copyToClipboard(content, fromEditor: false)
        await service.copyToClipboard(content, fromEditor: false)

        // Then - Should only have one entry
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
    }

    func testHistorySizeLimit() async {
        // Given - Add items exceeding the limit
        for i in 1...1005 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }

        // Then - History should be limited to 1000
        let history = await service.getHistory()
        XCTAssertLessThanOrEqual(history.count, 1000)
        XCTAssertEqual(history.first?.content, "Item 1005") // Most recent
    }

    func testTogglePin() async {
        // Given
        await service.copyToClipboard("Test item", fromEditor: false)
        let history = await service.getHistory()
        let item = history[0]

        // When
        let isPinned = await service.togglePin(for: item)

        // Then
        XCTAssertTrue(isPinned)
        let updatedHistory = await service.getHistory()
        XCTAssertTrue(updatedHistory[0].isPinned)
    }

    func testExternalRepeatedCopyAutoPinsWithinConfiguredWindow() async {
        // Given
        let baseDate = Date()
        await MainActor.run {
            AppSettings.shared.autoPinRepeatedCopyIntervalSeconds = 5
            AppSettings.shared.autoPinRepeatedCopyCount = 3
        }

        // When
        await service.addExternalClipboardItemForTesting("Repeated text", copiedAt: baseDate)
        await service.addExternalClipboardItemForTesting("Repeated text", copiedAt: baseDate.addingTimeInterval(2))
        await service.addExternalClipboardItemForTesting("Repeated text", copiedAt: baseDate.addingTimeInterval(4))

        // Then
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].content, "Repeated text")
        XCTAssertTrue(history[0].isPinned)
    }

    func testExternalRepeatedCopyDoesNotAutoPinOutsideConfiguredWindow() async {
        // Given
        let baseDate = Date()
        await MainActor.run {
            AppSettings.shared.autoPinRepeatedCopyIntervalSeconds = 5
            AppSettings.shared.autoPinRepeatedCopyCount = 3
        }

        // When
        await service.addExternalClipboardItemForTesting("Slow repeated text", copiedAt: baseDate)
        await service.addExternalClipboardItemForTesting("Slow repeated text", copiedAt: baseDate.addingTimeInterval(6))
        await service.addExternalClipboardItemForTesting("Slow repeated text", copiedAt: baseDate.addingTimeInterval(7))

        // Then
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertFalse(history[0].isPinned)
    }

    func testExternalRepeatedCopyDoesNotAutoPinWhenDisabled() async {
        // Given
        let baseDate = Date()
        await MainActor.run {
            AppSettings.shared.autoPinRepeatedCopyEnabled = false
            AppSettings.shared.autoPinRepeatedCopyIntervalSeconds = 5
            AppSettings.shared.autoPinRepeatedCopyCount = 3
        }

        // When
        await service.addExternalClipboardItemForTesting("Disabled auto pin", copiedAt: baseDate)
        await service.addExternalClipboardItemForTesting("Disabled auto pin", copiedAt: baseDate.addingTimeInterval(1))
        await service.addExternalClipboardItemForTesting("Disabled auto pin", copiedAt: baseDate.addingTimeInterval(2))

        // Then
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertFalse(history[0].isPinned)
    }

    func testDisablingAutoPinResetsRepeatedCopySequence() async {
        // Given
        let baseDate = Date()
        await service.addExternalClipboardItemForTesting("Reset sequence", copiedAt: baseDate)
        await service.addExternalClipboardItemForTesting("Reset sequence", copiedAt: baseDate.addingTimeInterval(1))

        // When
        await MainActor.run {
            AppSettings.shared.autoPinRepeatedCopyEnabled = false
        }
        await service.addExternalClipboardItemForTesting("Reset sequence", copiedAt: baseDate.addingTimeInterval(2))
        await MainActor.run {
            AppSettings.shared.autoPinRepeatedCopyEnabled = true
        }
        await service.addExternalClipboardItemForTesting("Reset sequence", copiedAt: baseDate.addingTimeInterval(3))

        // Then
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertFalse(history[0].isPinned)
    }

    func testExternalRepeatedCopyRequiresExactContentMatch() async {
        // Given
        let baseDate = Date()

        // When
        await service.addExternalClipboardItemForTesting("Exact text", copiedAt: baseDate)
        await service.addExternalClipboardItemForTesting("Exact text ", copiedAt: baseDate.addingTimeInterval(1))
        await service.addExternalClipboardItemForTesting("Exact text", copiedAt: baseDate.addingTimeInterval(2))

        // Then
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertFalse(history.contains { $0.isPinned })
    }

    func testExternalRepeatedCopyHonorsConfiguredCopyCount() async {
        // Given
        let baseDate = Date()
        await MainActor.run {
            AppSettings.shared.autoPinRepeatedCopyIntervalSeconds = 5
            AppSettings.shared.autoPinRepeatedCopyCount = 4
        }

        // When
        await service.addExternalClipboardItemForTesting("Four copies", copiedAt: baseDate)
        await service.addExternalClipboardItemForTesting("Four copies", copiedAt: baseDate.addingTimeInterval(1))
        await service.addExternalClipboardItemForTesting("Four copies", copiedAt: baseDate.addingTimeInterval(2))
        var history = await service.getHistory()

        // Then
        XCTAssertFalse(history[0].isPinned)

        // When
        await service.addExternalClipboardItemForTesting("Four copies", copiedAt: baseDate.addingTimeInterval(3))

        // Then
        history = await service.getHistory()
        XCTAssertTrue(history[0].isPinned)
    }

    func testRecopyFromHistoryDoesNotCountForAutoPin() async {
        // Given
        await service.addExternalClipboardItemForTesting("History recopy")
        var history = await service.getHistory()
        let item = history[0]

        // When
        await service.recopyFromHistory(item)
        history = await service.getHistory()
        let firstRecopy = history[0]
        await service.recopyFromHistory(firstRecopy)
        history = await service.getHistory()
        let secondRecopy = history[0]
        await service.recopyFromHistory(secondRecopy)

        // Then
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertFalse(history[0].isPinned)
    }

    func testExternalRepeatedCopyDoesNotAutoPinWhenPinnedLimitReached() async {
        // Given
        let baseDate = Date()
        await service.addExternalClipboardItemForTesting("Already pinned")
        var history = await service.getHistory()
        _ = await service.togglePin(for: history[0])

        await MainActor.run {
            AppSettings.shared.maxPinnedItems = 1
            AppSettings.shared.autoPinRepeatedCopyIntervalSeconds = 5
            AppSettings.shared.autoPinRepeatedCopyCount = 3
        }

        // When
        await service.addExternalClipboardItemForTesting("Limit target", copiedAt: baseDate)
        await service.addExternalClipboardItemForTesting("Limit target", copiedAt: baseDate.addingTimeInterval(1))
        await service.addExternalClipboardItemForTesting("Limit target", copiedAt: baseDate.addingTimeInterval(2))

        // Then
        history = await service.getHistory()
        let limitTarget = try? XCTUnwrap(history.first { $0.content == "Limit target" })
        XCTAssertEqual(history.filter { $0.isPinned }.count, 1)
        XCTAssertFalse(limitTarget?.isPinned ?? true)
    }

    func testDeleteItem() async {
        // Given
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)
        await service.copyToClipboard("Item 3", fromEditor: false)

        let history = await service.getHistory()
        let itemToDelete = history[1] // "Item 2"

        // When
        await service.deleteItem(itemToDelete)

        // Then
        let updatedHistory = await service.getHistory()
        XCTAssertEqual(updatedHistory.count, 2)
        XCTAssertFalse(updatedHistory.contains { $0.content == "Item 2" })
    }

    func testClearAllHistory() async {
        // Given
        await service.copyToClipboard("Item 1", fromEditor: false)
        await service.copyToClipboard("Item 2", fromEditor: false)

        // When
        await service.clearAllHistory()

        // Then
        let history = await service.getHistory()
        XCTAssertTrue(history.isEmpty)
    }

    func testClearHistoryKeepPinned() async {
        // Given
        await service.copyToClipboard("Unpinned 1", fromEditor: false)
        await service.copyToClipboard("Pinned item", fromEditor: false)
        await service.copyToClipboard("Unpinned 2", fromEditor: false)

        // Pin the middle item
        var history = await service.getHistory()
        _ = await service.togglePin(for: history[1])

        // When
        await service.clearHistory(keepPinned: true)

        // Then
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].content, "Pinned item")
        XCTAssertTrue(history[0].isPinned)
    }

    // MARK: - Performance Tests

    func testConcurrentAccess() async {
        // Test thread safety with concurrent operations
        let service = self.service!
        await withTaskGroup(of: Void.self) { group in
            // Multiple concurrent writes
            for i in 1...100 {
                group.addTask {
                    await service.copyToClipboard("Concurrent \(i)", fromEditor: false)
                }
            }

            // Multiple concurrent reads
            for _ in 1...50 {
                group.addTask {
                    _ = await service.getHistory()
                }
            }
        }

        // Verify data integrity
        let history = await service.getHistory()
        XCTAssertGreaterThan(history.count, 0)
    }

    func testDynamicIntervalAdjustment() async {
        // Given - Start monitoring
        await service.startMonitoring()

        // When - Simulate activity
        await service.copyToClipboard("Active item", fromEditor: false)
        let activeInterval = await service.getCurrentInterval()

        // Simulate inactivity (wait without adding items)
        try? await Task.sleep(for: .seconds(2))

        let inactiveInterval = await service.getCurrentInterval()

        // Then - Interval should stay within the tuned polling bounds
        XCTAssertGreaterThanOrEqual(activeInterval, 0.08)
        XCTAssertLessThanOrEqual(activeInterval, 0.25)
        XCTAssertGreaterThanOrEqual(inactiveInterval, 0.08)
        XCTAssertLessThanOrEqual(inactiveInterval, 0.25)
    }

    func testFromEditorFlag() async {
        // Given
        let editorContent = "Editor content"
        let normalContent = "Normal content"

        // When
        await service.copyToClipboard(editorContent, fromEditor: true)
        await service.copyToClipboard(normalContent, fromEditor: false)

        // Then
        let history = await service.getHistory()
        let editorItem = history.first { $0.content == editorContent }
        let normalItem = history.first { $0.content == normalContent }

        XCTAssertTrue(editorItem?.isFromEditor ?? false)
        XCTAssertFalse(normalItem?.isFromEditor ?? true)
    }

    func testGetCurrentClipboardContent() async {
        // Given
        let content = "Current clipboard"

        // When
        await service.copyToClipboard(content, fromEditor: false)

        // Then
        let current = await service.getCurrentClipboardContent()
        XCTAssertEqual(current, content)
    }

    func testUpdateItem() async {
        // Given
        await service.copyToClipboard("Original", fromEditor: false)
        var history = await service.getHistory()
        var item = history[0]

        // When - Update the item
        item.isPinned = true
        await service.updateItem(item)

        // Then
        history = await service.getHistory()
        let updatedItem = history.first { $0.id == item.id }
        XCTAssertTrue(updatedItem?.isPinned ?? false)
    }

    func testSearchHistory() async {
        // Given
        await service.copyToClipboard("Apple", fromEditor: false)
        await service.copyToClipboard("Banana", fromEditor: false)
        await service.copyToClipboard("Cherry", fromEditor: false)
        await service.copyToClipboard("Apple Pie", fromEditor: false)

        // When
        let searchResults = await service.searchHistory(query: "Apple")

        // Then
        XCTAssertEqual(searchResults.count, 2)
        XCTAssertTrue(searchResults.allSatisfy { $0.content.contains("Apple") })
    }

    func testMaxHistoryItemsConfiguration() async {
        // Given - Set a custom max history items
        await service.setMaxHistoryItems(5)

        // When - Add more items than the limit
        for i in 1...10 {
            await service.copyToClipboard("Item \(i)", fromEditor: false)
        }

        // Then
        let history = await service.getHistory()
        XCTAssertLessThanOrEqual(history.count, 5)
    }
}

// MARK: - ModernClipboardService Mock for Testing

actor ModernClipboardServiceMock: ModernClipboardServiceProtocol {
    private var history: [ClipItem] = []
    private var monitoring = false

    func getHistory() async -> [ClipItem] {
        history
    }

    func startMonitoring() async {
        monitoring = true
    }

    func stopMonitoring() async {
        monitoring = false
    }

    func isMonitoring() async -> Bool {
        monitoring
    }

    func copyToClipboard(_ content: String, fromEditor: Bool) async {
        let item = ClipItem(content: content, isFromEditor: fromEditor)
        history.insert(item, at: 0)
    }

    func writeToClipboardOnly(_ content: String) async {
        _ = content
    }

    func addEditorItems(_ contents: [String]) async -> [ClipItem] {
        let sanitized = contents
            .filter { !$0.isEmpty }

        guard !sanitized.isEmpty else { return [] }

        let created = sanitized.map {
            ClipItem(
                content: $0,
                sourceApp: "Kipple",
                windowTitle: "Live Editor",
                bundleIdentifier: Bundle.main.bundleIdentifier,
                processID: ProcessInfo.processInfo.processIdentifier,
                isFromEditor: true
            )
        }

        for item in created.reversed() {
            history.insert(item, at: 0)
        }

        return created
    }

    func recopyFromHistory(_ item: ClipItem) async {
        if let index = history.firstIndex(where: { $0.content == item.content }) {
            history.remove(at: index)
        }
        history.insert(item, at: 0)
    }

    func clearSystemClipboard() async {
        // In mock, clearing system clipboard just means we don't track pasteboard contents.
    }

    func clearAllHistory() async {
        history.removeAll()
    }

    func clearHistory(keepPinned: Bool) async {
        if keepPinned {
            history = history.filter { $0.isPinned }
        } else {
            history.removeAll()
        }
    }

    func togglePin(for item: ClipItem) async -> Bool {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index].isPinned.toggle()
            return history[index].isPinned
        }
        return false
    }

    func deleteItem(_ item: ClipItem) async {
        history.removeAll { $0.id == item.id }
    }

    func getCurrentClipboardContent() async -> String? {
        history.first?.content
    }

    func updateItem(_ item: ClipItem) async {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index] = item
        }
    }

    func searchHistory(query: String) async -> [ClipItem] {
        history.filter { $0.content.localizedCaseInsensitiveContains(query) }
    }

    func getCurrentInterval() async -> TimeInterval {
        0.5
    }

    func setMaxHistoryItems(_ max: Int) async {
        if history.count > max {
            history = Array(history.prefix(max))
        }
    }

    func flushPendingSaves() async {
        // No-op for mock
    }
}
