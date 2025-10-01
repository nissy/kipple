//
//  AppInfoRecordingTests.swift
//  KippleTests
//
//  Tests for correct app info recording when switching between apps
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class AppInfoRecordingTests: XCTestCase {
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

    // MARK: - Tests for App Info Recording

    func testAppInfoRecordedCorrectly() async throws {
        // This test verifies that app info is correctly recorded
        // Unfortunately, we can't easily simulate app switching in tests
        // But we can verify the basic mechanism works

        // Given: Copy from Kipple's editor
        await service.copyToClipboard("From Editor", fromEditor: true)
        await service.flushPendingSaves()

        // Then: Should record as from Kipple
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].sourceApp, "Kipple")
        XCTAssertEqual(history[0].windowTitle, "Quick Editor")
        XCTAssertTrue(history[0].isFromEditor ?? false)
    }

    func testNonEditorCopyRecordsCurrentApp() async throws {
        // Given: Copy not from editor (simulating external copy)
        await service.copyToClipboard("Not from Editor", fromEditor: false)
        await service.flushPendingSaves()

        // Then: Should record current app info (test runner in this case)
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)

        // Should have recorded some app name (not Kipple unless we're actually frontmost)
        XCTAssertNotNil(history[0].sourceApp)
        XCTAssertFalse(history[0].isFromEditor ?? true)

        // Should have bundle ID and process ID
        XCTAssertNotNil(history[0].bundleIdentifier)
        XCTAssertNotNil(history[0].processID)
        XCTAssertNotEqual(history[0].processID, 0)
    }

    func testRecopyPreservesOriginalAppInfo() async throws {
        // Given: Create an item with specific app info
        let originalItem = ClipItem(
            content: "Original Content",
            sourceApp: "Safari",
            windowTitle: "GitHub - Kipple",
            bundleIdentifier: "com.apple.Safari",
            processID: 12345
        )

        // When: Recopy from history
        await service.recopyFromHistory(originalItem)
        await service.flushPendingSaves()

        // Then: App info should be preserved
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].sourceApp, "Safari")
        XCTAssertEqual(history[0].windowTitle, "GitHub - Kipple")
        XCTAssertEqual(history[0].bundleIdentifier, "com.apple.Safari")
        XCTAssertEqual(history[0].processID, 12345)
    }

    func testMonitoringCapturesAppInfo() async throws {
        // Given: Start monitoring
        await service.startMonitoring()

        // When: Add content to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Monitored Content", forType: .string)

        // Wait for monitoring to detect
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        await service.flushPendingSaves()

        // Then: Should have captured app info
        let history = await service.getHistory()
        XCTAssertGreaterThan(history.count, 0)

        if !history.isEmpty {
            let item = history[0]
            XCTAssertNotNil(item.sourceApp, "Source app should be captured")
            XCTAssertNotNil(item.bundleIdentifier, "Bundle ID should be captured")
            XCTAssertNotNil(item.processID, "Process ID should be captured")

            // Log what was captured for debugging
            Logger.shared.log("Captured app: \(item.sourceApp ?? "nil")")
            Logger.shared.log("Bundle ID: \(item.bundleIdentifier ?? "nil")")
            Logger.shared.log("Window title: \(item.windowTitle ?? "nil")")
        }

        await service.stopMonitoring()
    }

    func testLastActiveAppTracking() async throws {
        // This test checks if we're tracking the last active non-Kipple app
        // Currently this feature is not implemented, so this test documents the issue

        // Given: Get current frontmost app
        guard let currentApp = NSWorkspace.shared.frontmostApplication else {
            XCTFail("No frontmost application")
            return
        }

        let currentAppName = currentApp.localizedName
        Logger.shared.log("Current frontmost app: \(currentAppName ?? "Unknown")")

        // When: Copy something
        await service.copyToClipboard("Test Content", fromEditor: false)
        await service.flushPendingSaves()

        // Then: Check what was recorded
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)

        let recordedApp = history[0].sourceApp
        Logger.shared.log("Recorded app: \(recordedApp ?? "nil")")

        // If Kipple is frontmost during the test, it will be recorded as Kipple
        // This is the bug we're trying to fix - we need to track the last non-Kipple app
        if currentAppName == "Kipple" {
            Logger.shared.log(
                "WARNING: Kipple is frontmost - cannot properly test last active app tracking",
                level: .warning
            )

            // This is where the bug manifests - when user switches to Kipple via hotkey
            // immediately after copying, we incorrectly record Kipple as the source
            XCTAssertEqual(recordedApp, "Kipple",
                          "Bug reproduced: Recording Kipple when it's frontmost after copy")
        }
    }

    func testAppSwitchDuringCopy() async throws {
        // This test simulates the problematic scenario where:
        // 1. User copies in Safari
        // 2. Immediately switches to Kipple via hotkey
        // 3. Kipple's polling detects the copy while Kipple is frontmost

        // Given: Start monitoring
        await service.startMonitoring()

        // Simulate: External copy from another app
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Copied from Safari", forType: .string)

        // In real scenario, user would now press hotkey to show Kipple
        // By the time polling runs, Kipple would be frontmost
        // This causes the bug where we record "Kipple" instead of "Safari"

        // Wait for monitoring to pick it up
        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        await service.flushPendingSaves()

        // Then: Check what was recorded
        let history = await service.getHistory()
        XCTAssertGreaterThan(history.count, 0)

        if !history.isEmpty {
            let item = history[0]
            Logger.shared.log("Content: \(item.content)")
            Logger.shared.log("Recorded as from: \(item.sourceApp ?? "nil")")

            // This will likely show the bug - it will record the current app
            // instead of the app where the copy actually originated
            if item.sourceApp == "Kipple" {
                Logger.shared.log(
                    "BUG: Copy recorded as from Kipple when it was from external app",
                    level: .error
                )
            }
        }

        await service.stopMonitoring()
    }
}
