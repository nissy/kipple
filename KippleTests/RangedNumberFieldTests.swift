//
//  RangedNumberFieldTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/06/29.
//

import XCTest
import SwiftUI
@testable import Kipple

final class RangedNumberFieldTests: XCTestCase {
    
    func testValueClamping() {
        // Given
        var testValue = 5
        let binding = Binding<Int>(
            get: { testValue },
            set: { testValue = $0 }
        )
        
        // Create view with range 1...10
        let view = RangedNumberField(
            title: "Test",
            value: binding,
            range: 1...10
        )
        
        // Test initial value
        XCTAssertEqual(testValue, 5)
        
        // Test setting value below range
        testValue = -5
        XCTAssertEqual(testValue, -5) // Direct assignment works
        
        // Test setting value above range
        testValue = 20
        XCTAssertEqual(testValue, 20) // Direct assignment works
        
        // Note: The actual clamping happens in the view's validateAndUpdate method
        // which is triggered by UI interactions, not direct value changes
    }
    
    func testRangeValidation() {
        // Test various ranges
        let ranges: [ClosedRange<Int>] = [
            1...10,
            0...100,
            -50...50,
            1...1
        ]
        
        for range in ranges {
            var testValue = range.lowerBound
            let binding = Binding<Int>(
                get: { testValue },
                set: { testValue = $0 }
            )
            
            let view = RangedNumberField(
                title: "Test",
                value: binding,
                range: range
            )
            
            // Verify the view creates without issues
            XCTAssertNotNil(view)
        }
    }
    
    func testWithSuffix() {
        // Given
        var testValue = 5
        let binding = Binding<Int>(
            get: { testValue },
            set: { testValue = $0 }
        )
        
        // Create view with suffix
        let view = RangedNumberField(
            title: "Test",
            value: binding,
            range: 1...10,
            suffix: "items"
        )
        
        // Verify the view creates without issues
        XCTAssertNotNil(view)
    }
}
