//
//  InternalClearExternalCopyTests.swift
//  KippleTests
//
//  Tests for the bug where first external copy after internal clear is lost
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class InternalClearExternalCopyTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!

    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        adapter = ModernClipboardServiceAdapter.shared

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

        try await super.tearDown()
    }

    // MARK: - Tests for Internal Clear followed by External Copy

    func testExternalCopyAfterInternalClearIsNotLost() async throws {
        // Given: Start monitoring
        await service.startMonitoring()

        // Add some initial content
        await service.copyToClipboard("Initial Content", fromEditor: false)
        await service.flushPendingSaves()

        // When: Clear clipboard internally
        await adapter.clearSystemClipboard()

        // Simulate external copy immediately after clear
        // This would happen when user copies in another app right after clearing
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("External Copy After Clear", forType: .string)

        // Give monitoring time to detect the change
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        await service.flushPendingSaves()

        // Then: External copy should be in history
        let history = await service.getHistory()

        // Should have both initial content and external copy
        XCTAssertGreaterThanOrEqual(history.count, 1, "History should contain at least the external copy")

        // Most recent item should be the external copy
        if !history.isEmpty {
            XCTAssertEqual(history[0].content, "External Copy After Clear",
                          "External copy after clear should be captured in history")
        }
    }

    func testMultipleExternalCopiesAfterInternalClear() async throws {
        // Given: Start monitoring
        await service.startMonitoring()

        // When: Clear clipboard internally
        await adapter.clearSystemClipboard()

        // Simulate multiple external copies
        let externalContents = ["External 1", "External 2", "External 3"]

        for content in externalContents {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)

            // Small delay between copies
            try await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        }

        // Give monitoring time to detect all changes
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        await service.flushPendingSaves()

        // Then: All external copies should be in history
        let history = await service.getHistory()

        XCTAssertGreaterThanOrEqual(history.count, 3, "All external copies should be captured")

        // Verify all contents are present (newest first)
        if history.count >= 3 {
            XCTAssertEqual(history[0].content, "External 3")
            XCTAssertEqual(history[1].content, "External 2")
            XCTAssertEqual(history[2].content, "External 1")
        }
    }

    func testRapidClearAndExternalCopy() async throws {
        // Given: Start monitoring
        await service.startMonitoring()

        // When: Rapidly clear and then external copy
        await adapter.clearSystemClipboard()

        // Immediate external copy (simulating user quickly copying after clear)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Rapid External Copy", forType: .string)

        // Very short wait
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Another clear and copy cycle
        await adapter.clearSystemClipboard()

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Second Rapid Copy", forType: .string)

        // Give monitoring time to process
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        await service.flushPendingSaves()

        // Then: Both external copies should be captured
        let history = await service.getHistory()

        // Should have captured the external copies
        let contents = history.map { $0.content }
        XCTAssertTrue(contents.contains("Rapid External Copy"),
                     "First rapid external copy should be captured")
        XCTAssertTrue(contents.contains("Second Rapid Copy"),
                     "Second rapid external copy should be captured")
    }

    func testInternalClearDoesNotBlockSubsequentExternalCopies() async throws {
        // Given: Start monitoring
        await service.startMonitoring()

        // When: Clear internally
        await adapter.clearSystemClipboard()

        // Wait a moment
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Then do multiple external copies
        let copies = ["Copy 1", "Copy 2", "Copy 3", "Copy 4", "Copy 5"]

        for copy in copies {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(copy, forType: .string)
            try await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        }

        await service.flushPendingSaves()

        // Then: All copies should be in history
        let history = await service.getHistory()
        let contents = history.map { $0.content }

        for copy in copies {
            XCTAssertTrue(contents.contains(copy),
                         "\(copy) should be in history after internal clear")
        }
    }

    func testChangeCountTrackingAfterInternalClear() async throws {
        // This test verifies that changeCount is properly tracked
        // after internal operations

        // Given: Get initial changeCount
        let initialChangeCount = NSPasteboard.general.changeCount

        await service.startMonitoring()

        // When: Clear internally (this increments changeCount)
        await adapter.clearSystemClipboard()

        let afterClearChangeCount = NSPasteboard.general.changeCount
        XCTAssertEqual(afterClearChangeCount, initialChangeCount + 1,
                      "Clear should increment changeCount by 1")

        // Simulate external copy (increments changeCount again)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("After Clear Copy", forType: .string)

        let afterCopyChangeCount = NSPasteboard.general.changeCount
        XCTAssertEqual(afterCopyChangeCount, initialChangeCount + 2,
                      "External copy should increment changeCount again")

        // Give monitoring time to process
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        await service.flushPendingSaves()

        // Then: External copy should be captured despite following internal clear
        let history = await service.getHistory()
        XCTAssertTrue(history.contains { $0.content == "After Clear Copy" },
                     "External copy after internal clear should be in history")
    }
}