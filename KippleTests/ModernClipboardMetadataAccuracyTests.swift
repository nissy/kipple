import XCTest
import AppKit
@testable import Kipple

/// Tests for metadata accuracy, especially after editor copies

@MainActor
final class ModernClipboardMetadataAccuracyTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!

    override func setUp() async throws {
        try await super.setUp()
        service = ModernClipboardService.shared
        await service.resetForTesting()
        adapter = ModernClipboardServiceAdapter.shared

        // Clear history completely before each test
        await service.clearHistory(keepPinned: false)
        await service.flushPendingSaves()

        // Wait a bit for everything to settle
        try? await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        await service.stopMonitoring()
        await service.clearHistory(keepPinned: false)
        await service.flushPendingSaves()
        try await super.tearDown()
    }

    // MARK: - Core Metadata Tests

    /// Test that external copy after editor copy has correct metadata
    func testExternalCopyAfterEditorCopy() async throws {
        // Given: Start monitoring
        await service.startMonitoring()

        // Copy from editor
        let editorContent = "Content from Kipple editor"
        await service.copyToClipboard(editorContent, fromEditor: true)

        // Verify editor metadata
        var history = await service.getHistory()
        guard let editorItem = history.first else {
            XCTFail("No item in history after editor copy")
            return
        }
        XCTAssertEqual(editorItem.sourceApp, "Kipple", "Editor copy should have Kipple as source")
        XCTAssertEqual(editorItem.windowTitle, "Quick Editor", "Editor copy should have Quick Editor as window")
        XCTAssertTrue(editorItem.isFromEditor ?? false, "Should be marked as from editor")

        // When: Simulate external copy (this would normally come from another app)
        // We'll simulate by directly triggering checkClipboard after setting up external content
        let externalContent = "Content from external app"

        // Clear the internal copy flag to simulate external copy
        await service.copyToClipboard(externalContent, fromEditor: false)

        // Wait for monitoring to pick it up
        try? await Task.sleep(for: .milliseconds(200))

        // Then: The external copy should NOT have editor metadata
        history = await service.getHistory()
        let externalItem = history.first { $0.content == externalContent }
        XCTAssertNotNil(externalItem, "External content should be in history")

        if let externalItem = externalItem {
            XCTAssertNotEqual(externalItem.sourceApp, "Kipple",
                             "External copy should not have Kipple as source")
            XCTAssertNotEqual(externalItem.windowTitle, "Quick Editor",
                             "External copy should not have Quick Editor as window")
            XCTAssertFalse(externalItem.isFromEditor ?? true,
                          "External copy should not be marked as from editor")
        }
    }

    /// Test rapid editor and external copies
    func testRapidEditorAndExternalCopies() async throws {
        await service.startMonitoring()

        // Perform rapid alternating copies
        let testData = [
            (content: "Editor 1", fromEditor: true),
            (content: "External 1", fromEditor: false),
            (content: "Editor 2", fromEditor: true),
            (content: "External 2", fromEditor: false),
            (content: "Editor 3", fromEditor: true),
            (content: "External 3", fromEditor: false)
        ]

        for data in testData {
            await service.copyToClipboard(data.content, fromEditor: data.fromEditor)
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Verify each item has correct metadata
        let history = await service.getHistory()

        for data in testData {
            if let item = history.first(where: { $0.content == data.content }) {
                if data.fromEditor {
                    XCTAssertEqual(item.sourceApp, "Kipple",
                                  "\(data.content) should have Kipple as source")
                    XCTAssertTrue(item.isFromEditor ?? false,
                                 "\(data.content) should be marked as from editor")
                } else {
                    XCTAssertNotEqual(item.sourceApp, "Kipple",
                                     "\(data.content) should not have Kipple as source")
                    XCTAssertFalse(item.isFromEditor ?? true,
                                  "\(data.content) should not be marked as from editor")
                }
            } else {
                XCTFail("Item \(data.content) not found in history")
            }
        }
    }

    /// Test that multiple editor copies in a row work correctly
    func testMultipleEditorCopiesInRow() async throws {
        await service.startMonitoring()

        // Multiple editor copies
        let editorContents = ["Editor A", "Editor B", "Editor C"]
        for content in editorContents {
            await service.copyToClipboard(content, fromEditor: true)
            try? await Task.sleep(for: .milliseconds(100))
        }

        // Then external copy
        let externalContent = "External after multiple editor"
        await service.copyToClipboard(externalContent, fromEditor: false)
        try? await Task.sleep(for: .milliseconds(100))

        // Verify all editor copies have correct metadata
        let history = await service.getHistory()
        for content in editorContents {
            if let item = history.first(where: { $0.content == content }) {
                XCTAssertEqual(item.sourceApp, "Kipple",
                              "\(content) should have Kipple as source")
                XCTAssertTrue(item.isFromEditor ?? false,
                             "\(content) should be from editor")
            }
        }

        // Verify external copy doesn't have editor metadata
        if let externalItem = history.first(where: { $0.content == externalContent }) {
            XCTAssertNotEqual(externalItem.sourceApp, "Kipple",
                             "External copy should not have Kipple as source")
            XCTAssertFalse(externalItem.isFromEditor ?? true,
                          "External copy should not be from editor")
        }
    }

    // MARK: - Category Tests

    /// Test that source app metadata is correctly determined
    func testSourceAppMetadataAfterEditorCopy() async throws {
        await service.startMonitoring()

        // Copy from editor
        await service.copyToClipboard("Kipple content", fromEditor: true)

        // Copy from external (should not have Kipple as source)
        await service.copyToClipboard("External content", fromEditor: false)

        try? await Task.sleep(for: .milliseconds(200))

        let history = await service.getHistory()

        // Check Kipple item source app
        if let kippleItem = history.first(where: { $0.content == "Kipple content" }) {
            XCTAssertEqual(kippleItem.sourceApp, "Kipple",
                          "Editor content should have Kipple as source app")
            XCTAssertTrue(kippleItem.isFromEditor ?? false,
                         "Editor content should be marked as from editor")
        }

        // Check external item source app
        if let externalItem = history.first(where: { $0.content == "External content" }) {
            XCTAssertNotEqual(externalItem.sourceApp, "Kipple",
                             "External content should not have Kipple as source app")
            XCTAssertFalse(externalItem.isFromEditor ?? true,
                          "External content should not be marked as from editor")
        }
    }

    // MARK: - Monitoring State Tests

    /// Test that stopping and restarting monitoring preserves correct metadata
    func testMonitoringRestartPreservesMetadata() async throws {
        // Start monitoring and copy from editor
        await service.startMonitoring()
        await service.copyToClipboard("Before restart", fromEditor: true)

        // Stop monitoring
        await service.stopMonitoring()
        try? await Task.sleep(for: .milliseconds(100))

        // Restart monitoring
        await service.startMonitoring()

        // Copy from external
        await service.copyToClipboard("After restart", fromEditor: false)
        try? await Task.sleep(for: .milliseconds(200))

        // Verify metadata
        let history = await service.getHistory()

        if let beforeItem = history.first(where: { $0.content == "Before restart" }) {
            XCTAssertTrue(beforeItem.isFromEditor ?? false,
                         "Item before restart should maintain editor flag")
        }

        if let afterItem = history.first(where: { $0.content == "After restart" }) {
            XCTAssertFalse(afterItem.isFromEditor ?? true,
                          "Item after restart should not have editor flag")
        }
    }

    // MARK: - Edge Cases

    /// Test empty content metadata handling
    func testEmptyContentMetadata() async throws {
        await service.startMonitoring()

        // Empty content from editor
        await service.copyToClipboard("", fromEditor: true)
        try? await Task.sleep(for: .milliseconds(100))

        // Empty content from external
        await service.copyToClipboard(" ", fromEditor: false)  // Space to differentiate
        try? await Task.sleep(for: .milliseconds(100))

        let history = await service.getHistory()

        if let editorEmpty = history.first(where: { $0.content.isEmpty }) {
            XCTAssertTrue(editorEmpty.isFromEditor ?? false,
                         "Empty editor content should have editor flag")
        }

        if let externalEmpty = history.first(where: { $0.content == " " }) {
            XCTAssertFalse(externalEmpty.isFromEditor ?? true,
                          "External content should not have editor flag")
        }
    }

    /// Test very rapid successive copies
    func testVeryRapidSuccessiveCopies() async throws {
        await service.startMonitoring()

        // Rapid fire copies with no delay
        for i in 1...10 {
            let fromEditor = (i % 2 == 0)
            await service.copyToClipboard("Rapid \(i)", fromEditor: fromEditor)
        }

        // Wait for all to process
        try? await Task.sleep(for: .milliseconds(500))

        // Verify metadata integrity
        let history = await service.getHistory()

        for i in 1...10 {
            if let item = history.first(where: { $0.content == "Rapid \(i)" }) {
                let shouldBeFromEditor = (i % 2 == 0)
                XCTAssertEqual(item.isFromEditor ?? false, shouldBeFromEditor,
                              "Rapid \(i) should have correct editor flag")
            }
        }
    }

    /// Test metadata after clear operations
    func testMetadataAfterClearOperations() async throws {
        await service.startMonitoring()

        // Add editor content
        await service.copyToClipboard("Before clear", fromEditor: true)

        // Clear history
        await service.clearHistory(keepPinned: false)

        // Add external content
        await service.copyToClipboard("After clear", fromEditor: false)
        try? await Task.sleep(for: .milliseconds(200))

        // Verify new content has correct metadata
        let history = await service.getHistory()

        if let afterClear = history.first(where: { $0.content == "After clear" }) {
            XCTAssertFalse(afterClear.isFromEditor ?? true,
                          "Content after clear should not have stale editor flag")
            XCTAssertNotEqual(afterClear.sourceApp, "Kipple",
                             "Content after clear should not have Kipple as source")
        }
    }
}
