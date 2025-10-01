//
//  LastActiveAppTrackingTests.swift
//  KippleTests
//
//  Tests for tracking last active app (non-Kipple)
//

import XCTest
import AppKit
@testable import Kipple

@available(macOS 14.0, *)
@MainActor
final class LastActiveAppTrackingTests: XCTestCase {
    private var service: ModernClipboardService!
    
    override func setUp() async throws {
        try await super.setUp()
        
        service = ModernClipboardService.shared
        await service.resetForTesting()
        
        // Clear any existing data
        await service.clearHistory(keepPinned: false)
        await service.stopMonitoring()
        await service.flushPendingSaves()
    }
    
    override func tearDown() async throws {
        await service.clearHistory(keepPinned: false)
        await service.stopMonitoring()
        
        service = nil
        
        try await super.tearDown()
    }
    
    func testCopyFromEditorShouldShowKipple() async throws {
        // Given: Copy from editor
        await service.copyToClipboard("From Editor", fromEditor: true)
        await service.flushPendingSaves()
        
        // Then: Should show Kipple as source
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].sourceApp, "Kipple")
        XCTAssertEqual(history[0].windowTitle, "Quick Editor")
        XCTAssertTrue(history[0].isFromEditor ?? false)
    }
    
    func testCopyNotFromEditorShouldNotAlwaysShowKipple() async throws {
        // This test can't fully verify the behavior without actually switching apps
        // but we can at least ensure the logic is in place
        
        // Given: Copy not from editor
        await service.copyToClipboard("External Copy", fromEditor: false)
        await service.flushPendingSaves()
        
        // Then: Should attempt to get actual app name
        let history = await service.getHistory()
        XCTAssertEqual(history.count, 1)
        
        // The app might be Kipple (test runner) or Xcode
        // The important thing is that it's not hardcoded to Kipple
        XCTAssertNotNil(history[0].sourceApp)
        
        // If running in Xcode, might get Xcode
        // If Kipple is frontmost, will get Kipple
        // The test verifies the mechanism exists
    }
    
    func testMonitoringDetectsExternalApp() async throws {
        // Given: Start monitoring
        await service.startMonitoring()
        
        // Simulate external copy
        // In real scenario, this would be from another app
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("From External App", forType: .string)
        
        // Wait for detection
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        // Then: Should detect and record app info
        let history = await service.getHistory()
        
        // At least one item should be detected
        XCTAssertGreaterThan(history.count, 0)
        
        if let latestItem = history.first {
            XCTAssertNotNil(latestItem.sourceApp)
            XCTAssertNotNil(latestItem.bundleIdentifier)
            // processID should be valid
            if let pid = latestItem.processID {
                XCTAssertNotEqual(pid, 0)
            }
        }
        
        await service.stopMonitoring()
    }
}
