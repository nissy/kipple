//
//  SearchAndFilterTests.swift
//  KippleTests
//
//  カテゴリ（URL または None）とピンフィルターの挙動を検証します。

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
            ClipItem(content: "https://example.com", isPinned: false), // URL
            ClipItem(content: "Short memo", isPinned: true),            // None
            ClipItem(content: String(repeating: "Long text sample. ", count: 15),
                    isPinned: false)                                     // None
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

    // MARK: - Pinned Filter Tests

    func testPinnedFilter() {
        viewModel.showOnlyPinned = true
        XCTAssertEqual(viewModel.filteredHistory.count, 1)
        XCTAssertTrue(viewModel.filteredHistory.allSatisfy { $0.isPinned })
    }

    func testCategorySelectionAndPinnedFilterCanBeChangedIndependently() {
        let pinnedURL = ClipItem(content: "https://example.com/pinned", isPinned: true)
        let pinnedMemo = ClipItem(content: "Pinned memo", isPinned: true)
        let otherMemo = ClipItem(content: "Other memo", isPinned: false)
        mockClipboardService.history = [
            pinnedURL, pinnedMemo, otherMemo,
            ClipItem(content: "https://example.com/unpinned", isPinned: false)
        ]
        viewModel.updateFilteredItems(mockClipboardService.history)

        viewModel.categoryFilter.toggleSingleSelection(BuiltInCategory.url)
        viewModel.togglePinnedFilter()
        XCTAssertEqual(viewModel.history.map(\.id), [pinnedURL.id])

        viewModel.categoryFilter.toggleSingleSelection(BuiltInCategory.none)
        XCTAssertEqual(viewModel.categoryFilter.ids, [BuiltInCategory.none])
        XCTAssertEqual(viewModel.history.map(\.id), [pinnedMemo.id])

        viewModel.togglePinnedFilter()
        XCTAssertEqual(Set(viewModel.history.map(\.id)), [pinnedMemo.id, otherMemo.id])

        viewModel.togglePinnedFilter()
        viewModel.categoryFilter.toggleSingleSelection(BuiltInCategory.none)
        XCTAssertTrue(viewModel.categoryFilter.ids.isEmpty)
        XCTAssertTrue(viewModel.isPinnedFilterActive)
        XCTAssertEqual(Set(viewModel.history.map(\.id)), [pinnedURL.id, pinnedMemo.id])
    }

    // MARK: - Toggle Behavior

    func testToggleCategoryFilterClearsSelection() {
        viewModel.toggleCategoryFilter(.url)
        XCTAssertEqual(viewModel.categoryFilter.ids, [BuiltInCategory.url])
        viewModel.toggleCategoryFilter(.url)
        XCTAssertTrue(viewModel.categoryFilter.ids.isEmpty)
    }

    // MARK: - Performance

    func testCategoryFilterPerformance() {
        for i in 0..<1000 {
            mockClipboardService.history.append(
                ClipItem(content: "Item \(i)", isPinned: i % 10 == 0)
            )
        }

        measure {
            viewModel.updateFilteredItems(mockClipboardService.history)
            viewModel.toggleCategoryFilter(.url)
            viewModel.showOnlyPinned = true
            viewModel.showOnlyPinned = false
            viewModel.toggleCategoryFilter(.all)
        }
    }
}
