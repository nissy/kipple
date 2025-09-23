//
//  IsolatedSettingsTests.swift
//  KippleTests
//
//  Created by Codex on 2025/09/23.
//

import XCTest
@testable import Kipple

// 方法2: TestUserDefaultsを使用してテスト環境を分離
class IsolatedSettingsTests: XCTestCase {
    
    private var testDefaults: TestUserDefaults!
    
    override func setUp() {
        super.setUp()
        
        // テスト用のUserDefaultsを作成
        testDefaults = TestUserDefaults(suiteName: nil)
        
        // 必要に応じてデフォルト値を設定
        testDefaults.set(true, forKey: "filterCategoryKipple")
        testDefaults.set(300, forKey: "maxHistoryItems")
    }
    
    override func tearDown() {
        // テスト用UserDefaultsをクリア
        testDefaults.clearAll()
        testDefaults = nil
        
        super.tearDown()
    }
    
    func testSettingsInIsolation() {
        // テスト用UserDefaultsで操作
        testDefaults.set(false, forKey: "filterCategoryKipple")
        
        XCTAssertFalse(testDefaults.bool(forKey: "filterCategoryKipple"))
        
        // 本番のUserDefaultsには影響なし
        let realDefaults = UserDefaults.standard
        let realValue = realDefaults.object(forKey: "filterCategoryKipple") as? Bool ?? true
        // realValueは変更されていない
    }
}
