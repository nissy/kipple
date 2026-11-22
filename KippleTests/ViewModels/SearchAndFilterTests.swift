//
//  SearchAndFilterTests.swift
//  KippleTests
//
//  履歴のカテゴリフィルタを検証します。

import XCTest
import Combine
@testable import Kipple

@MainActor
final class SearchAndFilterTests: XCTestCase, @unchecked Sendable {
    var viewModel: MainViewModel!
    var mockClipboardService: MockClipboardService!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() async throws {
        try await super.setUp()
        mockClipboardService = MockClipboardService()
        viewModel = MainViewModel(clipboardService: mockClipboardService)
        cancellables.removeAll()
        setupTestHistory()
        viewModel.updateFilteredItems(mockClipboardService.history)
    }

    override func tearDown() async throws {
        mockClipboardService?.reset()
        viewModel = nil
        mockClipboardService = nil
        cancellables.removeAll()
        try await super.tearDown()
    }

    private func setupTestHistory() {
        mockClipboardService.history = [
            ClipItem(content: "https://example.com"), // URL
            ClipItem(content: "Short memo", userCategoryId: savedHistoryCategoryID),            // None
            ClipItem(content: String(repeating: "Long text sample. ", count: 15))                                     // None
        ]
    }

    // MARK: - Category Filter Tests

    func testCategoryFilterURL() {
        viewModel.toggleCategoryFilter(.url)
        XCTAssertEqual(viewModel.filteredHistory.count, 1)
        XCTAssertEqual(viewModel.filteredHistory.first?.category, .url)
        XCTAssertEqual(viewModel.categoryFilter.ids, [BuiltInCategory.url])
    }

    func testCategoryFilterAllResetsSelection() {
        viewModel.toggleCategoryFilter(.url)
        XCTAssertEqual(viewModel.filteredHistory.count, 1)

        viewModel.toggleCategoryFilter(.all)

        XCTAssertTrue(viewModel.categoryFilter.ids.isEmpty)
        XCTAssertEqual(viewModel.filteredHistory.count, mockClipboardService.history.count)
    }

    func testCategoryFilterAvailabilityUsesHistoryOutsideVisiblePageAndSearch() {
        let memo = ClipItem(content: "Memo")
        let savedURL = ClipItem(
            content: "https://example.com",
            userCategoryId: savedHistoryCategoryID,
            metadata: ClipMetadata(source: .ocr)
        )
        mockClipboardService.history = [memo, savedURL]
        let pagedModel = MainViewModel(clipboardService: mockClipboardService, pageSize: 1)
        let expectedIDs: Set = [BuiltInCategory.none, BuiltInCategory.url, BuiltInCategory.ocr, savedHistoryCategoryID]

        XCTAssertEqual(pagedModel.history.map(\.id), [memo.id])
        XCTAssertEqual(pagedModel.historyCategoryIDs, expectedIDs)

        pagedModel.searchText = "Memo"
        pagedModel.updateFilteredItems(mockClipboardService.history)
        XCTAssertEqual(pagedModel.filteredHistory.map(\.id), [memo.id])
        XCTAssertEqual(pagedModel.historyCategoryIDs, expectedIDs)
    }

    func testHistoryUpdateClearsOnlySelectedCategoriesThatBecomeEmpty() {
        let memo = ClipItem(content: "Memo")
        var savedURL = ClipItem(content: "https://example.com", userCategoryId: savedHistoryCategoryID)
        mockClipboardService.history = [memo, savedURL]
        viewModel.loadHistory()
        viewModel.categoryFilter.ids = [BuiltInCategory.url, savedHistoryCategoryID]

        savedURL.setCategory(BuiltInCategory.url, enabled: false)
        mockClipboardService.history = [memo, savedURL]
        mockClipboardService.onHistoryChanged?(memo)
        XCTAssertEqual(viewModel.historyCategoryIDs, [BuiltInCategory.none, savedHistoryCategoryID])
        XCTAssertEqual(viewModel.categoryFilter.ids, [savedHistoryCategoryID])
        XCTAssertEqual(viewModel.history.map(\.id), [savedURL.id])

        savedURL.setCategory(savedHistoryCategoryID, enabled: false)
        mockClipboardService.history = [memo, savedURL]
        mockClipboardService.onHistoryChanged?(memo)
        XCTAssertEqual(viewModel.historyCategoryIDs, [BuiltInCategory.none])
        XCTAssertTrue(viewModel.categoryFilter.ids.isEmpty)
        XCTAssertEqual(viewModel.history.map(\.id), [memo.id, savedURL.id])
    }

