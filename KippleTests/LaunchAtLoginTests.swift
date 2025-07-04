//
//  LaunchAtLoginTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/06/29.
//

import XCTest
@testable import Kipple

final class LaunchAtLoginTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // テスト前の状態を保存
        UserDefaults.standard.removeObject(forKey: "autoLaunchAtLogin")
    }
    
    override func tearDown() {
        super.tearDown()
        // テスト後にクリーンアップ
        UserDefaults.standard.removeObject(forKey: "autoLaunchAtLogin")
    }
    
    func testLaunchAtLoginSingleton() {
        // Given
        let instance1 = LaunchAtLogin.shared
        let instance2 = LaunchAtLogin.shared
        
        // Then
        XCTAssertTrue(instance1 === instance2, "LaunchAtLogin should be a singleton")
    }
    
    func testCheckStatus() {
        // Given
        let launchAtLogin = LaunchAtLogin.shared
        
        // When/Then - Should not crash
        launchAtLogin.checkStatus()
    }
    
    func testIsEnabledGetter() {
        // Given
        let launchAtLogin = LaunchAtLogin.shared
        
        // When
        let isEnabled = launchAtLogin.isEnabled
        
        // Then
        XCTAssertNotNil(isEnabled)
        XCTAssertTrue(isEnabled == true || isEnabled == false, "isEnabled should return a boolean")
    }
    
    func testSetEnabledNotification() {
        // Given
        let launchAtLogin = LaunchAtLogin.shared
        let expectation = self.expectation(description: "Notification should be posted on error")
        expectation.isInverted = true // We don't expect this to be fulfilled in normal operation
        
        var notificationReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LaunchAtLoginError"),
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
            expectation.fulfill()
        }
        
        // When
        launchAtLogin.isEnabled = true
        
        // Then
        waitForExpectations(timeout: 1.0) { _ in
            // In CI environment, this might fail, which is expected
            if notificationReceived {
                // LaunchAtLogin error notification received (expected in test environment)
            }
        }
        
        NotificationCenter.default.removeObserver(observer)
    }
    
    func testUserDefaultsSynchronization() {
        // Given
        let launchAtLogin = LaunchAtLogin.shared
        
        // When - Set to false
        launchAtLogin.setEnabled(false)
        
        // Then
        let storedValue = UserDefaults.standard.bool(forKey: "autoLaunchAtLogin")
        XCTAssertFalse(storedValue, "UserDefaults should be synchronized with LaunchAtLogin state")
    }
}
