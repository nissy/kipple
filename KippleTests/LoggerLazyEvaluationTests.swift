//
//  LoggerLazyEvaluationTests.swift
//  KippleTests
//
//  Ensures Logger.debug does not build messages when disabled.
//

import XCTest
@testable import Kipple

final class LoggerLazyEvaluationTests: XCTestCase {
    private static let counter = SideEffectCounter()

    private final class SideEffectCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.lock()
            defer { lock.unlock() }
            value += 1
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            value = 0
        }

        func getValue() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private func expensiveMessage(_ text: String) -> String {
        // Detect evaluation by incrementing a counter
        LoggerLazyEvaluationTests.counter.increment()
        return text
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "enableDebugLogs")
        Task { @MainActor in
            Logger.shared.refreshConfig() // clear cache
        }
        LoggerLazyEvaluationTests.counter.reset()
    }

    @MainActor
    func testDebugMessageNotEvaluatedWhenDisabled() {
        // Given: default enableDebugLogs=false
        // When: send a debug log with an expensive message
        Logger.shared.debug(expensiveMessage("SHOULD_NOT_EVALUATE"))
        
        // Then: side effect should not happen
        XCTAssertEqual(Self.counter.getValue(), 0)
    }

    @MainActor
    func testDebugMessageEvaluatedWhenEnabled() {
        // Given
        UserDefaults.standard.set(true, forKey: "enableDebugLogs")
        Logger.shared.refreshConfig() // reload config
        
        // When
        Logger.shared.debug(expensiveMessage("SHOULD_EVALUATE"))
        
        // Then: side effect should occur exactly once
        XCTAssertEqual(Self.counter.getValue(), 1)
    }
}
