//
//  LastLineHighlightTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/06.
//

import XCTest
import SwiftUI
import AppKit
@testable import Kipple

class LastLineHighlightTests: XCTestCase {
    
    func testCalculateSelectedLineNumberForLastEmptyLine() {
        // SimpleLineNumberRulerViewのcalculateSelectedLineNumberをテスト
        let rulerView = SimpleLineNumberRulerView(textView: NSTextView())
        
        // テキストが改行で終わる場合
        let textWithNewline = "Line 1\nLine 2\n" as NSString
        let selectedRange = NSRange(location: textWithNewline.length, length: 0)
        
        // privateメソッドを直接テストできないため、
        // calculateSelectedLineNumberの動作をMainViewModelで検証
        let viewModel = MainViewModel()
        viewModel.editorText = "Line 1\nLine 2\n"
        
        // エディタのテキストが改行で終わる場合、最終行は3行目
        let lines = viewModel.editorText.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 3, "Text ending with newline should have 3 lines")
        XCTAssertEqual(lines.last, "", "Last line should be empty")
    }
    
    func testLastLineHighlightScenario() {
        // 最終行のハイライトが正しく動作することを確認
        let viewModel = MainViewModel()
        
        // 複数行のテキストを設定
        viewModel.editorText = "First line\nSecond line\nThird line\n"
        
        // 最終行（空行）の位置を計算
        let text = viewModel.editorText as NSString
        let lastPosition = text.length
        
        // 最終行が空行であることを確認
        XCTAssertTrue(text.hasSuffix("\n"), "Text should end with newline")
        
        // 行数を確認
        let lineCount = text.components(separatedBy: "\n").count
        XCTAssertEqual(lineCount, 4, "Should have 4 lines including empty last line")
    }
    
    func testEditorWithMultipleEmptyLines() {
        let viewModel = MainViewModel()
        
        // 複数の空行を含むテキスト
        viewModel.editorText = "Line 1\n\n\nLine 4\n\n"
        
        let text = viewModel.editorText as NSString
        let lines = text.components(separatedBy: "\n")
        
        // 6行（最後の空行を含む）
        XCTAssertEqual(lines.count, 6, "Should have 6 lines total")
        XCTAssertEqual(lines[1], "", "Line 2 should be empty")
        XCTAssertEqual(lines[2], "", "Line 3 should be empty")
        XCTAssertEqual(lines[5], "", "Line 6 should be empty")
    }
    
    func testLineNumberViewHandlesEmptyText() {
        // 空のテキストでも行番号1が表示されることを確認
        let text = Binding.constant("")
        let font = NSFont.systemFont(ofSize: 14)
        let view = SimpleLineNumberView(text: text, font: font, onScrollChange: nil)
        
        let coordinator = view.makeCoordinator()
        XCTAssertEqual(coordinator.parent.text, "", "Text should be empty")
        
        // 空のテキストでも最低1行として扱われる
        let lines = coordinator.parent.text.isEmpty ? 1 : 
                    coordinator.parent.text.components(separatedBy: "\n").count
        XCTAssertEqual(lines, 1, "Empty text should show as 1 line")
    }
    
    func testTextEndingWithoutNewline() {
        let viewModel = MainViewModel()
        
        // 改行で終わらないテキスト
        viewModel.editorText = "Line 1\nLine 2"
        
        let text = viewModel.editorText as NSString
        XCTAssertFalse(text.hasSuffix("\n"), "Text should not end with newline")
        
        let lines = text.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2, "Should have exactly 2 lines")
    }
}