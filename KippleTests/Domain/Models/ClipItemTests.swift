//
//  ClipItemTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/06/28.
//

import XCTest
@testable import Kipple

final class ClipItemTests: XCTestCase {
    
    func testClipItemCreation() {
        // Given
        let content = "Test content"
        
        // When
        let item = ClipItem(content: content)
        
        // Then
        XCTAssertEqual(item.content, content)
        XCTAssertFalse(item.isPinned)
        XCTAssertNotNil(item.id)
        XCTAssertTrue(item.timestamp.timeIntervalSinceNow < 1)
    }
    
    func testClipItemEquality() {
        // Given
        let item1 = ClipItem(content: "Test")
        let item2 = ClipItem(content: "Test")
        
        // Then
        XCTAssertNotEqual(item1.id, item2.id)
        XCTAssertEqual(item1.content, item2.content)
    }
    
    func testClipItemCodable() throws {
        // Given
        var item = ClipItem(content: "Test content")
        item.isPinned = true
        
        // When
        let encoded = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ClipItem.self, from: encoded)
        
        // Then
        XCTAssertEqual(item.id, decoded.id)
        XCTAssertEqual(item.content, decoded.content)
        XCTAssertEqual(item.isPinned, decoded.isPinned)
        XCTAssertEqual(item.timestamp.timeIntervalSince1970, decoded.timestamp.timeIntervalSince1970, accuracy: 0.001)
    }
}
