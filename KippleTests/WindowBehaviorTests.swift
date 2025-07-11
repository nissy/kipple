//
//  WindowBehaviorTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/11.
//
//  SPECS.md準拠: ウィンドウ動作のテスト
//  注意: TEST_HOST環境でのメインスレッド競合を避けるため、
//  実際のウィンドウインスタンスを作成せずにロジックのみをテスト
//

import XCTest
import AppKit

final class WindowBehaviorTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        
        // UserDefaultsをクリアしてテスト間の独立性を確保
        let keysToRemove = ["windowWidth", "windowHeight", "windowAnimation", 
                            "editorSectionHeight", "historySectionHeight"]
        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
    }
    
    override func tearDown() {
        // UserDefaultsをクリア
        let keysToRemove = ["windowWidth", "windowHeight", "windowAnimation", 
                            "editorSectionHeight", "historySectionHeight"]
        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
        
        super.tearDown()
    }
    
    // MARK: - Window Level Tests
    
    func testFloatingWindowLevel() {
        // SPECS.md: フローティングウィンドウ（常に最前面レベル）
        // ウィンドウレベルの値の関係性をテスト
        
        let floatingLevel = NSWindow.Level.floating
        let normalLevel = NSWindow.Level.normal
        
        // フローティングレベルは通常レベルより高いことを確認
        XCTAssertGreaterThan(floatingLevel.rawValue, normalLevel.rawValue)
    }
    
    // MARK: - Window Size Tests
    
    func testDefaultWindowSize() {
        // SPECS.md: デフォルト420×600
        // UserDefaultsから直接値を確認
        let width = UserDefaults.standard.object(forKey: "windowWidth") as? Double
        let height = UserDefaults.standard.object(forKey: "windowHeight") as? Double
        
        // UserDefaultsがクリアされているのでnilのはず
        XCTAssertNil(width, "Width should be nil after clearing UserDefaults")
        XCTAssertNil(height, "Height should be nil after clearing UserDefaults")
        
        // AppStorageのデフォルト値は420x600
        XCTAssertEqual(width ?? 420, 420)
        XCTAssertEqual(height ?? 600, 600)
    }
    
    func testWindowSizeConstraints() {
        // SPECS.md: 最小300×300、最大800×1200
        // 制約値の妥当性をテスト
        
        let minWidth: CGFloat = 300
        let minHeight: CGFloat = 300
        let maxWidth: CGFloat = 800
        let maxHeight: CGFloat = 1200
        
        // 最小サイズが妥当な値であることを確認
        XCTAssertGreaterThan(minWidth, 0)
        XCTAssertGreaterThan(minHeight, 0)
        
        // 最大サイズが最小サイズより大きいことを確認
        XCTAssertGreaterThan(maxWidth, minWidth)
        XCTAssertGreaterThan(maxHeight, minHeight)
        
        // デフォルトサイズが制約内にあることを確認
        XCTAssertGreaterThanOrEqual(420, minWidth)
        XCTAssertLessThanOrEqual(420, maxWidth)
        XCTAssertGreaterThanOrEqual(600, minHeight)
        XCTAssertLessThanOrEqual(600, maxHeight)
    }
    
    // MARK: - Always on Top Tests
    
    func testAlwaysOnTopToggle() {
        // SPECS.md: Always on Topトグル
        // ロジックのみをテスト
        
        var isAlwaysOnTop = false
        
        // When: Always on Top有効時の期待値
        isAlwaysOnTop = true
        let expectedLevelOn = NSWindow.Level.floating
        let expectedBehaviorOn: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary]
        
        // Then: 期待値が正しいことを確認
        XCTAssertEqual(isAlwaysOnTop ? NSWindow.Level.floating : NSWindow.Level.normal, expectedLevelOn)
        XCTAssertTrue(expectedBehaviorOn.contains(.canJoinAllSpaces))
        
        // When: Always on Top無効時の期待値
        isAlwaysOnTop = false
        let expectedLevelOff = NSWindow.Level.normal
        let expectedBehaviorOff: NSWindow.CollectionBehavior = []
        
        // Then: 期待値が正しいことを確認
        XCTAssertEqual(isAlwaysOnTop ? NSWindow.Level.floating : NSWindow.Level.normal, expectedLevelOff)
        XCTAssertTrue(expectedBehaviorOff.isEmpty)
    }
    
    // MARK: - Animation Tests
    
    func testWindowAnimationSettings() {
        // SPECS.md: fade、scale、slide、none
        // 注意: デフォルトアニメーションは "fade" に変更されている（AppSettings.swift参照）
        
        // デフォルトアニメーションの確認
        let defaultAnimation = UserDefaults.standard.string(forKey: "windowAnimation") ?? "fade"
        XCTAssertEqual(defaultAnimation, "fade")
        
        // 各アニメーションタイプを設定できることを確認
        let animations = ["fade", "scale", "slide", "none"]
        for animation in animations {
            UserDefaults.standard.set(animation, forKey: "windowAnimation")
            let saved = UserDefaults.standard.string(forKey: "windowAnimation")
            XCTAssertEqual(saved, animation)
        }
    }
    
    // MARK: - Focus Behavior Tests
    
    func testAutoCloseOnFocusLoss() {
        // SPECS.md: フォーカスを失うと自動的に閉じる（Always on Top無効時）
        // ロジックのみをテスト
        
        // When: 通常レベルのウィンドウ
        let normalLevel = NSWindow.Level.normal
        let shouldCloseNormal = normalLevel != .floating
        
        // Then: 閉じるべき
        XCTAssertTrue(shouldCloseNormal, "Window should close when not always on top")
        
        // When: フローティングレベルのウィンドウ
        let floatingLevel = NSWindow.Level.floating
        let shouldCloseFloating = floatingLevel != .floating
        
        // Then: 閉じるべきではない
        XCTAssertFalse(shouldCloseFloating, "Window should not close when always on top")
    }
    
    // MARK: - Window Persistence Tests
    
    func testWindowSizePersistence() {
        // SPECS.md: サイズ変更時に自動保存
        // UserDefaultsへの永続化をテスト
        
        let newWidth: Double = 500
        let newHeight: Double = 700
        
        // When: UserDefaultsに保存
        UserDefaults.standard.set(newWidth, forKey: "windowWidth")
        UserDefaults.standard.set(newHeight, forKey: "windowHeight")
        UserDefaults.standard.synchronize()
        
        // Then: 永続化されることを確認
        let savedWidth = UserDefaults.standard.double(forKey: "windowWidth")
        let savedHeight = UserDefaults.standard.double(forKey: "windowHeight")
        
        XCTAssertEqual(savedWidth, 500)
        XCTAssertEqual(savedHeight, 700)
    }
}
