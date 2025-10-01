//
//  SettingsBackupTests.swift
//  KippleTests
//
//  Created by Codex on 2025/09/23.
//

import XCTest
@testable import Kipple

// 方法3: 設定値の一括保存・復元ヘルパー
class SettingsBackupHelper {
    
    private var backup: [String: Any] = [:]
    
    func backupSettings(keys: [String]) {
        let defaults = UserDefaults.standard
        for key in keys {
            if let value = defaults.object(forKey: key) {
                backup[key] = value
            }
        }
    }
    
    func restoreSettings() {
        let defaults = UserDefaults.standard
        for (key, value) in backup {
            defaults.set(value, forKey: key)
        }
        defaults.synchronize()
        backup.removeAll()
    }
}

// ヘルパーを使用したテスト例
class SettingsBackupTests: XCTestCase {
    
    private let backupHelper = SettingsBackupHelper()
    private let settingsKeys = [
        "filterCategoryKipple",
        "filterCategoryURL",
        "filterCategoryEmail",
        "maxHistoryItems",
        "maxPinnedItems"
    ]
    
    override func setUp() {
        super.setUp()
        backupHelper.backupSettings(keys: settingsKeys)
    }
    
    override func tearDown() {
        backupHelper.restoreSettings()
        super.tearDown()
    }
    
    func testMultipleSettingsChange() {
        let defaults = UserDefaults.standard
        
        // 複数の設定を変更
        defaults.set(false, forKey: "filterCategoryKipple")
        defaults.set(false, forKey: "filterCategoryURL")
        defaults.set(50, forKey: "maxHistoryItems")
        
        // テストロジック
        XCTAssertFalse(defaults.bool(forKey: "filterCategoryKipple"))
        XCTAssertFalse(defaults.bool(forKey: "filterCategoryURL"))
        XCTAssertEqual(defaults.integer(forKey: "maxHistoryItems"), 50)
        
        // tearDownですべて自動復元
    }
}
