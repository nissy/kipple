//
//  TestHelpers.swift
//  KippleTests
//
//  テスト用のヘルパー関数と拡張
//

import Foundation
import XCTest

// テスト環境でのメインスレッドブロックを回避するヘルパー
extension XCTestCase {
    /// UserDefaultsを安全にクリアする
    func clearTestUserDefaults(keys: [String]) {
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
    }
    
    /// テスト用の非同期待機
    func waitAsync(seconds: TimeInterval, completion: @escaping @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            completion()
        }
    }
}
