//
//  TestHelpers.swift
//  KippleTests
//
//  テスト用のヘルパー関数と拡張
//

import Foundation
import XCTest

let savedHistoryCategoryID = UUID(uuidString: "EBBC4529-F432-4D84-A9FC-D4614BB0FF95")!

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
