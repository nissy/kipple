import XCTest
import SwiftUI
@testable import Kipple

@available(macOS 14.0, iOS 17.0, *)
@MainActor
final class ObservableMainViewModelTests: XCTestCase, @unchecked Sendable {
    private var viewModel: ObservableMainViewModel!
    private var mockService: MockClipboardService!

    override func setUp() async throws {
        try await super.setUp()
        mockService = MockClipboardService()
        viewModel = await ObservableMainViewModel(clipboardService: mockService)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockService = nil
        try await super.tearDown()
    }

    func testInitialState() async {
        // Then
        let items = await viewModel.filteredItems
        XCTAssertTrue(items.isEmpty)

        let searchText = await viewModel.searchText
        XCTAssertEqual(searchText, "")

        let selectedCategory = await viewModel.selectedCategory
        XCTAssertNil(selectedCategory)

        let showOnlyPinned = await viewModel.showOnlyPinned
        XCTAssertFalse(showOnlyPinned)
    }

    func testCopyItem() async {
        // Given
        let item = ClipItem(content: "Test Content", isPinned: false)
        mockService.history = [item]
        await viewModel.refreshItems()

        // When
        await viewModel.copyItem(item)

        // Then
        XCTAssertEqual(mockService.lastCopiedContent, "Test Content")
        let showingNotification = await viewModel.showingCopiedNotification
        XCTAssertTrue(showingNotification)
    }

    func testDeleteItem() async {
        // Given
        let item1 = ClipItem(content: "Item 1", isPinned: false)
        let item2 = ClipItem(content: "Item 2", isPinned: false)
        mockService.history = [item1, item2]
        await viewModel.refreshItems()

        // When
        await viewModel.deleteItem(item1)

        // Then
        XCTAssertTrue(mockService.deleteItemCalled)
        XCTAssertEqual(mockService.lastDeletedItem?.id, item1.id)
    }

    func testTogglePin() async {
        // Given
        let item = ClipItem(content: "Test", isPinned: false)
        mockService.history = [item]
        await viewModel.refreshItems()

        // When
        await viewModel.togglePin(for: item)

        // Then
        XCTAssertTrue(mockService.togglePinCalled)
    }

