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

    override func setUp() {
        super.setUp()
        mockClipboardService = MockClipboardService()
        viewModel = MainViewModel(clipboardService: mockClipboardService)
        cancellables.removeAll()
        setupTestHistory()
        viewModel.updateFilteredItems(mockClipboardService.history)
    }

    override func tearDown() {
        mockClipboardService?.reset()
        viewModel = nil
        mockClipboardService = nil
        cancellables.removeAll()
        super.tearDown()
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
        XCTAssertEqual(viewModel.selectedCategory, .url)
    }

    func testCategoryFilterAllResetsSelection() {
        viewModel.toggleCategoryFilter(.url)
        XCTAssertEqual(viewModel.filteredHistory.count, 1)

        viewModel.toggleCategoryFilter(.all)

        XCTAssertNil(viewModel.selectedCategory)
        XCTAssertEqual(viewModel.filteredHistory.count, mockClipboardService.history.count)
    }

    // MARK: - Pinned Filter Tests

    func testPinnedFilter() {
        viewModel.showOnlyPinned = true
        XCTAssertEqual(viewModel.filteredHistory.count, 1)
        XCTAssertTrue(viewModel.filteredHistory.allSatisfy { $0.isPinned })
    }

    // MARK: - Toggle Behavior

    func testToggleCategoryFilterClearsSelection() {
        viewModel.toggleCategoryFilter(.url)
        XCTAssertEqual(viewModel.selectedCategory, .url)
        viewModel.toggleCategoryFilter(.url)
        XCTAssertNil(viewModel.selectedCategory)
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
