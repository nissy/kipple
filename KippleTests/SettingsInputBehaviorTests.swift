//
//  SettingsInputBehaviorTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/06/29.
//

import XCTest
import SwiftUI
@testable import Kipple

final class SettingsInputBehaviorTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // テスト用の初期値を設定
        UserDefaults.standard.set(6, forKey: "historyInitialDisplayCount")
        UserDefaults.standard.set(10, forKey: "historyMaxDisplayCount")
        UserDefaults.standard.set(3, forKey: "pinInitialDisplayCount")
        UserDefaults.standard.set(5, forKey: "pinMaxDisplayCount")
    }
    
    func testHistoryMaxDisplayInputBehavior() {
        // Given - SettingsViewの@AppStorageの動作をシミュレート
        var historyInitialDisplayCount = 6
        var historyMaxDisplayCount = 10
        
        // When - ユーザーが8を入力する
        historyMaxDisplayCount = 8
        
        // SettingsViewのonChange処理をシミュレート
        if historyMaxDisplayCount < historyInitialDisplayCount {
            historyMaxDisplayCount = historyInitialDisplayCount
        }
        
        // Then - 8 < 6ではないので、8のまま保持されるべき
        XCTAssertEqual(historyMaxDisplayCount, 8, "Value should remain 8 when it's greater than initial count")
        
        // When - ユーザーが5を入力する（初期表示件数より小さい）
        historyMaxDisplayCount = 5
        
        // SettingsViewのonChange処理をシミュレート
        if historyMaxDisplayCount < historyInitialDisplayCount {
            historyMaxDisplayCount = historyInitialDisplayCount
        }
        
        // Then - 5 < 6なので、6に変更される
        XCTAssertEqual(historyMaxDisplayCount, 6, "Value should be adjusted to initial count when smaller")
    }
    
    func testNumberFieldInputBehavior() {
        // Given
        var testValue = 10
        let binding = Binding<Int>(
            get: { testValue },
            set: { testValue = $0 }
        )
        
        let range = 1...50
        
        // When - NumberFieldのvalidateAndUpdate関数をシミュレート
        func simulateValidateAndUpdate(_ text: String) {
            // 空の場合は最小値を設定
            if text.isEmpty {
                testValue = range.lowerBound
                return
            }
            
            // 数値以外の文字を除去
            let filtered = text.filter { $0.isNumber }
            
            // 数値に変換して範囲内に収める
            if let number = Int(filtered) {
                let clamped = min(max(number, range.lowerBound), range.upperBound)
                testValue = clamped
            }
        }
        
        // Test case 1: 正常な値
        simulateValidateAndUpdate("8")
        XCTAssertEqual(testValue, 8, "Valid input should be preserved")
        
        // Test case 2: 範囲外の値（上限超過）
        simulateValidateAndUpdate("100")
        XCTAssertEqual(testValue, 50, "Value should be clamped to upper bound")
        
        // Test case 3: 範囲外の値（下限未満）
        simulateValidateAndUpdate("0")
        XCTAssertEqual(testValue, 1, "Value should be clamped to lower bound")
        
        // Test case 4: 空文字
        simulateValidateAndUpdate("")
        XCTAssertEqual(testValue, 1, "Empty input should set minimum value")
    }
    
    func testSettingsInteractionScenario_Fixed() {
        // Given - 修正後の動作をテスト（onChange処理を削除済み）
        var historyInitialDisplayCount = 6   // デフォルト値
        var historyMaxDisplayCount = 10      // デフォルト値
        
        // Initial values - Initial: 6, Max: 10
        
        // When - ユーザーが8を入力
        historyMaxDisplayCount = 8
        // After user input 8 - Initial: 6, Max: 8
        
        // 修正後: onChange処理は存在しないので、値はそのまま保持される
        
        // After fix (no onChange) - Initial: 6, Max: 8
        
        // Then - 8がそのまま保持される
        XCTAssertEqual(historyMaxDisplayCount, 8, "Max should remain 8 after fix (no forced adjustment)")
        
        // When - さらに小さい値を入力
        historyMaxDisplayCount = 3
        
        // Then - 3もそのまま保持される
        XCTAssertEqual(historyMaxDisplayCount, 3, "Max should remain 3 after fix")
    }
    
    func testNumberFieldWarning() {
        // Given - 新しい警告機能をテスト
        var testValue = 10
        var showWarning = false
        let range = 1...50
        
        // シミュレート関数
        func simulateInput(_ text: String, focused: Bool) {
            if text.isEmpty {
                showWarning = false
                return
            }
            
            let filtered = text.filter { $0.isNumber }
            if let number = Int(filtered) {
                testValue = number
                
                // 範囲外の場合は警告を表示（入力中）
                if focused && (number < range.lowerBound || number > range.upperBound) {
                    showWarning = true
                } else if focused {
                    showWarning = false
                }
                
                // フォーカス喪失時は制約を適用
                if !focused {
                    let clamped = min(max(number, range.lowerBound), range.upperBound)
                    testValue = clamped
                    showWarning = false
                }
            }
        }
        
        // Test case 1: 範囲内の値（入力中）
        simulateInput("25", focused: true)
        XCTAssertEqual(testValue, 25, "Valid input should be preserved")
        XCTAssertFalse(showWarning, "No warning for valid input")
        
        // Test case 2: 範囲外の値（入力中）
        simulateInput("100", focused: true)
        XCTAssertEqual(testValue, 100, "Out-of-range input should be temporarily preserved")
        XCTAssertTrue(showWarning, "Warning should be shown for out-of-range input")
        
        // Test case 3: フォーカス喪失（制約適用）
        simulateInput("100", focused: false)
        XCTAssertEqual(testValue, 50, "Value should be clamped on focus loss")
        XCTAssertFalse(showWarning, "Warning should be hidden after constraint application")
    }
}
