//
//  MainViewModelSaveEditorTests.swift
//  KippleTests
//

import XCTest
@testable import Kipple

@MainActor
final class MainViewModelSaveEditorTests: XCTestCase {
    private var viewModel: MainViewModel!
    private var mockClipboardService: MockClipboardService!

    override func setUp() async throws {
        try await super.setUp()
        mockClipboardService = MockClipboardService()
        viewModel = MainViewModel(clipboardService: mockClipboardService)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockClipboardService = nil
        try await super.tearDown()
    }

    func testSaveEditorToHistoryDoesNothingWhenTextIsUnchangedFromClipboardSource() async {
        mockClipboardService.currentClipboardContent = "same content"
        viewModel = MainViewModel(clipboardService: mockClipboardService)
        viewModel.editorText = "same content"

        let count = await viewModel.saveEditorToHistory()

        XCTAssertEqual(count, 0)
        XCTAssertFalse(viewModel.canSaveEditorToHistory)
        XCTAssertEqual(mockClipboardService.addEditorItemsCallCount, 0)
        XCTAssertNil(mockClipboardService.lastAddEditorItemsInput)
    }

    func testSaveEditorToHistoryAllowsTextThatMatchesDifferentHistoryItem() async {
        mockClipboardService.currentClipboardContent = "source content"
        mockClipboardService.history = [
            ClipItem(content: "source content"),
            ClipItem(content: "other history content")
        ]
        viewModel = MainViewModel(clipboardService: mockClipboardService)
        viewModel.beginClipboardEditing()
        viewModel.editorText = "other history content"

        let count = await viewModel.saveEditorToHistory()

        XCTAssertEqual(count, 1)
        XCTAssertEqual(mockClipboardService.addEditorItemsCallCount, 1)
        XCTAssertEqual(mockClipboardService.lastAddEditorItemsInput, ["other history content"])
    }

    func testSaveEditorToHistoryIsAvailableAfterEditingEndsWhenHistoryDoesNotContainText() async {
        mockClipboardService.currentClipboardContent = "original"
        viewModel = MainViewModel(clipboardService: mockClipboardService)
        viewModel.beginClipboardEditing()
        viewModel.editorText = "edited but unsaved"
        viewModel.commitClipboardEditor()

        let count = await viewModel.saveEditorToHistory()

        XCTAssertEqual(viewModel.currentClipboardContent, "edited but unsaved")
        XCTAssertEqual(count, 1)
        XCTAssertEqual(mockClipboardService.addEditorItemsCallCount, 1)
        XCTAssertEqual(mockClipboardService.lastAddEditorItemsInput, ["edited but unsaved"])
    }

    func testSaveEditorToHistoryStaysAvailableAfterClipboardOnlyRefresh() async throws {
        _ = try await prepareAdapterBackedViewModel(sourceText: "original")
        commitEditorText("edited but unsaved")

        XCTAssertTrue(viewModel.canSaveEditorToHistory)

        try await Task.sleep(for: .milliseconds(5_500))

        XCTAssertEqual(viewModel.editorText, "edited but unsaved")
        XCTAssertTrue(viewModel.canSaveEditorToHistory)
    }

    func testSaveEditorToHistoryStaysAvailableAfterMultipleClipboardOnlyRefreshes() async throws {
        _ = try await prepareAdapterBackedViewModel(sourceText: "original")
        commitEditorText("edited across multiple refreshes")

        XCTAssertTrue(viewModel.canSaveEditorToHistory)

        try await Task.sleep(for: .milliseconds(10_500))

        XCTAssertEqual(viewModel.editorText, "edited across multiple refreshes")
        XCTAssertTrue(viewModel.canSaveEditorToHistory)
    }

    func testExternalClipboardChangeAfterClipboardOnlyWriteResetsSaveState() async throws {
        let adapter = try await prepareAdapterBackedViewModel(sourceText: "original")
        commitEditorText("edited but overwritten")

        XCTAssertTrue(viewModel.canSaveEditorToHistory)

        adapter.copyToClipboard("external copy", fromEditor: false)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(viewModel.editorText, "external copy")
        XCTAssertFalse(viewModel.canSaveEditorToHistory)
    }

    func testSavedEditorTextStaysUnavailableAfterClipboardOnlyRefresh() async throws {
        _ = try await prepareAdapterBackedViewModel(sourceText: "original")
        commitEditorText("edited and saved after refresh")

        let count = await viewModel.saveEditorToHistory()
        XCTAssertEqual(count, 1)
        XCTAssertFalse(viewModel.canSaveEditorToHistory)

        try await Task.sleep(for: .milliseconds(5_500))

        XCTAssertEqual(viewModel.editorText, "edited and saved after refresh")
        XCTAssertFalse(viewModel.canSaveEditorToHistory)
    }

    func testSaveEditorToHistoryBecomesUnavailableAfterSavingChangedText() async {
        mockClipboardService.currentClipboardContent = "original"
        viewModel = MainViewModel(clipboardService: mockClipboardService)
        viewModel.beginClipboardEditing()
        viewModel.editorText = "edited and saved"

        let count = await viewModel.saveEditorToHistory()

        XCTAssertEqual(count, 1)
        XCTAssertFalse(viewModel.canSaveEditorToHistory)
        XCTAssertEqual(mockClipboardService.lastAddEditorItemsInput, ["edited and saved"])
    }

    func testSaveEditorToHistoryDoesNothingForEmptyText() async {
        mockClipboardService.currentClipboardContent = "original"
        viewModel = MainViewModel(clipboardService: mockClipboardService)
        viewModel.editorText = ""

        let count = await viewModel.saveEditorToHistory()

        XCTAssertEqual(count, 0)
        XCTAssertFalse(viewModel.canSaveEditorToHistory)
        XCTAssertEqual(mockClipboardService.addEditorItemsCallCount, 0)
        XCTAssertNil(mockClipboardService.lastAddEditorItemsInput)
    }

    func testSaveEditorToHistoryCountsWhitespaceOnlyText() async {
        mockClipboardService.currentClipboardContent = ""
        viewModel = MainViewModel(clipboardService: mockClipboardService)
        viewModel.editorText = " \n "

        let count = await viewModel.saveEditorToHistory()

        XCTAssertEqual(count, 1)
        XCTAssertFalse(viewModel.canSaveEditorToHistory)
        XCTAssertEqual(mockClipboardService.lastAddEditorItemsInput, [" \n "])
    }

    func testSaveEditorToHistoryCountsTrailingNewlineDifference() async {
        mockClipboardService.currentClipboardContent = "original"
        viewModel = MainViewModel(clipboardService: mockClipboardService)
        viewModel.editorText = "original\n"

        let count = await viewModel.saveEditorToHistory()

        XCTAssertEqual(count, 1)
        XCTAssertFalse(viewModel.canSaveEditorToHistory)
        XCTAssertEqual(mockClipboardService.lastAddEditorItemsInput, ["original\n"])
    }

    private func prepareAdapterBackedViewModel(sourceText: String) async throws -> ModernClipboardServiceAdapter {
        let adapter = ModernClipboardServiceAdapter.shared
        await ModernClipboardService.shared.resetForTesting()
        await adapter.clearHistory(keepPinned: false)
        adapter.copyToClipboard(sourceText, fromEditor: false)
        try await Task.sleep(for: .milliseconds(300))
        viewModel = MainViewModel(clipboardService: adapter)
        return adapter
    }

    private func commitEditorText(_ text: String) {
        viewModel.beginClipboardEditing()
        viewModel.editorText = text
        viewModel.commitClipboardEditor()
    }
}