    func testEmptyCategoryReturnsAtEndAndKeepsItsNewOrder() throws {
        let suite = "CategoryFilterOrderTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserCategoryStore(defaults: defaults)
        store.add(name: "Saved", iconSystemName: "tag", id: savedHistoryCategoryID)

        let url = ClipItem(content: "https://example.com")
        let ocr = ClipItem(content: "Captured text", metadata: ClipMetadata(source: .ocr))
        let saved = ClipItem(content: "Memo", userCategoryId: savedHistoryCategoryID)
        mockClipboardService.history = [url, ocr, saved]
        let model = MainViewModel(clipboardService: mockClipboardService, categoryStore: store)
        let initialOrder = [BuiltInCategory.url, BuiltInCategory.ocr, savedHistoryCategoryID]
        func activeOrder(in store: UserCategoryStore) -> [UUID] {
            store.orderedForFiltering().map(\.id).filter { model.historyCategoryIDs.contains($0) }
        }
        XCTAssertEqual(activeOrder(in: store), initialOrder)

        mockClipboardService.history.removeFirst()
        mockClipboardService.onHistoryChanged?(ocr)
        XCTAssertEqual(activeOrder(in: store), [BuiltInCategory.ocr, savedHistoryCategoryID])

        mockClipboardService.copyToClipboard(url.content, fromEditor: false)
        let newOrder = [BuiltInCategory.ocr, savedHistoryCategoryID, BuiltInCategory.url]
        XCTAssertEqual(activeOrder(in: store), newOrder)
        XCTAssertEqual(activeOrder(in: UserCategoryStore(defaults: defaults)), newOrder)

        store.moveFilter(BuiltInCategory.url, to: BuiltInCategory.ocr, among: newOrder)
        mockClipboardService.copyToClipboard("https://example.net", fromEditor: false)
        XCTAssertEqual(activeOrder(in: store), initialOrder)
    }

    func testOCRHighlightTemporarilyRevealsHistoryWithoutChangingFilters() throws {
        let url = try XCTUnwrap(mockClipboardService.history.first)
        let ocr = ClipItem(content: "Captured text", metadata: ClipMetadata(source: .ocr))
        mockClipboardService.history.insert(ocr, at: 0)
        viewModel.searchText = "example.com"
        viewModel.toggleCategoryFilter(.url)
        XCTAssertEqual(viewModel.history.map(\.id), [url.id])

        viewModel.highlightHistoryItem(ocr.id)
        let firstRequest = try XCTUnwrap(viewModel.historyHighlightRequest)
        viewModel.highlightHistoryItem(ocr.id)
        let secondRequest = try XCTUnwrap(viewModel.historyHighlightRequest)
        XCTAssertNotEqual(firstRequest.id, secondRequest.id)
        XCTAssertEqual(secondRequest.itemID, ocr.id)
        viewModel.finishHighlightingHistoryItem(firstRequest.id)
        XCTAssertEqual(viewModel.history.map(\.id), [ocr.id, url.id])
        XCTAssertEqual(viewModel.searchText, "example.com")
        XCTAssertEqual(viewModel.categoryFilter.ids, [BuiltInCategory.url])

        viewModel.finishHighlightingHistoryItem(secondRequest.id)
        XCTAssertNil(viewModel.historyHighlightRequest)
        XCTAssertEqual(viewModel.history.map(\.id), [url.id])
    }

    // MARK: - Toggle Behavior

    func testToggleCategoryFilterClearsSelection() {
        viewModel.toggleCategoryFilter(.url)
        XCTAssertEqual(viewModel.categoryFilter.ids, [BuiltInCategory.url])
        viewModel.toggleCategoryFilter(.url)
        XCTAssertTrue(viewModel.categoryFilter.ids.isEmpty)
    }

    func testCategoryTogglesKeepOtherSelectionsAndApplyTheMatchMode() {
        let url = ClipItem(content: "https://example.com")
        let memo = ClipItem(content: "Memo", userCategoryId: savedHistoryCategoryID)
        let savedURL = ClipItem(content: "https://example.com/saved", userCategoryId: savedHistoryCategoryID)
        mockClipboardService.history = [url, memo, savedURL]

        viewModel.toggleUserCategoryFilter(BuiltInCategory.url)
        viewModel.toggleUserCategoryFilter(savedHistoryCategoryID)
        XCTAssertEqual(viewModel.categoryFilter.ids, [BuiltInCategory.url, savedHistoryCategoryID])
        XCTAssertEqual(viewModel.filteredHistory.map(\.id), [savedURL.id])

        viewModel.categoryFilter.match = .any
        XCTAssertEqual(viewModel.filteredHistory.map(\.id), [url.id, memo.id, savedURL.id])

        viewModel.toggleUserCategoryFilter(BuiltInCategory.url)
        XCTAssertEqual(viewModel.categoryFilter.ids, [savedHistoryCategoryID])
        XCTAssertEqual(viewModel.filteredHistory.map(\.id), [memo.id, savedURL.id])
    }

    // MARK: - Performance

    func testCategoryFilterPerformance() {
        for i in 0..<1000 {
            mockClipboardService.history.append(
                ClipItem(content: "Item \(i)", userCategoryId: i % 10 == 0 ? savedHistoryCategoryID : nil)
            )
        }

        measure {
            viewModel.updateFilteredItems(mockClipboardService.history)
            viewModel.toggleCategoryFilter(.url)
            viewModel.categoryFilter.select(savedHistoryCategoryID)
            viewModel.toggleCategoryFilter(.all)
        }
    }
}
