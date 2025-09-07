//
//  LoggerLazyEvaluationTests.swift
//  KippleTests
//
//  Ensures Logger.debug does not build messages when disabled.
//

import XCTest
@testable import Kipple

final class LoggerLazyEvaluationTests: XCTestCase {
    private static var sideEffectCounter = 0

    private func expensiveMessage(_ text: String) -> String {
        // Detect evaluation by incrementing a counter
        LoggerLazyEvaluationTests.sideEffectCounter += 1
        return text
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "enableDebugLogs")
        Logger.shared.refreshConfig() // clear cache
        LoggerLazyEvaluationTests.sideEffectCounter = 0
    }

    func testDebugMessageNotEvaluatedWhenDisabled() {
        // Given: default enableDebugLogs=false
        // When: send a debug log with an expensive message
        Logger.shared.debug(expensiveMessage("SHOULD_NOT_EVALUATE"))
        
        // Then: side effect should not happen
        XCTAssertEqual(Self.sideEffectCounter, 0)
    }

    func testDebugMessageEvaluatedWhenEnabled() {
        // Given
        UserDefaults.standard.set(true, forKey: "enableDebugLogs")
        Logger.shared.refreshConfig() // reload config
        
        // When
        Logger.shared.debug(expensiveMessage("SHOULD_EVALUATE"))
        
        // Then: side effect should occur exactly once
        XCTAssertEqual(Self.sideEffectCounter, 1)
    }
}