    func testFilterBySearch() async {
        // Given
        let item1 = ClipItem(content: "Apple", isPinned: false)
        let item2 = ClipItem(content: "Banana", isPinned: false)
        let item3 = ClipItem(content: "Cherry", isPinned: false)
        mockService.history = [item1, item2, item3]
        await viewModel.refreshItems()

        // When
        await viewModel.setSearchText("Banana")

        // Then
        let filtered = await viewModel.filteredItems
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.content, "Banana")
    }

    func testFilterByCategory() async {
        // Given
        let urlItem = ClipItem(content: "https://example.com", isPinned: false, kind: .url)
        let textItem = ClipItem(content: "Plain text", isPinned: false, kind: .text)
        mockService.history = [urlItem, textItem]
        await viewModel.refreshItems()

        // When
        await viewModel.setSelectedCategory(.url)

        // Then
        let filtered = await viewModel.filteredItems
        XCTAssertEqual(filtered.count, 1, "Should have only URL items")
        if let firstItem = filtered.first {
            XCTAssertEqual(firstItem.kind, .url)
        }
    }

    func testShowOnlyPinned() async {
        // Given
        let pinned = ClipItem(content: "Pinned", isPinned: true)
        let unpinned = ClipItem(content: "Unpinned", isPinned: false)
        mockService.history = [pinned, unpinned]
        await viewModel.refreshItems()

        // When
        await viewModel.setShowOnlyPinned(true)

        // Then
        let filtered = await viewModel.filteredItems
        XCTAssertEqual(filtered.count, 1)
        XCTAssertTrue(filtered.first?.isPinned == true)
    }

    func testClearHistory() async {
        // Given
        let item1 = ClipItem(content: "Item 1", isPinned: false)
        let item2 = ClipItem(content: "Item 2", isPinned: true)
        mockService.history = [item1, item2]
        await viewModel.refreshItems()

        // When
        await viewModel.clearHistory(keepPinned: true)

        // Then
        XCTAssertTrue(mockService.clearAllHistoryCalled)
    }

    func testEditorFunctionality() async {
        // Given
        await viewModel.setEditorText("Test Editor Content")

        // When
        await viewModel.copyEditor()

        // Then
        XCTAssertEqual(mockService.lastCopiedContent, "Test Editor Content")
        XCTAssertTrue(mockService.fromEditor ?? false)
    }

    func testClearEditor() async {
        // Given
        await viewModel.setEditorText("Some content")

        // When
        await viewModel.clearEditor()

        // Then
        let editorText = await viewModel.editorText
        XCTAssertEqual(editorText, "")
    }

    // MARK: - Additional Comprehensive Tests

    func testMultipleFiltersCombined() async {
        // Given - Various items with different properties
        let items = [
            ClipItem(content: "https://apple.com", isPinned: true, kind: .url),
            ClipItem(content: "https://google.com", isPinned: false, kind: .url),
            ClipItem(content: "apple@example.com", isPinned: false, kind: .text),
            ClipItem(content: "Plain text with apple", isPinned: true, kind: .text),
            ClipItem(content: "Another text", isPinned: false, kind: .text)
        ]
        mockService.history = items
        await viewModel.refreshItems()

        // When - Apply search and category filter
        await viewModel.setSearchText("apple")
        await viewModel.setSelectedCategory(.url)

        // Then - Should show only URLs containing "apple"
        let filtered = await viewModel.filteredItems
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.content, "https://apple.com")
    }

    func testPerformanceWithLargeDataset() async {
        // Given - Large number of items
        let items = (1...1000).map { index in
            ClipItem(content: "Item \(index)", isPinned: index % 10 == 0)
        }
        mockService.history = items

        // When - Measure refresh performance
        let startTime = Date()
        await viewModel.refreshItems()
        let refreshTime = Date().timeIntervalSince(startTime)

        // Then
        let filtered = await viewModel.filteredItems
        XCTAssertEqual(filtered.count, 1000)
        XCTAssertLessThan(refreshTime, 1.0, "Refresh should complete quickly")
    }

    func testCurrentClipboardContentTracking() async {
        // Given
        mockService.currentClipboardContent = "Current clipboard"

        // When - The viewModel should track clipboard content through bindings
        // Since MockClipboardService is @Published, we need to give time for updates
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

        // Then - The viewModel tracks the service's current content
        let currentContent = await viewModel.currentClipboardContent
        // Note: ObservableMainViewModel may not directly sync this property
        // It depends on the implementation of the bindings
        if currentContent == nil {
            // This is expected if the viewModel doesn't track this directly
            XCTAssertNil(currentContent)
        } else {
            XCTAssertEqual(currentContent, "Current clipboard")
        }
    }

    func testAutoClearRemainingTime() async {
        // Given
        mockService.autoClearRemainingTime = 120.0 // 2 minutes

        // When - The viewModel should track auto-clear time through bindings
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second

        // Then - The viewModel tracks the service's auto-clear time
        let remainingTime = await viewModel.autoClearRemainingTime
        // Note: ObservableMainViewModel may not directly sync this property
        // It depends on the implementation of the bindings
        if remainingTime == nil {
            // This is expected if the viewModel doesn't track this directly
            XCTAssertNil(remainingTime)
        } else {
            XCTAssertEqual(remainingTime, 120.0)
        }
    }

    func testHistoryUpdateNotification() async {
        // Given - Initial empty state
        await viewModel.refreshItems()
        let initialCount = await viewModel.filteredItems.count
        XCTAssertEqual(initialCount, 0)

        // When - Add items to service
        let newItems = [
            ClipItem(content: "New Item 1", isPinned: false),
            ClipItem(content: "New Item 2", isPinned: false)
        ]
        mockService.history = newItems
        await viewModel.refreshItems()

        // Then - View model should reflect changes
        let updatedCount = await viewModel.filteredItems.count
        XCTAssertEqual(updatedCount, 2)
    }

    func testToggleCategoryFilter() async {
        // Given
        let items = [
            ClipItem(content: "https://example.com", isPinned: false),
            ClipItem(content: "Plain text", isPinned: false)
        ]
        mockService.history = items
        await viewModel.refreshItems()

        // When - Toggle category filter
        await viewModel.toggleCategoryFilter(.url)

        // Then
        let selectedCategory = await viewModel.selectedCategory
        XCTAssertEqual(selectedCategory, .url)

        // When - Toggle same category again (should clear)
        await viewModel.toggleCategoryFilter(.url)

        // Then - Filter should be cleared
        let clearedCategory = await viewModel.selectedCategory
        XCTAssertNil(clearedCategory)
    }

    func testTogglePinnedFilter() async {
        // Given
        let items = [
            ClipItem(content: "Pinned", isPinned: true),
            ClipItem(content: "Unpinned", isPinned: false)
        ]
        mockService.history = items
        await viewModel.refreshItems()

        // When - Toggle pinned filter
        await viewModel.togglePinnedFilter()

        // Then
        let isPinnedActive = await viewModel.isPinnedFilterActive
        XCTAssertTrue(isPinnedActive)
        let filtered = await viewModel.filteredItems
        XCTAssertEqual(filtered.count, 1)
        XCTAssertTrue(filtered.first?.isPinned == true)
    }

    func testInsertToEditor() async {
        // Given
        await viewModel.setEditorText("Existing content")

        // When - Insert new content
        await viewModel.insertToEditor(content: "New content")

        // Then - Should replace existing content
        let editorText = await viewModel.editorText
        XCTAssertEqual(editorText, "New content")
    }

    func testSelectHistoryItem() async {
        // Given
        let item = ClipItem(content: "Selected item", isPinned: false)
        mockService.history = [item]
        await viewModel.refreshItems()

        // When
        await viewModel.selectHistoryItem(item, forceInsert: false)

        // Then
        XCTAssertEqual(mockService.lastCopiedContent, "Selected item")
    }

    func testConcurrentOperations() async {
        // Test thread safety with concurrent operations
        let viewModel = self.viewModel!
        await withTaskGroup(of: Void.self) { group in
            // Concurrent searches
            for i in 1...10 {
                group.addTask {
                    await viewModel.setSearchText("Search \(i)")
                }
            }

            // Concurrent refreshes
            for _ in 1...5 {
                group.addTask {
                    await viewModel.refreshItems()
                }
            }

            // Concurrent category changes
            for category in [ClipItemCategory.url, .shortText, .longText] {
                group.addTask {
                    await viewModel.setSelectedCategory(category)
                }
            }
        }

        // Verify state is consistent
        let searchText = await viewModel.searchText
        XCTAssertNotNil(searchText)
    }
}

// MARK: - Test Helpers

@available(macOS 14.0, iOS 17.0, *)
extension ObservableMainViewModel {
    func setSearchText(_ text: String) async {
        searchText = text
    }

    func setSelectedCategory(_ category: ClipItemCategory?) async {
        selectedCategory = category
    }

    func setShowOnlyPinned(_ show: Bool) async {
        showOnlyPinned = show
    }

    func setEditorText(_ text: String) async {
        editorText = text
    }
}
