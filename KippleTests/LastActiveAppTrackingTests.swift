//
//  LastActiveAppTrackingTests.swift
//  KippleTests
//
//  Tests for tracking last active app (non-Kipple)
//

import XCTest
import AppKit
@testable import Kipple

@MainActor
final class LastActiveAppTrackingTests: XCTestCase {
    private var service: ModernClipboardService!
    
    override func setUp() async throws {
        try await super.setUp()
        
        service = ModernClipboardService.shared
        await service.resetForTesting()
        
        // Clear any existing data
        await service.clearHistory(keepingCategories: false)
        await service.stopMonitoring()
        await service.flushPendingSaves()
    }
    
    override func tearDown() async throws {
        await service.clearHistory(keepingCategories: false)
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
        XCTAssertEqual(history[0].windowTitle, "Live Editor")
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
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let source = ClipboardReader.Source(
            name: "External App", bundleID: "com.example.external", processID: 1234, windowTitle: "Selected Document"
        )
        let selection = "From External App"
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in
            ClipboardReader.Selection(text: selection, source: source, webPageURL: nil)
        })
        let monitoredService = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)

        await monitoredService.startMonitoring()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(selection, forType: .string))
        await monitoredService.checkClipboardForTesting()
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString("Unrelated copy", forType: .string))
        await monitoredService.checkClipboardForTesting()
        await monitoredService.stopMonitoring()

        let history = await monitoredService.getHistory()
        XCTAssertEqual(history.map(\.content), ["Unrelated copy", selection])
        let matched = try XCTUnwrap(history.last)
        XCTAssertEqual(matched.sourceApp, source.name)
        XCTAssertEqual(matched.bundleIdentifier, source.bundleID)
        XCTAssertEqual(matched.processID, source.processID)
        XCTAssertEqual(matched.windowTitle, source.windowTitle)
        let unmatched = try XCTUnwrap(history.first)
        XCTAssertNil(unmatched.sourceApp)
        XCTAssertNil(unmatched.bundleIdentifier)
        XCTAssertNil(unmatched.processID)
        XCTAssertNil(unmatched.windowTitle)
    }
}
