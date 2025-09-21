import XCTest
import SwiftUI
@testable import Kipple

@available(macOS 14.0, *)
final class MainViewIntegrationTests: XCTestCase {
    private var viewModel: ObservableMainViewModel!
    private var clipboardService: ClipboardServiceProtocol!
    private var repository: ClipboardRepositoryProtocol!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()

        // Set up test dependencies
        repository = try await SwiftDataRepository(inMemory: true)
        clipboardService = ClipboardService.shared

        // Clear history and stop monitoring before starting
        await clipboardService.clearHistory(keepPinned: false)
        clipboardService.stopMonitoring()

        viewModel = await ObservableMainViewModel(clipboardService: clipboardService)
    }

    @MainActor
    override func tearDown() async throws {
        // Ensure clipboard monitoring is stopped
        clipboardService.stopMonitoring()

        // Clear history
        await clipboardService.clearHistory(keepPinned: false)

        // Give time for cleanup
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        viewModel = nil
        clipboardService = nil
        repository = nil
        try await super.tearDown()
    }

    // MARK: - Observable Macro Tests

    @MainActor
    func testObservableMacroWorksWithSwiftUI() async {
        // Given: ObservableMainViewModel with @Observable macro

        // When: We access published properties
        let initialHistory = viewModel.filteredHistory
        let initialPinned = viewModel.pinnedHistory
        let searchText = viewModel.searchText

        // Then: Properties are accessible and observable
        XCTAssertNotNil(initialHistory)
        XCTAssertNotNil(initialPinned)
        XCTAssertEqual(searchText, "")
    }

    @MainActor
    func testViewModelPublishesChanges() async {
        // Given: Initial state
        let initialCount = viewModel.filteredHistory.count

        // When: Add new clipboard item (use fromEditor=true to ensure it's added to history)
        await clipboardService.copyToClipboard("Test item", fromEditor: true)

        // Allow time for async update
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 second

        // Manually refresh the view model
        await viewModel.refreshItems()

        // Then: History is updated
        XCTAssertGreaterThan(viewModel.filteredHistory.count, initialCount, "ViewModel should have updated")
    }

    // MARK: - Search Functionality Tests

    @MainActor
    func testSearchFiltering() async {
        // Given: Multiple items in history (use fromEditor=true to ensure they're added)
        await clipboardService.copyToClipboard("Apple", fromEditor: true)
        await clipboardService.copyToClipboard("Banana", fromEditor: true)
        await clipboardService.copyToClipboard("Cherry", fromEditor: true)

        // Allow time for updates
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Manually refresh the view model
        await viewModel.refreshItems()

        // When: Search for specific item
        viewModel.searchText = "Banana"

        // Then: Only matching items shown
        XCTAssertTrue(viewModel.filteredHistory.contains { $0.content.contains("Banana") })
        XCTAssertFalse(viewModel.filteredHistory.contains { $0.content.contains("Apple") })
    }

    // MARK: - Pinning Functionality Tests

    @MainActor
    func testPinningItem() async {
        // Given: An item in history (use fromEditor=true to ensure it's added)
        await clipboardService.copyToClipboard("Item to pin", fromEditor: true)
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Manually refresh the view model
        await viewModel.refreshItems()

        guard let item = viewModel.filteredHistory.first else {
            XCTFail("No items in history")
            return
        }

        // When: Pin the item
        await viewModel.togglePin(for: item)

        // Then: Item appears in pinned section
        XCTAssertTrue(viewModel.pinnedHistory.contains { $0.id == item.id })
    }

    // MARK: - Editor Functionality Tests

    @MainActor
    func testEditorTextBinding() async {
        // Given: Initial editor state
        XCTAssertEqual(viewModel.editorText, "")

        // When: Update editor text
        viewModel.editorText = "Test text"

        // Then: Editor text is updated
        XCTAssertEqual(viewModel.editorText, "Test text")
    }

    @MainActor
    func testCopyFromEditor() async {
        // Given: Text in editor
        viewModel.editorText = "Text from editor"

        // When: Copy from editor
        viewModel.copyEditor()

        // Allow time for async operation
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Manually refresh the view model
        await viewModel.refreshItems()

        // Then: Text is in clipboard history
        XCTAssertTrue(viewModel.filteredHistory.contains { $0.content == "Text from editor" })
    }

    // MARK: - Clear Functionality Tests

    @MainActor
    func testClearHistory() async {
        // Given: Items in history (use fromEditor=true to ensure they're added)
        await clipboardService.copyToClipboard("Item 1", fromEditor: true)
        await clipboardService.copyToClipboard("Item 2", fromEditor: true)
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Manually refresh the view model
        await viewModel.refreshItems()

        // When: Clear history
        await viewModel.clearHistory(keepPinned: true)

        // Then: History is cleared
        XCTAssertEqual(viewModel.filteredHistory.filter { !$0.isPinned }.count, 0)
    }

    // MARK: - View Integration Tests

    @MainActor
    func testMainViewCreation() async {
        // Given: ObservableMainViewModel

        // When: Create MainView with the view model
        let view = MainView()
            .environment(viewModel)

        // Then: View is created without crashes
        XCTAssertNotNil(view)
    }

    @MainActor
    func testViewModelProviderResolution() async {
        // Given: ViewModelProvider configured

        // When: Resolve MainViewModel
        let resolvedViewModel = await ViewModelProvider.resolve()

        // Then: Returns ObservableMainViewModel instance
        XCTAssertTrue(type(of: resolvedViewModel) == ObservableMainViewModel.self)
    }
}

// MARK: - Legacy Tests (macOS 13.0)

@MainActor
final class LegacyMainViewIntegrationTests: XCTestCase {
    private var viewModel: MainViewModel!
    private var clipboardService: ClipboardServiceProtocol!

    override func setUp() {
        super.setUp()

        // Set up legacy dependencies
        clipboardService = ClipboardService.shared
        viewModel = MainViewModel(clipboardService: clipboardService)
    }

    override func tearDown() {
        viewModel = nil
        clipboardService = nil
        super.tearDown()
    }

    func testLegacyViewModelWorks() {
        // Given: Legacy MainViewModel

        // When: Access properties
        let history = viewModel.filteredHistory
        let searchText = viewModel.searchText

        // Then: Properties are accessible
        XCTAssertNotNil(history)
        XCTAssertEqual(searchText, "")
    }

    func testViewModelProviderReturnsCorrectType() async {
        // When: Resolve MainViewModel
        let resolvedViewModel = await ViewModelProvider.resolve()

        // Then: Returns appropriate ViewModel based on OS version
        if #available(macOS 14.0, *) {
            XCTAssertTrue(type(of: resolvedViewModel) == ObservableMainViewModel.self)
        } else {
            XCTAssertTrue(type(of: resolvedViewModel) == MainViewModel.self)
        }
    }
}
