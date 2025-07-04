//
//  SettingsReflectionTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/06/29.
//

import XCTest
import SwiftUI
@testable import Kipple

final class SettingsReflectionTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // デフォルト値を設定
        UserDefaults.standard.set(100, forKey: "maxHistoryItems")
        UserDefaults.standard.set(10, forKey: "maxPinnedItems")
    }
    
    func testMainViewModelReflectsSettings() {
        // Given
        let service = ClipboardService.shared
        service.history = []
        
        // 15個のアイテムを追加
        for i in 1...15 {
            service.history.append(ClipItem(content: "Item \(i)"))
        }
        
        // 5個のピン留めアイテムを追加
        for i in 1...5 {
            service.history.append(ClipItem(content: "Pinned \(i)", isPinned: true))
        }
        
        // When
        let viewModel = MainViewModel()
        
        // Wait for initialization
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        
        // Then - ViewModelが正しく履歴とピン留めアイテムを分けて管理していることを確認
        XCTAssertEqual(viewModel.history.count, 15, "History should contain all unpinned items")
        XCTAssertEqual(viewModel.pinnedItems.count, 5, "Pinned items should contain all pinned items")
        XCTAssertTrue(viewModel.history.allSatisfy { !$0.isPinned }, "History should only contain unpinned items")
        XCTAssertTrue(viewModel.pinnedItems.allSatisfy { $0.isPinned }, "Pinned items should only contain pinned items")
    }
    
    func testResizableSectionHeights() {
        // Given - ドラッグによる高さ調整のテスト設定
        // 初期値が設定されていない場合は0が返される
        
        // When - 新しい高さを設定
        UserDefaults.standard.set(350.0, forKey: "editorSectionHeight")
        UserDefaults.standard.set(400.0, forKey: "historySectionHeight")
        
        // Then - 設定が保存されることを確認
        XCTAssertEqual(UserDefaults.standard.double(forKey: "editorSectionHeight"), 350.0)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "historySectionHeight"), 400.0)
        
        // When - 別の値に変更
        UserDefaults.standard.set(275.0, forKey: "editorSectionHeight")
        UserDefaults.standard.set(325.0, forKey: "historySectionHeight")
        
        // Then - 新しい値が正しく保存されることを確認
        XCTAssertEqual(UserDefaults.standard.double(forKey: "editorSectionHeight"), 275.0)
        XCTAssertEqual(UserDefaults.standard.double(forKey: "historySectionHeight"), 325.0)
    }
}
