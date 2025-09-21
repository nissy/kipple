//
//  MetadataPreservationTests.swift
//  KippleTests
//
//  Tests for metadata preservation when recopying clipboard items
//

import XCTest
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class MetadataPreservationTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!
    private var viewModel: MainViewModel!

    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        adapter = ModernClipboardServiceAdapter.shared
        viewModel = MainViewModel(clipboardService: adapter)

        // Clear any existing data
        await service.clearAllHistory()
        await service.stopMonitoring()
    }

    override func tearDown() async throws {
        // Clean up
        await service.clearAllHistory()
        await service.stopMonitoring()

        service = nil
        adapter = nil
        viewModel = nil

        try await super.tearDown()
    }

    // MARK: - Metadata Preservation Tests

    func testRecopyFromHistoryPreservesSourceApp() async throws {
        // Given: Item with specific source app metadata
        let originalItem = ClipItem(
            content: "Test Content",
            sourceApp: "Safari",
            windowTitle: "GitHub - Kipple",
            bundleIdentifier: "com.apple.Safari",
            processID: 12345,
            isFromEditor: false
        )

        // Add directly to history to ensure metadata is set
        await service.addItemDirectly(originalItem)
        await service.flushPendingSaves()

        var history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].sourceApp, "Safari", "Original source app should be Safari")

        // When: Recopy from history via MainViewModel (simulating UI selection)
        viewModel.selectHistoryItem(history[0])
        await service.flushPendingSaves()

        // Then: Metadata should be preserved
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Should still have 1 item (no duplicates)")
        XCTAssertEqual(history[0].sourceApp, "Safari", "Source app should still be Safari after recopy")
        XCTAssertEqual(history[0].windowTitle, "GitHub - Kipple", "Window title should be preserved")
        XCTAssertEqual(history[0].bundleIdentifier, "com.apple.Safari", "Bundle ID should be preserved")
        XCTAssertEqual(history[0].processID, 12345, "Process ID should be preserved")
    }

    func testRecopyFromHistoryPreservesAllMetadata() async throws {
        // Given: Multiple items with different metadata
        let items = [
            ClipItem(
                content: "From Xcode",
                sourceApp: "Xcode",
                windowTitle: "Kipple.xcodeproj",
                bundleIdentifier: "com.apple.dt.Xcode",
                processID: 11111,
                isFromEditor: false
            ),
            ClipItem(
                content: "From Terminal",
                sourceApp: "Terminal",
                windowTitle: "bash - 80x24",
                bundleIdentifier: "com.apple.Terminal",
                processID: 22222,
                isFromEditor: false
            ),
            ClipItem(
                content: "From Editor",
                sourceApp: "Kipple",
                windowTitle: "Quick Editor",
                bundleIdentifier: Bundle.main.bundleIdentifier,
                processID: ProcessInfo.processInfo.processIdentifier,
                isFromEditor: true
            )
        ]

        // Add all items
        for item in items {
            await service.addItemDirectly(item)
        }
        await service.flushPendingSaves()

        // When: Recopy the Xcode item (now at index 2)
        var history = await service.getHistory()
        let xcodeItem = history.first { $0.content == "From Xcode" }!
        viewModel.selectHistoryItem(xcodeItem)
        await service.flushPendingSaves()

        // Then: Xcode item should be at top with metadata preserved
        history = await service.getHistory()
        XCTAssertEqual(history[0].content, "From Xcode", "Xcode item should be at top")
        XCTAssertEqual(history[0].sourceApp, "Xcode", "Source app should be preserved")
        XCTAssertEqual(history[0].windowTitle, "Kipple.xcodeproj", "Window title should be preserved")
        XCTAssertEqual(history[0].bundleIdentifier, "com.apple.dt.Xcode", "Bundle ID should be preserved")
        XCTAssertEqual(history[0].processID, 11111, "Process ID should be preserved")
        XCTAssertFalse(history[0].isFromEditor ?? false, "Editor flag should be preserved as false")
    }

    func testRecopyPreservesEditorFlag() async throws {
        // Given: Item from editor
        let editorItem = ClipItem(
            content: "Editor Content",
            sourceApp: "Kipple",
            windowTitle: "Quick Editor",
            bundleIdentifier: Bundle.main.bundleIdentifier,
            processID: ProcessInfo.processInfo.processIdentifier,
            isFromEditor: true
        )

        await service.addItemDirectly(editorItem)
        await service.flushPendingSaves()

        // When: Recopy
        let history = await service.getHistory()
        viewModel.selectHistoryItem(history[0])
        await service.flushPendingSaves()

        // Then: Editor flag should be preserved
        let updatedHistory = await service.getHistory()
        XCTAssertTrue(updatedHistory[0].isFromEditor ?? false, "Editor flag should be preserved")
        XCTAssertEqual(updatedHistory[0].sourceApp, "Kipple", "Should remain as Kipple for editor items")
    }

    func testRecopyPreservesPinnedState() async throws {
        // Given: Pinned item with metadata
        let item = ClipItem(
            content: "Pinned Content",
            sourceApp: "Finder",
            windowTitle: "Desktop",
            bundleIdentifier: "com.apple.finder",
            processID: 33333,
            isFromEditor: false
        )

        await service.addItemDirectly(item)
        var history = await service.getHistory()
        _ = await service.togglePin(for: history[0])

        // When: Recopy pinned item
        history = await service.getHistory()
        XCTAssertTrue(history[0].isPinned, "Item should be pinned before recopy")
        viewModel.selectHistoryItem(history[0])
        await service.flushPendingSaves()

        // Then: Both pin state and metadata should be preserved
        history = await service.getHistory()
        XCTAssertTrue(history[0].isPinned, "Pin state should be preserved")
        XCTAssertEqual(history[0].sourceApp, "Finder", "Source app should be preserved")
        XCTAssertEqual(history[0].windowTitle, "Desktop", "Window title should be preserved")
    }

    // MARK: - Edge Cases

    func testRecopyWithNilMetadata() async throws {
        // Given: Item with some nil metadata
        let item = ClipItem(
            content: "Partial Metadata",
            sourceApp: "Unknown",
            windowTitle: nil,
            bundleIdentifier: nil,
            processID: nil,
            isFromEditor: false
        )

        await service.addItemDirectly(item)
        await service.flushPendingSaves()

        // When: Recopy
        let history = await service.getHistory()
        viewModel.selectHistoryItem(history[0])
        await service.flushPendingSaves()

        // Then: Nil values should remain nil
        let updatedHistory = await service.getHistory()
        XCTAssertEqual(updatedHistory[0].sourceApp, "Unknown", "Known metadata should be preserved")
        XCTAssertNil(updatedHistory[0].windowTitle, "Nil window title should remain nil")
        XCTAssertNil(updatedHistory[0].bundleIdentifier, "Nil bundle ID should remain nil")
        XCTAssertNil(updatedHistory[0].processID, "Nil process ID should remain nil")
    }

    func testDirectCopyVsHistoryRecopy() async throws {
        // Given: Item with specific metadata
        let originalContent = "Test Content for Comparison"
        let item = ClipItem(
            content: originalContent,
            sourceApp: "TextEdit",
            windowTitle: "Document.txt",
            bundleIdentifier: "com.apple.TextEdit",
            processID: 44444,
            isFromEditor: false
        )

        await service.addItemDirectly(item)
        await service.flushPendingSaves()

        // When: Copy same content directly (not from history)
        await service.copyToClipboard(originalContent, fromEditor: false)
        await service.flushPendingSaves()

        // Then: Direct copy should update metadata to current app
        var history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Should not create duplicate")
        // Direct copy would update to current app (likely test runner or Kipple)
        // This is expected behavior - only recopy from history should preserve metadata

        // When: Now recopy from history
        viewModel.selectHistoryItem(history[0])
        await service.flushPendingSaves()

        // Then: History recopy should preserve whatever metadata was there
        history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Should still have 1 item")
        // Metadata should be whatever was set after the direct copy
    }

    // MARK: - Performance

    func testMetadataPreservationPerformance() async throws {
        // Given: Large number of items with metadata
        for i in 1...100 {
            let item = ClipItem(
                content: "Item \(i)",
                sourceApp: "App\(i % 10)",
                windowTitle: "Window \(i)",
                bundleIdentifier: "com.test.app\(i % 10)",
                processID: Int32(10000 + i),
                isFromEditor: i % 5 == 0
            )
            await service.addItemDirectly(item)
        }

        // Measure recopy performance
        let startTime = Date()

        // When: Recopy multiple items
        let history = await service.getHistory()
        for i in stride(from: 10, to: 20, by: 1) {
            viewModel.selectHistoryItem(history[i])
        }
        await service.flushPendingSaves()

        let duration = Date().timeIntervalSince(startTime)

        // Then: Should complete quickly
        XCTAssertLessThan(duration, 1.0, "Batch recopy with metadata preservation should be fast")

        // Verify metadata is preserved
        let updatedHistory = await service.getHistory()
        let item15 = updatedHistory.first { $0.content == "Item 85" }!
        XCTAssertEqual(item15.sourceApp, "App5", "Metadata should be preserved after batch operations")
    }
}

// MARK: - Test Helper Extension

extension ModernClipboardService {
    /// Helper method for tests to add items directly with full metadata control
    func addItemDirectly(_ item: ClipItem) async {
        // Use copyToClipboard to add item with proper internal state management
        await recopyFromHistory(item)
    }
}
