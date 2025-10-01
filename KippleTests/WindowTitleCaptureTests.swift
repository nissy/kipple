//
//  WindowTitleCaptureTests.swift
//  KippleTests
//
//  Tests for window title capture functionality
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class WindowTitleCaptureTests: XCTestCase {
    private var service: ModernClipboardService!
    private var adapter: ModernClipboardServiceAdapter!

    override func setUp() async throws {
        try await super.setUp()

        service = ModernClipboardService.shared
        await service.resetForTesting()
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

    // MARK: - Window Title Capture Tests

    func testWindowTitleCaptureFromCurrentApp() async throws {
        // Given: Copy from the current app (test runner)
        await service.copyToClipboard("Test Content", fromEditor: false)
        await service.flushPendingSaves()

        // When: Get the history
        let history = await service.getHistory()

        // Then: Should have captured app info
        XCTAssertEqual(history.count, 1)
        let item = history[0]

        // At minimum, should have app name
        XCTAssertNotNil(item.sourceApp, "Source app should be captured")

        // Window title might be available for some apps
        // Log the result for debugging
        if let windowTitle = item.windowTitle {
            Logger.shared.log("Captured window title: \(windowTitle)")
        } else {
            Logger.shared.log("Window title was nil (may need accessibility permissions)")
        }

        // Bundle ID should be captured
        XCTAssertNotNil(item.bundleIdentifier, "Bundle identifier should be captured")

        // Process ID should be captured
        XCTAssertNotNil(item.processID, "Process ID should be captured")
        XCTAssertNotEqual(item.processID, 0, "Process ID should be valid")
    }

    func testWindowTitlePersistence() async throws {
        // Given: Item with window title
        let item = ClipItem(
            content: "Content with Window",
            sourceApp: "Safari",
            windowTitle: "GitHub - Kipple Repository", // Simulate captured window title
            bundleIdentifier: "com.apple.Safari",
            processID: 12345
        )

        // When: Add to history using recopyFromHistory to preserve metadata
        await service.recopyFromHistory(item)
        await service.flushPendingSaves()

        // Then: Window title should be preserved
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].windowTitle, "GitHub - Kipple Repository", "Window title should be preserved")
        XCTAssertEqual(history[0].sourceApp, "Safari")
        XCTAssertEqual(history[0].bundleIdentifier, "com.apple.Safari")
    }

    func testMultipleAppsWithWindowTitles() async throws {
        // Given: Items from different apps with window titles
        let items = [
            ClipItem(
                content: "From Terminal",
                sourceApp: "Terminal",
                windowTitle: "bash — 80×24",
                bundleIdentifier: "com.apple.Terminal"
            ),
            ClipItem(
                content: "From Xcode",
                sourceApp: "Xcode",
                windowTitle: "Kipple.xcodeproj",
                bundleIdentifier: "com.apple.dt.Xcode"
            ),
            ClipItem(
                content: "From Safari",
                sourceApp: "Safari",
                windowTitle: "Apple Developer Documentation",
                bundleIdentifier: "com.apple.Safari"
            )
        ]

        // When: Add all items
        for item in items {
            await service.recopyFromHistory(item)
        }
        await service.flushPendingSaves()

        // Then: All window titles should be preserved
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 3)

        // Items are in reverse order (newest first)
        XCTAssertEqual(history[0].windowTitle, "Apple Developer Documentation")
        XCTAssertEqual(history[1].windowTitle, "Kipple.xcodeproj")
        XCTAssertEqual(history[2].windowTitle, "bash — 80×24")
    }

    func testWindowTitleWithSpecialCharacters() async throws {
        // Given: Window title with special characters
        let item = ClipItem(
            content: "Special Content",
            sourceApp: "TextEdit",
            windowTitle: "Document — Edited 🔴 (~/Documents/Test.txt)",
            bundleIdentifier: "com.apple.TextEdit",
            processID: 99999
        )

        // When: Add to history
        await service.recopyFromHistory(item)
        await service.flushPendingSaves()

        // Then: Special characters should be preserved
        let history = await service.getHistory()
        XCTAssertEqual(history[0].windowTitle, "Document — Edited 🔴 (~/Documents/Test.txt)")
    }

    func testNilWindowTitleHandling() async throws {
        // Given: Item without window title
        let item = ClipItem(
            content: "No Window Title",
            sourceApp: "Background App",
            windowTitle: nil,
            bundleIdentifier: "com.example.backgroundapp",
            processID: 55555
        )

        // When: Add to history
        await service.recopyFromHistory(item)
        await service.flushPendingSaves()

        // Then: Should handle nil gracefully
        let history = await service.getHistory()
        XCTAssertEqual(history[0].sourceApp, "Background App")
        XCTAssertNil(history[0].windowTitle, "Nil window title should remain nil")
        XCTAssertEqual(history[0].bundleIdentifier, "com.example.backgroundapp")
    }

    // MARK: - Monitoring Tests

    func testWindowTitleCaptureWhileMonitoring() async throws {
        // Given: Start monitoring
        await service.startMonitoring()

        // When: Copy some content
        await service.copyToClipboard("Monitored Content", fromEditor: false)

        // Wait for monitoring to pick it up
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        await service.flushPendingSaves()

        // Then: Should have captured metadata
        let history = await service.getHistory()
        XCTAssertGreaterThan(history.count, 0)

        let item = history[0]
        XCTAssertNotNil(item.sourceApp, "Should capture source app while monitoring")
        XCTAssertNotNil(item.bundleIdentifier, "Should capture bundle ID while monitoring")

        // Log window title status for debugging
        if item.windowTitle != nil {
            Logger.shared.log("Successfully captured window title while monitoring")
        } else {
            Logger.shared.log("Window title capture needs implementation or permissions")
        }

        await service.stopMonitoring()
    }

    // MARK: - Helper Methods

    /// Test that window title capturing is at least attempted
    func testWindowTitleCaptureAttempt() async throws {
        // This test verifies that the system at least attempts to get window titles
        // Even if it fails due to permissions, the attempt should be made

        // Given: A frontmost application exists
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            XCTFail("No frontmost application available")
            return
        }

        let appName = frontApp.localizedName
        let bundleId = frontApp.bundleIdentifier
        let pid = frontApp.processIdentifier

        XCTAssertNotNil(appName, "App name should be available")
        XCTAssertNotNil(bundleId, "Bundle ID should be available")
        XCTAssertNotEqual(pid, 0, "Process ID should be valid")

        // When: Copy something
        await service.copyToClipboard("Test for Window Title", fromEditor: false)
        await service.flushPendingSaves()

        // Then: Check what was captured
        let history = await service.getHistory()
        let item = history[0]

        // Service uses LastActiveAppTracker to resolve metadata, which may return
        // the last non-Kipple app when Kipple is frontmost. Align expectations with
        // that behavior so the test is environment-agnostic.
        let expectedInfo = LastActiveAppTracker.shared.getSourceAppInfo()

        if let expectedName = expectedInfo.name {
            XCTAssertEqual(item.sourceApp, expectedName, "Source app should match tracker info")
        } else {
            XCTAssertNil(item.sourceApp)
        }

        if let expectedBundle = expectedInfo.bundleId {
            XCTAssertEqual(item.bundleIdentifier, expectedBundle, "Bundle identifier should match tracker info")
        } else {
            XCTAssertNil(item.bundleIdentifier)
        }

        let expectedPid = expectedInfo.pid == 0 ? nil : Optional(expectedInfo.pid)
        XCTAssertEqual(item.processID, expectedPid, "Process ID should match tracker info when available")

        // Window title might be nil if not implemented or no permissions
        // This is where the implementation needs to be added
        if item.windowTitle == nil {
            Logger.shared.log(
                "WARNING: Window title is nil. Implementation needed in getActiveAppInfo()",
                level: .warning
            )
        }
    }
}
