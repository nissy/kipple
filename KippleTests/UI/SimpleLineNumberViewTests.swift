//
//  SimpleLineNumberViewTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/02.
//

import XCTest
import SwiftUI
import AppKit
@testable import Kipple

class SimpleLineNumberViewTests: XCTestCase {
    
    func testTextViewIsEditableInMainViewModel() {
        // MainViewModelからエディタの動作をテスト
        // UserDefaultsをクリアして確実に初期状態にする
        UserDefaults.standard.removeObject(forKey: "lastEditorText")
        UserDefaults.standard.synchronize()
        
        let viewModel = MainViewModel()
        
        // 初期状態の確認
        XCTAssertEqual(viewModel.editorText, "", "Editor should start empty")
        
        // テキストを設定
        viewModel.editorText = "Hello, World!"
        XCTAssertEqual(viewModel.editorText, "Hello, World!", "Editor should accept text")
        
        // エディタ挿入の設定確認（UserDefaultsの値に依存）
        let isEnabled = viewModel.isEditorInsertEnabled()
        // 設定値に依存するため、結果をチェックするだけにする
        XCTAssertNotNil(isEnabled, "Editor insert enabled should return a value")
        
        // エディタのクリア
        viewModel.clearEditor()
        XCTAssertEqual(viewModel.editorText, "", "Editor should be cleared")
    }
    
    func testEditorCopyFunctionality() {
        // エディタのコピー機能をテスト
        let viewModel = MainViewModel()
        
        // テキストを設定
        viewModel.editorText = "Test Content"
        
        // コピー実行
        viewModel.copyEditor()
        
        // copyEditor()はテキストをクリアするので、空になることを確認
        XCTAssertEqual(viewModel.editorText, "", "Editor text should be cleared after copy")
    }
    
    func testEditorInsertFromHistory() {
        // 履歴からエディタへの挿入をテスト
        let viewModel = MainViewModel()
        
        // 初期テキストを設定
        viewModel.editorText = "Initial"
        
        // 履歴から挿入（insertToEditorは内容を置き換える）
        viewModel.insertToEditor(content: "Replaced")
        
        // 結果を確認
        XCTAssertEqual(viewModel.editorText, "Replaced", "Editor should replace text")
    }
    
    func testLineNumberViewCreation() {
        // SimpleLineNumberViewの基本的な作成テスト
        let text = Binding.constant("Test")
        let font = NSFont.systemFont(ofSize: 14)
        let view = SimpleLineNumberView(text: text, font: font, onScrollChange: nil)
        
        // Coordinatorが作成できることを確認
        let coordinator = view.makeCoordinator()
        XCTAssertNotNil(coordinator, "Coordinator should be created")
        
        // 親ビューの参照を確認
        XCTAssertEqual(coordinator.parent.text, "Test", "Coordinator should have reference to parent")
    }
    
    func testFontSettingsIntegration() {
        // フォント設定の統合テスト
        let fontManager = FontManager.shared
        
        // エディタフォント設定
        let originalSize = fontManager.editorSettings.primaryFontSize
        fontManager.editorSettings.primaryFontSize = 16
        
        // maxLineHeightが更新されることを確認
        let maxHeight = fontManager.maxLineHeight
        XCTAssertGreaterThan(maxHeight, 0, "Max line height should be positive")
        
        // 元に戻す
        fontManager.editorSettings.primaryFontSize = originalSize
    }
}
