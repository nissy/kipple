//
//  MenuBarAppTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/06/29.
//

import XCTest
@testable import Kipple

final class MenuBarAppTests: XCTestCase {
    var menuBarApp: MenuBarApp!
    
    override func setUp() {
        super.setUp()
        menuBarApp = MenuBarApp()
    }
    
    override func tearDown() {
        menuBarApp = nil
        super.tearDown()
    }
    
    func testMenuBarInitialization() {
        // Test that MenuBarApp initializes without errors
        XCTAssertNotNil(menuBarApp)
    }
    
    func testWindowCloseCallback() {
        // Given
        var closedCalled = false
        let expectation = XCTestExpectation(description: "Close callback called")
        
        let onCloseHandler: (() -> Void)? = {
            closedCalled = true
            expectation.fulfill()
        }
        
        // Create MainView with close callback
        _ = MainView(onClose: onCloseHandler)
        
        // When the onClose callback is triggered
        onCloseHandler?()
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(closedCalled)
    }
}
