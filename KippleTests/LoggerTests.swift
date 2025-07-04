//
//  LoggerTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/06/29.
//

import XCTest
@testable import Kipple

final class LoggerTests: XCTestCase {
    
    func testLoggerSingleton() {
        // Given
        let logger1 = Logger.shared
        let logger2 = Logger.shared
        
        // Then
        XCTAssertTrue(logger1 === logger2, "Logger should be a singleton")
    }
    
    func testLogLevels() {
        // Given
        let logger = Logger.shared
        
        // When/Then - These should not crash
        logger.debug("Debug message")
        logger.info("Info message")
        logger.warning("Warning message")
        logger.error("Error message")
        
        // Test with custom parameters
        logger.log("Custom message", level: .info)
        logger.log("Error occurred", level: .error)
    }
    
    func testLogWithFileInfo() {
        // Given
        let logger = Logger.shared
        let testFile = "TestFile.swift"
        let testFunction = "testFunction()"
        let testLine = 42
        
        // When/Then - Should not crash with custom file info
        logger.debug("Debug with file info", file: testFile, function: testFunction, line: testLine)
        logger.info("Info with file info", file: testFile, function: testFunction, line: testLine)
        logger.warning("Warning with file info", file: testFile, function: testFunction, line: testLine)
        logger.error("Error with file info", file: testFile, function: testFunction, line: testLine)
    }
    
    func testLogWithSpecialCharacters() {
        // Given
        let logger = Logger.shared
        
        // When/Then - Should handle special characters
        logger.info("Message with emoji 😀")
        logger.info("Message with newline\nand tab\t")
        logger.info("Message with quotes \"hello\" and 'world'")
        logger.info("Message with backslash \\")
    }
    
    func testLogWithLongMessage() {
        // Given
        let logger = Logger.shared
        let longMessage = String(repeating: "A", count: 1000)
        
        // When/Then - Should handle long messages
        logger.info(longMessage)
    }
}
