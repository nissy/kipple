//
//  TestUserDefaults.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/03.
//

import Foundation

/// テスト専用のUserDefaults実装
/// 本番のUserDefaultsに影響を与えないようにメモリ上でデータを管理する
class TestUserDefaults: UserDefaults {
    private var storage: [String: Any] = [:]
    
    override init?(suiteName suitename: String?) {
        super.init(suiteName: nil)
    }
    
    override func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }
    
    override func object(forKey defaultName: String) -> Any? {
        return storage[defaultName]
    }
    
    override func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
    
    override func string(forKey defaultName: String) -> String? {
        return storage[defaultName] as? String
    }
    
    override func integer(forKey defaultName: String) -> Int {
        return storage[defaultName] as? Int ?? 0
    }
    
    override func bool(forKey defaultName: String) -> Bool {
        return storage[defaultName] as? Bool ?? false
    }
    
    override func double(forKey defaultName: String) -> Double {
        return storage[defaultName] as? Double ?? 0.0
    }
    
    override func synchronize() -> Bool {
        // メモリ上のみなので同期は不要
        return true
    }
    
    override func data(forKey defaultName: String) -> Data? {
        return storage[defaultName] as? Data
    }
    
    override func set(_ value: Bool, forKey defaultName: String) {
        storage[defaultName] = value
    }
    
    override func set(_ value: Int, forKey defaultName: String) {
        storage[defaultName] = value
    }
    
    override func set(_ value: Double, forKey defaultName: String) {
        storage[defaultName] = value
    }
    
    /// テスト用のクリアメソッド
    func clearAll() {
        storage.removeAll()
    }
}
