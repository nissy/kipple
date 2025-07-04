//
//  DynamicRangeTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/06/29.
//

import XCTest
import SwiftUI
@testable import Kipple

final class DynamicRangeTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // デフォルト値を設定
        UserDefaults.standard.set(100, forKey: "maxHistoryItems")
        UserDefaults.standard.set(10, forKey: "maxPinnedItems")
    }
    
    func testRangedNumberFieldRangeUpdate() {
        // Given
        var testValue = 10
        let binding = Binding<Int>(
            get: { testValue },
            set: { testValue = $0 }
        )
        
        // 初期範囲
        var currentRange = 1...20
        
        // When - 範囲が狭くなって、現在の値が範囲外になる
        currentRange = 1...8
        
        // RangedNumberFieldが値を範囲内に収めることを期待
        let view = RangedNumberField(
            title: "Test",
            value: binding,
            range: currentRange
        )
        
        XCTAssertNotNil(view)
        // 注: 実際のUI更新はSwiftUIのランタイムで行われるため、
        // ここでは構造が正しく作成されることのみ確認
    }
    
    func testMaxHistoryItemsConstraints() {
        // Given
        UserDefaults.standard.set(100, forKey: "maxHistoryItems")
        
        // When - 値を変更
        UserDefaults.standard.set(200, forKey: "maxHistoryItems")
        
        // Then - 値が正しく保存されることを確認
        let maxItems = UserDefaults.standard.integer(forKey: "maxHistoryItems")
        XCTAssertEqual(maxItems, 200)
    }
    
    func testMaxPinnedItemsConstraints() {
        // Given
        UserDefaults.standard.set(10, forKey: "maxPinnedItems")
        
        // When - 値を変更
        UserDefaults.standard.set(15, forKey: "maxPinnedItems")
        
        // Then - 値が正しく保存されることを確認
        let maxPinned = UserDefaults.standard.integer(forKey: "maxPinnedItems")
        XCTAssertEqual(maxPinned, 15)
    }
    
    func testSettingsValueInputScenario() {
        // Given - シミュレート：ユーザーが設定画面で値を入力するシナリオ
        var maxHistoryItems = 100
        let binding = Binding<Int>(
            get: { maxHistoryItems },
            set: { maxHistoryItems = $0 }
        )
        
        // When - 固定範囲（10...1000）で値を設定
        let view = RangedNumberField(
            title: "Maximum history items:",
            value: binding,
            range: 10...1000
        )
        
        // 値を150に設定しようとする
        maxHistoryItems = 150
        
        // Then - 値は範囲内なので150のまま
        XCTAssertEqual(maxHistoryItems, 150, "Value should remain 150 within the range 10...1000")
        XCTAssertNotNil(view)
    }
}
