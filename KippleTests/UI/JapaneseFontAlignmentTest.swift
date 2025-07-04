//
//  JapaneseFontAlignmentTest.swift
//  KippleTests
//
//  Created by Kipple on 2025/07/02.
//

import XCTest
import AppKit
@testable import Kipple

class JapaneseFontAlignmentTest: XCTestCase {
    
    func testFontMetricsComparison() {
        // 英語フォントと日本語フォントのメトリクスを比較
        let fontSize: CGFloat = 14
        
        // 英語フォント
        let englishFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        
        // 日本語フォント（ヒラギノ）
        if let japaneseFont = NSFont(name: "HiraginoSans-W3", size: fontSize) {
            
            // 差分を計算
            let japaneseLineHeight = japaneseFont.ascender - japaneseFont.descender + japaneseFont.leading
            let englishLineHeight = englishFont.ascender - englishFont.descender + englishFont.leading
        }
    }
    
    func testLineNumberBaselineCalculation() {
        // 現在の実装での行番号のベースライン計算をテスト
        let fontSize: CGFloat = 14
        let textFont = NSFont(name: "HiraginoSans-W3", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let lineNumberFont = NSFont.monospacedSystemFont(ofSize: fontSize * 0.7, weight: .regular)
        
        // 仮想的な行の位置
        let lineY: CGFloat = 100
        
        // 現在の実装（SimpleLineNumberView.swift の line 416-419）
        let baselineY = lineY + textFont.ascender
        let drawingY = baselineY - lineNumberFont.ascender
        
        // 代替案1: キャップハイトを使用
        let capHeightBaseline = lineY + textFont.capHeight
        let altDrawingY1 = capHeightBaseline - lineNumberFont.capHeight
        
        // 代替案2: 中央揃え
        let textCenter = lineY + (textFont.ascender - textFont.descender) / 2
        let lineNumberCenter = (lineNumberFont.ascender - lineNumberFont.descender) / 2
        let altDrawingY2 = textCenter - lineNumberCenter - lineNumberFont.descender
    }
    
    func testLayoutManagerLineFragmentPositioning() {
        // NSLayoutManagerが日本語テキストをどう配置するかテスト
        let textStorage = NSTextStorage(string: "あいうえお\nHello World\n123456")
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer()
        
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        
        // フォントを設定
        let font = NSFont(name: "HiraginoSans-W3", size: 14) ?? NSFont.systemFont(ofSize: 14)
        textStorage.addAttribute(.font, value: font, range: NSRange(location: 0, length: textStorage.length))
        
        // 段落スタイルを設定（SimpleLineNumberViewと同じ）
        let paragraphStyle = NSMutableParagraphStyle()
        let maxLineHeight = font.ascender - font.descender + font.leading
        paragraphStyle.minimumLineHeight = maxLineHeight
        paragraphStyle.maximumLineHeight = maxLineHeight
        paragraphStyle.lineHeightMultiple = 1.0
        textStorage.addAttribute(
            .paragraphStyle, 
            value: paragraphStyle, 
            range: NSRange(location: 0, length: textStorage.length)
        )
        
        // レイアウトを強制実行
        layoutManager.ensureLayout(for: textContainer)
        
        // 各行のフラグメントを調査
        var lineNumber = 1
        let glyphRange = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, glyphRange, _ in
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let lineText = (textStorage.string as NSString).substring(with: characterRange)
            
            lineNumber += 1
        }
    }
    
    func testFontFallbackBehavior() {
        // フォントフォールバックの動作をテスト
        let fontManager = FontManager.shared
        
        // 日本語と英語を含むフォント設定
        let testSettings = FontSettings(
            primaryFontName: "SFMono-Regular",
            primaryFontSize: 14,
            fallbackFontNames: ["HiraginoSans-W3", "Menlo-Regular"],
            lineHeightMultiple: 1.4
        )
        
        let maxHeight = calculateMaxLineHeight(for: testSettings)
        
        // 各フォントの個別の高さ
        for fontName in testSettings.fontList {
            if let font = NSFont(name: fontName, size: testSettings.primaryFontSize) {
                let height = font.ascender - font.descender + font.leading
            }
        }
    }
    
    private func calculateMaxLineHeight(for settings: FontSettings) -> CGFloat {
        var maxHeight: CGFloat = 0
        
        for fontName in settings.fontList {
            if let font = NSFont(name: fontName, size: settings.primaryFontSize) {
                let fontHeight = font.ascender - font.descender + font.leading
                maxHeight = max(maxHeight, fontHeight)
            }
        }
        
        let minimumHeight = settings.primaryFontSize * 1.2
        return max(maxHeight, minimumHeight)
    }
}
