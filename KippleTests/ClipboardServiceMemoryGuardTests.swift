//
//  ClipboardServiceMemoryGuardTests.swift
//  KippleTests
//
//  Verifies size limits for history insertion.
//

import XCTest
@testable import Kipple

final class ClipboardServiceMemoryGuardTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Ensure clean slate
        UserDefaults.standard.removeObject(forKey: "maxClipboardBytes")
        // Shared service in tests does minimal init (no timers)
        ClipboardService.shared.history = []
    }

    func testLargeContentIsRejectedByConfiguredLimit() {
        // Given: limit 1KB
        UserDefaults.standard.set(1024, forKey: "maxClipboardBytes")
        let content = String(repeating: "A", count: 2048) // 2KB ASCII
        let initialCount = ClipboardService.shared.history.count
        
        // When
        let appInfo = ClipboardService.AppInfo(appName: "TestApp", windowTitle: nil, bundleId: "com.example", pid: 0)
        ClipboardService.shared.addToHistoryWithAppInfo(content, appInfo: appInfo, isFromEditor: false)
        
        // Then: async work settles; verify unchanged
        let exp = expectation(description: "wait for history update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(ClipboardService.shared.history.count, initialCount)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }

    func testSmallContentIsAccepted() {
        // Given: limit 4KB
        UserDefaults.standard.set(4096, forKey: "maxClipboardBytes")
        let content = String(repeating: "B", count: 1024) // 1KB ASCII
        ClipboardService.shared.history = []
        
        // When
        let appInfo = ClipboardService.AppInfo(appName: "TestApp", windowTitle: nil, bundleId: "com.example", pid: 0)
        ClipboardService.shared.addToHistoryWithAppInfo(content, appInfo: appInfo, isFromEditor: false)
        
        // Then
        let exp = expectation(description: "wait for history insert")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(ClipboardService.shared.history.first?.content, content)
            exp.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }
}

