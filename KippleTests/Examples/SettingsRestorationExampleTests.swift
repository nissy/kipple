//
//  SettingsRestorationExampleTests.swift
//  KippleTests
//
//  Created by Codex on 2025/09/23.
//

import XCTest
@testable import Kipple

// 方法1: setUp/tearDownで設定値を保存・復元
class SettingsRestorationExampleTests: XCTestCase {
    
    // 元の設定値を保存する変数
    private var originalFilterCategoryShortText: Bool!
    private var originalMaxHistoryItems: Int!
    
    override func setUp() {
        super.setUp()
        
        // テスト前の設定値を保存
        let defaults = UserDefaults.standard
        originalFilterCategoryShortText = defaults.object(forKey: "filterCategoryShortText") as? Bool ?? true
        originalMaxHistoryItems = defaults.object(forKey: "maxHistoryItems") as? Int ?? 300
    }
    
    override func tearDown() {
        // テスト後に元の設定値を復元
        let defaults = UserDefaults.standard
        defaults.set(originalFilterCategoryShortText, forKey: "filterCategoryShortText")
        defaults.set(originalMaxHistoryItems, forKey: "maxHistoryItems")
        defaults.synchronize()
        
        super.tearDown()
    }
    
    func testFilterSettingChange() {
        // テスト実行
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "filterCategoryShortText")
        
        // テストロジック
        XCTAssertFalse(defaults.bool(forKey: "filterCategoryShortText"))
        
        // tearDownで自動的に元の値に復元される
    }
}
