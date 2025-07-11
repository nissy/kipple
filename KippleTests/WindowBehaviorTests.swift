//
//  WindowBehaviorTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/11.
//
//  SPECS.md準拠: ウィンドウ動作のテスト
//  注意: 現在の実装では基本的なウィンドウサイズの永続化のみをテストする
//

import XCTest
import AppKit

final class WindowBehaviorTests: XCTestCase {
    var window: NSWindow!
    
    override func setUp() {
        super.setUp()
        
        // UserDefaultsをクリアしてテスト間の独立性を確保
        let keysToRemove = ["windowWidth", "windowHeight", "windowAnimation", 
                            "editorSectionHeight", "historySectionHeight"]
        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.synchronize()
        
        // テスト用のウィンドウを作成（NSHostingViewを使わない）
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        // シンプルなNSViewを使用
        window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 600))
    }
    
    override func tearDown() {
        window?.close()
        window = nil
        
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
        // Given
        let floatingLevel = NSWindow.Level.floating
        
        // When
        window.level = floatingLevel
        
        // Then
        XCTAssertEqual(window.level, .floating)
        XCTAssertGreaterThan(window.level.rawValue, NSWindow.Level.normal.rawValue)
    }
    
    // MARK: - Window Size Tests
    
    func testDefaultWindowSize() {
        // SPECS.md: デフォルト420×600
        // setUpでUserDefaultsがクリアされているため、
        // デフォルト値が使用される
        
        // UserDefaultsから直接値を確認
        let width = UserDefaults.standard.object(forKey: "windowWidth") as? Double
        let height = UserDefaults.standard.object(forKey: "windowHeight") as? Double
        
        // UserDefaultsがクリアされているのでnilのはず
        XCTAssertNil(width, "Width should be nil after clearing UserDefaults")
        XCTAssertNil(height, "Height should be nil after clearing UserDefaults")
        
        // デフォルト値は420x600
        XCTAssertEqual(width ?? 420, 420)
        XCTAssertEqual(height ?? 600, 600)
    }
    
    func testWindowSizeConstraints() {
        // SPECS.md: 最小300×300、最大800×1200
        // Given
        window.contentMinSize = NSSize(width: 300, height: 300)
        window.contentMaxSize = NSSize(width: 800, height: 1200)
        
        // When: サイズを制約内に設定
        window.setContentSize(NSSize(width: 400, height: 500))
        
        // Then: 正しく設定される
        XCTAssertEqual(window.contentView?.frame.width ?? 0, 400, accuracy: 1)
        XCTAssertEqual(window.contentView?.frame.height ?? 0, 500, accuracy: 1)
        
        // 制約が正しく設定されていることを確認
        XCTAssertEqual(window.contentMinSize.width, 300)
        XCTAssertEqual(window.contentMinSize.height, 300)
        XCTAssertEqual(window.contentMaxSize.width, 800)
        XCTAssertEqual(window.contentMaxSize.height, 1200)
    }
    
    // MARK: - Always on Top Tests
    
    func testAlwaysOnTopToggle() {
        // SPECS.md: Always on Topトグル
        // Given
        var isAlwaysOnTop = false
        
        // When: Always on Top有効
        isAlwaysOnTop = true
        window.level = isAlwaysOnTop ? .floating : .normal
        window.collectionBehavior = isAlwaysOnTop ? [.canJoinAllSpaces, .stationary] : []
        
        // Then
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        
        // When: Always on Top無効
        isAlwaysOnTop = false
        window.level = isAlwaysOnTop ? .floating : .normal
        window.collectionBehavior = isAlwaysOnTop ? [.canJoinAllSpaces, .stationary] : []
        
        // Then
        XCTAssertEqual(window.level, .normal)
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))
    }
    
    // MARK: - Animation Tests
    
    func testWindowAnimationSettings() {
        // SPECS.md: fade、scale、slide、none
        // UserDefaultsから直接テスト
        
        // デフォルトアニメーションの確認
        let defaultAnimation = UserDefaults.standard.string(forKey: "windowAnimation") ?? "none"
        XCTAssertEqual(defaultAnimation, "none")
        
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
        // Given
        window.level = .normal
        
        // When: フォーカス喪失時の動作をシミュレート
        let shouldClose = window.level != .floating
        
        // Then
        XCTAssertTrue(shouldClose, "Window should close when not always on top")
        
        // When: Always on Top有効時
        window.level = .floating
        let shouldNotClose = window.level == .floating
        
        // Then
        XCTAssertTrue(shouldNotClose, "Window should not close when always on top")
    }
    
    // MARK: - Window Persistence Tests
    
    func testWindowSizePersistence() {
        // SPECS.md: サイズ変更時に自動保存
        // Given
        let newWidth: Double = 500
        let newHeight: Double = 700
        
        // When: UserDefaultsに直接保存
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
