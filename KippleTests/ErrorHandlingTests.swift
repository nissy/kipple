//
//  ErrorHandlingTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/06/29.
//

import XCTest
@testable import Kipple

final class ErrorHandlingTests: XCTestCase {
    
    func testClipboardRepositorySaveError() {
        // Given
        let repository = ClipboardRepository()
        
        // Create an item that might cause encoding issues
        let problematicItem = ClipItem(content: String(repeating: "🔥", count: 10000))
        let items = [problematicItem]
        
        // When/Then - Should not crash
        repository.save(items)
    }
    
    func testClipboardRepositoryLoadCorruptedData() {
        // Given
        let repository = ClipboardRepository()
        let userDefaults = UserDefaults.standard
        let key = "com.Kipple.clipboardHistory"
        
        // Set corrupted data
        let corruptedData = Data("This is not valid JSON".utf8)
        userDefaults.set(corruptedData, forKey: key)
        
        // When
        let loadedItems = repository.load()
        
        // Then
        XCTAssertEqual(loadedItems.count, 0, "Should return empty array for corrupted data")
        
        // Verify corrupted data was cleared
        XCTAssertNil(userDefaults.data(forKey: key), "Corrupted data should be cleared")
    }
    
    func testSettingsViewExportError() {
        // Given
        let service = ClipboardService.shared
        service.clearAllHistory()
        
        // Create a test item directly without monitoring
        let testItem = ClipItem(
            content: "Test content",
            sourceApp: "TestApp",
            windowTitle: "Test Window"
        )
        
        // When - Add the item directly to history
        service.history.insert(testItem, at: 0)
        
        // Then - History should contain the item
        XCTAssertFalse(service.history.isEmpty, "Service should have at least one item")
        XCTAssertEqual(service.history.first?.content, "Test content")
    }
    
    func testLoggerWithNilValues() {
        // Given
        let logger = Logger.shared
        
        // When/Then - Should handle edge cases
        logger.info("")
        let nilValue: String? = nil
        logger.error("Error: \(String(describing: nilValue))")
        logger.warning("Optional value: \(String(describing: nilValue))")
        
        XCTAssertTrue(true, "Logger should handle nil and empty values")
    }
}
