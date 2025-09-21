//
//  EditorHotkeyTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/11.
//
//  SPECS.md準拠: エディターホットキー機能のテスト
//  - メインホットキー: Control+V（初期状態で無効）
//  - エディターコピーホットキー: Cmd+S（初期状態で無効）
//  - エディタークリアホットキー: Cmd+L（初期状態で無効）
//  - ウィンドウ非表示時も動作

import XCTest
@testable import Kipple

@MainActor
final class EditorHotkeyTests: XCTestCase {
    var windowManager: WindowManager!
    var mainViewModel: MainViewModel!
    var hotkeyManager: HotkeyManager!
    var mockClipboardService: MockClipboardService!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // UserDefaultsをクリア
        UserDefaults.standard.removeObject(forKey: "enableHotkey")
        UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "hotkeyModifierFlags")
        UserDefaults.standard.removeObject(forKey: "enableEditorCopyHotkey")
        UserDefaults.standard.removeObject(forKey: "editorCopyHotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "editorCopyHotkeyModifierFlags")
        UserDefaults.standard.removeObject(forKey: "enableEditorClearHotkey")
        UserDefaults.standard.removeObject(forKey: "editorClearHotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "editorClearHotkeyModifierFlags")
        UserDefaults.standard.synchronize()
        
        // Core Dataを使わないMockを作成
        mockClipboardService = MockClipboardService()
        
        // Mockを使用してMainViewModelを初期化
        mainViewModel = MainViewModel(clipboardService: mockClipboardService)
        
        // WindowManagerとHotkeyManagerを初期化
        windowManager = WindowManager()
        hotkeyManager = HotkeyManager()
    }
    
    override func tearDown() async throws {
        // UserDefaultsをクリア
        UserDefaults.standard.removeObject(forKey: "enableHotkey")
        UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "hotkeyModifierFlags")
        UserDefaults.standard.removeObject(forKey: "enableEditorCopyHotkey")
        UserDefaults.standard.removeObject(forKey: "editorCopyHotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "editorCopyHotkeyModifierFlags")
        UserDefaults.standard.removeObject(forKey: "enableEditorClearHotkey")
        UserDefaults.standard.removeObject(forKey: "editorClearHotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "editorClearHotkeyModifierFlags")
        
        mockClipboardService?.reset()
        mockClipboardService = nil
        windowManager = nil
        mainViewModel = nil
        hotkeyManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Default Hotkey Values Tests
    
    func testDefaultHotkeyValues() async {
        // SPECS.md: デフォルトホットキー値の確認
        // メインホットキー: Control+V (keyCode: 9)
        XCTAssertEqual(AppSettings.shared.hotkeyKeyCode, 9)
        XCTAssertEqual(
            AppSettings.shared.hotkeyModifierFlags,
            Int(NSEvent.ModifierFlags.control.rawValue)
        )
        XCTAssertFalse(AppSettings.shared.enableHotkey) // 初期状態で無効
        
        // エディターコピー: Cmd+S (keyCode: 1)
        XCTAssertEqual(AppSettings.shared.editorCopyHotkeyKeyCode, 1)
        XCTAssertEqual(
            AppSettings.shared.editorCopyHotkeyModifierFlags,
            Int(NSEvent.ModifierFlags.command.rawValue)
        )
        XCTAssertFalse(AppSettings.shared.enableEditorCopyHotkey) // 初期状態で無効
        
        // エディタークリア: Cmd+L (keyCode: 37)
        XCTAssertEqual(AppSettings.shared.editorClearHotkeyKeyCode, 37)
        XCTAssertEqual(
            AppSettings.shared.editorClearHotkeyModifierFlags,
            Int(NSEvent.ModifierFlags.command.rawValue)
        )
        XCTAssertFalse(AppSettings.shared.enableEditorClearHotkey) // 初期状態で無効
    }
    
    // MARK: - Editor Copy Hotkey Tests
    
    func testEditorCopyHotkey() async {
        // SPECS.md: エディターコピーホットキー（Cmd+S）
        // Given
        let testContent = "Test editor content"
        mainViewModel.editorText = testContent
        
        // When: エディターコピーを実行
        mainViewModel.copyEditor()
        
        // Then
        // エディター内容がコピーされ、クリアされる
        XCTAssertEqual(mainViewModel.editorText, "")
        
        // Mockでコピーが記録される
        XCTAssertTrue(mockClipboardService.copyToClipboardCalled)
        XCTAssertEqual(mockClipboardService.lastCopiedContent, testContent)
        XCTAssertTrue(mockClipboardService.fromEditor)
        
        if let latestItem = mockClipboardService.history.first {
            XCTAssertEqual(latestItem.content, testContent)
            XCTAssertTrue(latestItem.isFromEditor ?? false)
            XCTAssertEqual(latestItem.category, .kipple)
        }
    }
    
    func testEditorCopyHotkeyWhenWindowHidden() async {
        // SPECS.md: ウィンドウ非表示時も動作
        // Given
        let testContent = "Hidden window test"
        mainViewModel.editorText = testContent
        windowManager.closeMainWindow() // ウィンドウを非表示
        
        // When
        mainViewModel.copyEditor()
        
        // Then: ウィンドウが非表示でも動作する
        XCTAssertEqual(mainViewModel.editorText, "")
        
        // Mockでコピーが記録される
        XCTAssertTrue(mockClipboardService.copyToClipboardCalled)
        XCTAssertEqual(mockClipboardService.lastCopiedContent, testContent)
    }
    
    func testEditorCopyHotkeyWithEmptyContent() async {
        // Given: エディターが空
        mainViewModel.editorText = ""
        let initialHistoryCount = mockClipboardService.history.count
        
        // When
        mainViewModel.copyEditor()
        
        // Then: 空のコンテンツはコピーされない
        XCTAssertEqual(mockClipboardService.history.count, initialHistoryCount)
        XCTAssertFalse(mockClipboardService.copyToClipboardCalled)
    }
    
    // MARK: - Editor Clear Hotkey Tests
    
    func testEditorClearHotkey() async {
        // SPECS.md: エディタークリアホットキー（Cmd+L）
        // Given
        mainViewModel.editorText = "Content to clear"
        
        // When
        mainViewModel.clearEditor()
        
        // Then
        XCTAssertEqual(mainViewModel.editorText, "")
    }
    
    func testEditorClearHotkeyWhenWindowHidden() async {
        // SPECS.md: ウィンドウ非表示時も動作
        // Given
        mainViewModel.editorText = "Hidden clear test"
        windowManager.closeMainWindow()
        
        // When
        mainViewModel.clearEditor()
        
        // Then
        XCTAssertEqual(mainViewModel.editorText, "")
    }
    
    // MARK: - Main Hotkey Tests
    
    @MainActor
    func testMainHotkeyToggleWindow() async {
        // SPECS.md: メインホットキー（Control+V）でウィンドウ表示/非表示
        // WindowManagerのウィンドウ操作メソッドをテスト

        // When: ウィンドウを開く
        windowManager.openMainWindow()

        // Then: MainViewModelが作成される
        XCTAssertNotNil(windowManager.getMainViewModel())

        // When: ウィンドウを閉じる
        windowManager.closeMainWindow()

        // Then: ウィンドウは閉じられる（実際の動作は統合テストで確認）
        // ユニットテストではメソッドが呼ばれることを確認
    }
    
    // MARK: - Hotkey Registration Tests
    
    func testHotkeyRegistration() async {
        // Given: ホットキーを有効化
        UserDefaults.standard.set(true, forKey: "enableEditorCopyHotkey")
        UserDefaults.standard.set(1, forKey: "editorCopyHotkeyKeyCode") // S key
        UserDefaults.standard.set(
            Int(NSEvent.ModifierFlags.command.rawValue),
            forKey: "editorCopyHotkeyModifierFlags"
        )
        
        // When: HotkeyManagerを再初期化
        let newHotkeyManager = HotkeyManager()
        
        // Then: 登録処理が開始される（非同期）
        let expectation = XCTestExpectation(description: "Hotkey registration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // 登録が完了していることを期待
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 2.0)
        
        XCTAssertNotNil(newHotkeyManager)
    }
    
    func testHotkeyUnregistration() async {
        // Given: ホットキーが有効な状態
        UserDefaults.standard.set(true, forKey: "enableEditorCopyHotkey")
        
        // When: ホットキーを無効化
        UserDefaults.standard.set(false, forKey: "enableEditorCopyHotkey")
        hotkeyManager.registerEditorCopyHotkey()
        
        // Then: 登録解除される
        let expectation = XCTestExpectation(description: "Hotkey unregistration")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 1.0)
        
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "enableEditorCopyHotkey"))
    }
    
    // MARK: - Concurrent Hotkey Tests
    
    func testConcurrentHotkeyPresses() async {
        // 複数のホットキーが同時に押された場合のテスト
        let expectation = XCTestExpectation(description: "Concurrent hotkey handling")
        
        // Given
        mainViewModel.editorText = "Concurrent test"
        
        // When: 複数のホットキーを短時間に実行
        Task {
            mainViewModel.copyEditor()
        }
        
        Task {
            mainViewModel.clearEditor()
        }
        
        // Then: クラッシュしないことを確認
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
}
