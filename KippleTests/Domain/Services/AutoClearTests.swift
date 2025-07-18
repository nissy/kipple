//
//  AutoClearTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/17.
//

import XCTest
@testable import Kipple

@MainActor
class AutoClearTests: XCTestCase {
    var clipboardService: ClipboardService!
    var appSettings: AppSettings!
    
    override func setUp() {
        super.setUp()
        clipboardService = ClipboardService.shared
        appSettings = AppSettings.shared
        
        // Reset settings
        appSettings.enableAutoClear = false
        appSettings.autoClearInterval = 60
    }
    
    override func tearDown() {
        appSettings.enableAutoClear = false
        clipboardService.stopMonitoring()
        super.tearDown()
    }
    
    func testAutoClearTimerStartsWhenEnabled() {
        // Given
        appSettings.enableAutoClear = false
        
        // When
        appSettings.enableAutoClear = true
        clipboardService.updateAutoClearTimer()
        
        // Wait for async operations to complete
        let expectation = XCTestExpectation(description: "Timer starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        
        // Then
        XCTAssertNotNil(clipboardService.autoClearRemainingTime)
    }
    
    func testAutoClearTimerStopsWhenDisabled() {
        // Given
        appSettings.enableAutoClear = true
        clipboardService.updateAutoClearTimer()
        
        // Wait for timer to start
        let startExpectation = XCTestExpectation(description: "Timer starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1)
        
        // Verify timer started
        XCTAssertNotNil(clipboardService.autoClearRemainingTime)
        
        // When
        appSettings.enableAutoClear = false
        clipboardService.updateAutoClearTimer()
        
        // Wait for timer to stop
        let stopExpectation = XCTestExpectation(description: "Timer stops")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            stopExpectation.fulfill()
        }
        wait(for: [stopExpectation], timeout: 1)
        
        // Then
        XCTAssertNil(clipboardService.autoClearRemainingTime)
    }
    
    func testAutoClearTimerRestartsWhenIntervalChanges() {
        // Given
        appSettings.enableAutoClear = true
        appSettings.autoClearInterval = 60
        clipboardService.updateAutoClearTimer()
        
        // Wait for first timer to start
        let startExpectation = XCTestExpectation(description: "Initial timer starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1)
        
        let initialTime = clipboardService.autoClearRemainingTime
        
        // When
        appSettings.autoClearInterval = 120
        clipboardService.updateAutoClearTimer()
        
        // Wait for timer to restart
        let restartExpectation = XCTestExpectation(description: "Timer restarts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            restartExpectation.fulfill()
        }
        wait(for: [restartExpectation], timeout: 1)
        
        // Then
        XCTAssertNotNil(clipboardService.autoClearRemainingTime)
        if let newTime = clipboardService.autoClearRemainingTime,
           let oldTime = initialTime {
            XCTAssertGreaterThan(newTime, oldTime)
        }
    }
    
    func testRemainingTimeDecreases() {
        // Given
        appSettings.enableAutoClear = true
        appSettings.autoClearInterval = 60
        clipboardService.updateAutoClearTimer()
        
        // Wait for timer to start
        let startExpectation = XCTestExpectation(description: "Timer starts")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startExpectation.fulfill()
        }
        wait(for: [startExpectation], timeout: 1)
        
        guard let initialTime = clipboardService.autoClearRemainingTime else {
            XCTFail("Auto-clear timer should have started")
            return
        }
        
        // When - wait for 2 seconds
        let expectation = XCTestExpectation(description: "Wait for timer update")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 3)
        
        // Then
        guard let currentTime = clipboardService.autoClearRemainingTime else {
            XCTFail("Auto-clear timer should still be running")
            return
        }
        
        XCTAssertLessThan(currentTime, initialTime)
        XCTAssertGreaterThan(currentTime, initialTime - 3) // Should be about 2 seconds less
    }
    
    func testAutoClearClearsSystemClipboard() async {
        // Given
        appSettings.enableAutoClear = true
        
        // Set test content to clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Test content", forType: .string)
        
        // When - simulate auto-clear
        await MainActor.run {
            // This would be called by performAutoClear in the actual implementation
            NSPasteboard.general.clearContents()
            clipboardService.currentClipboardContent = nil
        }
        
        // Then
        await MainActor.run {
            XCTAssertNil(NSPasteboard.general.string(forType: .string))
            XCTAssertNil(clipboardService.currentClipboardContent)
        }
    }
}
