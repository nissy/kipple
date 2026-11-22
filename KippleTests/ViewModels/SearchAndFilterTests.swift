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
