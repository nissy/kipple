//
//  ClipboardMonitoringDuplicateTests.swift
//  KippleTests
//
//  Tests for clipboard monitoring duplicate handling
//

import XCTest
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class ClipboardMonitoringDuplicateTests: XCTestCase {
    private var service: ModernClipboardService!

    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        await service.resetForTesting()

        // Clear any existing data
        await service.clearAllHistory()
        await service.stopMonitoring()
    }

    override func tearDown() async throws {
        // Clean up
        await service.clearAllHistory()
        await service.stopMonitoring()

        service = nil

        try await super.tearDown()
    }

    // MARK: - Duplicate Handling Tests

    func testMonitoringSameContentMultipleTimes() async throws {
        // Given: Monitoring is active
        await service.startMonitoring()

        // When: Copy the same content multiple times
        await service.copyToClipboard("Test Content", fromEditor: false)
        await service.flushPendingSaves()

        var history = await service.getHistory()
        let firstCopyTime = history[0].timestamp
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].content, "Test Content")

        // Wait a bit
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Copy different content
        await service.copyToClipboard("Other Content", fromEditor: false)
        await service.flushPendingSaves()

        history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].content, "Other Content")

        // Wait a bit more
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Copy the first content again - should move to top
        await service.copyToClipboard("Test Content", fromEditor: false)
        await service.flushPendingSaves()

        // Then: First content should move to top with updated timestamp
        history = await service.getHistory()
        XCTAssertEqual(history.count, 2, "Should not create duplicate")
        XCTAssertEqual(history[0].content, "Test Content", "Should move to top")
        XCTAssertNotEqual(history[0].timestamp, firstCopyTime, "Should have new timestamp")
        XCTAssertEqual(history[1].content, "Other Content")
    }

    func testExternalCopySameContent() async throws {
        // Given: Some content in history
        await service.copyToClipboard("External Test", fromEditor: false)
        await service.copyToClipboard("Another Item", fromEditor: false)
        await service.flushPendingSaves()

        // Start monitoring
        await service.startMonitoring()

        // When: External app copies the same content (simulated by not marking as internal)
        let state = ClipboardState()
        await state.setInternalCopy(false) // Simulate external copy

        // Manually trigger clipboard check with same content
        await simulateExternalCopy("External Test")

        // Then: Content should move to top
        let history = await service.getHistory()
        XCTAssertEqual(history[0].content, "External Test", "External recopy should move to top")
        XCTAssertEqual(history.count, 2, "Should not create duplicate")
    }

    func testRapidDuplicateCopies() async throws {
        // Given: Monitoring active
        await service.startMonitoring()

        // When: Rapidly copy same content
        for i in 1...5 {
            await service.copyToClipboard("Rapid Copy", fromEditor: false)
            if i < 5 {
                try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            }
        }
        await service.flushPendingSaves()

        // Then: Should only have one entry
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1, "Rapid duplicates should not create multiple entries")
        XCTAssertEqual(history[0].content, "Rapid Copy")
    }

    func testAlternatingContentPattern() async throws {
        // Given: Monitoring active
        await service.startMonitoring()

        // When: Alternate between two pieces of content
        for i in 1...6 {
            let content = i % 2 == 0 ? "Content A" : "Content B"
            await service.copyToClipboard(content, fromEditor: false)
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
        }
        await service.flushPendingSaves()

        // Then: Should have only 2 items, with last copied at top
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 2, "Should only have 2 unique items")
        XCTAssertEqual(history[0].content, "Content A", "Last copied should be at top")
        XCTAssertEqual(history[1].content, "Content B")
    }

    func testLongContentDuplication() async throws {
        // Given: Very long content
        let longContent = String(repeating: "A", count: 10000)

        await service.startMonitoring()

        // When: Copy long content multiple times
        await service.copyToClipboard(longContent, fromEditor: false)
        await service.copyToClipboard("Short", fromEditor: false)
        await service.copyToClipboard(longContent, fromEditor: false)
        await service.flushPendingSaves()

        // Then: Long content should move to top without duplication
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].content, longContent)
        XCTAssertEqual(history[1].content, "Short")
    }

    // MARK: - Helper Methods

    private func simulateExternalCopy(_ content: String) async {
        // This simulates what would happen when external app copies to clipboard
        // The service should detect this through monitoring and update history

        // We can't directly simulate NSPasteboard changes in tests,
        // so we'll call the internal method that would be triggered

        // For now, just copy through service without internal flag
        // In real scenario, this would come from pasteboard monitoring
        await service.copyToClipboard(content, fromEditor: false)
    }
}
