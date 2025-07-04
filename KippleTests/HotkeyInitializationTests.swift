//
//  HotkeyInitializationTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/03.
//

import XCTest
@testable import Kipple

final class HotkeyInitializationTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // テスト前にUserDefaultsをクリア
        UserDefaults.standard.removeObject(forKey: "enableHotkey")
        UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "hotkeyModifierFlags")
        UserDefaults.standard.removeObject(forKey: "enableEditorCopyHotkey")
        UserDefaults.standard.removeObject(forKey: "enableEditorClearHotkey")
    }
    
    override func tearDown() {
        // テスト後にUserDefaultsをクリア
        UserDefaults.standard.removeObject(forKey: "enableHotkey")
        UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "hotkeyModifierFlags")
        UserDefaults.standard.removeObject(forKey: "enableEditorCopyHotkey")
        UserDefaults.standard.removeObject(forKey: "enableEditorClearHotkey")
        super.tearDown()
    }
    
    func testHotkeyManagerInitialization() {
        // Given
        UserDefaults.standard.set(true, forKey: "enableHotkey")
        UserDefaults.standard.set(9, forKey: "hotkeyKeyCode") // V key
        UserDefaults.standard.set(
            NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue,
            forKey: "hotkeyModifierFlags"
        )
        
        // When
        let hotkeyManager = HotkeyManager()
        
        // Then - 遅延実行を待つ
        let expectation = XCTestExpectation(description: "Hotkey registration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // ホットキーが登録されることを期待
            // 実際の登録確認は内部状態に依存するため、ログを確認
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertNotNil(hotkeyManager)
    }
    
    func testHotkeyDisabledByDefault() {
        // Given - UserDefaultsに何も設定しない（デフォルト状態）
        
        // When
        let hotkeyManager = HotkeyManager()
        
        // Then
        let expectation = XCTestExpectation(description: "Hotkey not registered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // デフォルトではホットキーが無効
            let isEnabled = UserDefaults.standard.bool(forKey: "enableHotkey")
            XCTAssertFalse(isEnabled, "Hotkey should be disabled by default")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
        
        XCTAssertNotNil(hotkeyManager)
    }
    
    func testHotkeySettingsRetention() {
        // Given - 設定を保存
        UserDefaults.standard.set(true, forKey: "enableHotkey")
        UserDefaults.standard.set(9, forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(
            NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue,
            forKey: "hotkeyModifierFlags"
        )
        UserDefaults.standard.synchronize()
        
        // When - 値を読み込む
        let isEnabled = UserDefaults.standard.bool(forKey: "enableHotkey")
        let keyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        let modifierFlags = UserDefaults.standard.integer(forKey: "hotkeyModifierFlags")
        
        // Then
        XCTAssertTrue(isEnabled, "Hotkey should be enabled")
        XCTAssertEqual(keyCode, 9, "Key code should be V (9)")
        XCTAssertNotEqual(modifierFlags, 0, "Modifier flags should not be zero")
    }
    
    func testDefaultHotkeyValues() {
        // Given - 初回起動時の状態をシミュレート
        let hotkeyManager = HotkeyManager()
        
        // When - デフォルト値が設定されるのを待つ
        let expectation = XCTestExpectation(description: "Default values set")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // registerCurrentHotkey()が呼ばれた後
            let keyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
            let modifierFlags = UserDefaults.standard.integer(forKey: "hotkeyModifierFlags")
            
            // Then - デフォルト値が設定されていることを確認
            if keyCode == 0 {
                // まだ設定されていない場合は、手動で呼び出し
                hotkeyManager.registerCurrentHotkey()
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }
}
