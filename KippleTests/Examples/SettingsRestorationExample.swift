//
//  SettingsRestorationExample.swift
//  KippleTests
//
//  設定値の保存と復元の例
//

import XCTest
@testable import Kipple

// 方法1: setUp/tearDownで設定値を保存・復元
class SettingsRestorationExampleTests: XCTestCase {
    
    // 元の設定値を保存する変数
    private var originalFilterCategoryKipple: Bool!
    private var originalMaxHistoryItems: Int!
    
    override func setUp() {
        super.setUp()
        
        // テスト前の設定値を保存
        let defaults = UserDefaults.standard
        originalFilterCategoryKipple = defaults.object(forKey: "filterCategoryKipple") as? Bool ?? true
        originalMaxHistoryItems = defaults.object(forKey: "maxHistoryItems") as? Int ?? 300
    }
    
    override func tearDown() {
        // テスト後に元の設定値を復元
        let defaults = UserDefaults.standard
        defaults.set(originalFilterCategoryKipple, forKey: "filterCategoryKipple")
        defaults.set(originalMaxHistoryItems, forKey: "maxHistoryItems")
        defaults.synchronize()
        
        super.tearDown()
    }
    
    func testFilterSettingChange() {
        // テスト実行
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "filterCategoryKipple")
        
        // テストロジック
        XCTAssertFalse(defaults.bool(forKey: "filterCategoryKipple"))
        
        // tearDownで自動的に元の値に復元される
    }
}

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

// 方法4: UserDefaultsのモック化（依存性注入）
protocol UserDefaultsProtocol {
    func bool(forKey defaultName: String) -> Bool
    func set(_ value: Bool, forKey defaultName: String)
    func integer(forKey defaultName: String) -> Int
    func set(_ value: Int, forKey defaultName: String)
    func object(forKey defaultName: String) -> Any?
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: UserDefaultsProtocol {}

// モック実装
class MockUserDefaults: UserDefaultsProtocol {
    private var storage: [String: Any] = [:]
    
    func bool(forKey defaultName: String) -> Bool {
        return storage[defaultName] as? Bool ?? false
    }
    
    func set(_ value: Bool, forKey defaultName: String) {
        storage[defaultName] = value
    }
    
    func integer(forKey defaultName: String) -> Int {
        return storage[defaultName] as? Int ?? 0
    }
    
    func set(_ value: Int, forKey defaultName: String) {
        storage[defaultName] = value
    }
    
    func object(forKey defaultName: String) -> Any? {
        return storage[defaultName]
    }
    
    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
}

// 推奨される方法：
// 1. 単体テストではTestUserDefaultsやMockUserDefaultsを使用
// 2. 統合テストではsetUp/tearDownで設定値を保存・復元
// 3. 複数の設定を扱う場合はSettingsBackupHelperのようなユーティリティを使用
