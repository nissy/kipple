//
//  SimpleLineNumberView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI
import AppKit

// シンプルで正確な行番号表示の実装
struct SimpleLineNumberView: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let onScrollChange: ((CGFloat) -> Void)?
    
    typealias Coordinator = SimpleLineNumberCoordinator
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        // テキストビューの設定（テキスト以外の基本設定）
        setupTextView(textView, context: context)
        
        // 段落スタイルの設定
        let lineHeight = calculateFixedLineHeight(for: font)
        let paragraphStyle = createParagraphStyle(lineHeight: lineHeight)
        setupParagraphStyle(textView: textView, paragraphStyle: paragraphStyle)
        
        // Coordinatorに固定行高を保存
        context.coordinator.fixedLineHeight = lineHeight
        
        // テキストを設定
        textView.string = text
        
        // スクロールビューの設定
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // カスタムルーラービューを設定
        let lineNumberView = SimpleLineNumberRulerView(textView: textView)
        lineNumberView.fixedLineHeight = lineHeight // 固定行高を渡す
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        
        // 参照を保存
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.paragraphStyle = paragraphStyle
        context.coordinator.setupNotifications()
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        
        // テキストが変更された場合のみ更新（IME入力中は除く）
        if textView.string != text && !textView.hasMarkedText() {
            // 循環更新を防ぐためにフラグを設定
            context.coordinator.isUpdatingText = true
            
            textView.string = text
            
            context.coordinator.isUpdatingText = false
            
            // テキストが空になった場合、行番号ビューを強制的に更新
            if text.isEmpty {
                if let rulerView = scrollView.verticalRulerView as? SimpleLineNumberRulerView {
                    rulerView.cachedLineCount = 1
                    rulerView.cachedTextLength = 0
                    rulerView.needsDisplay = true
                }
            }
        }
        
        // フォントが変更された場合のみ更新
        if textView.font != font {
            textView.font = font
            
            let lineHeight = calculateFixedLineHeight(for: font)
            let paragraphStyle = createParagraphStyle(lineHeight: lineHeight)
            context.coordinator.paragraphStyle = paragraphStyle
            context.coordinator.fixedLineHeight = lineHeight
            
            applyParagraphStyle(
                to: textView,
                paragraphStyle: paragraphStyle,
                text: text,
                font: font
            )
            
            updateLineNumberView(scrollView: scrollView, lineHeight: lineHeight)
        }
    }
    
    nonisolated func createParagraphStyle(lineHeight: CGFloat) -> NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = lineHeight
        paragraphStyle.maximumLineHeight = lineHeight
        paragraphStyle.lineHeightMultiple = 1.0
        paragraphStyle.lineSpacing = 0
        return paragraphStyle
    }
    
    private func applyParagraphStyle(
        to textView: NSTextView,
        paragraphStyle: NSMutableParagraphStyle,
        text: String,
        font: NSFont
    ) {
        textView.defaultParagraphStyle = paragraphStyle
        
        // IME入力中はテキストの同期をスキップ
        if !textView.hasMarkedText() && textView.string != text {
            // 属性付き文字列として設定（1文字目に依存しないように）
            let attributedString = NSMutableAttributedString(string: text)
            let fullRange = NSRange(location: 0, length: text.count)
            attributedString.addAttribute(.font, value: font, range: fullRange)
            attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
            attributedString.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            textView.textStorage?.setAttributedString(attributedString)
        }
        
        // タイピング属性も更新
        textView.typingAttributes = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]
        
        // テキストコンテナの最小サイズを維持
        if let textContainer = textView.textContainer {
            textContainer.size = NSSize(width: textContainer.size.width, height: 100000)
        }
    }
    
    private func setupTextView(_ textView: NSTextView, context: Context) {
        textView.delegate = context.coordinator
        textView.font = font
        // テキストの設定は段落スタイル適用後に移動
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor
        
        // CotEditorから学んだ重要な設定
        textView.layoutManager?.usesFontLeading = false
        
        // カスタムレイアウトマネージャーを設定
        if let layoutManager = textView.layoutManager {
            layoutManager.delegate = context.coordinator
            // タイポグラフィの動作を無効化して、固定行高を保証
            layoutManager.usesDefaultHyphenation = false
            layoutManager.typesetterBehavior = .latestBehavior
        }
        
        // テキストコンテナの設定
        let verticalPadding = FontManager.currentEditorLayoutSettings().verticalPadding
        textView.textContainerInset = NSSize(width: 8, height: verticalPadding)
        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
            textContainer.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            // 折り返しを有効にする設定
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
        }
        
        // テキストビューの折り返しを明示的に有効化
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = .width
    }
    
    private func setupParagraphStyle(textView: NSTextView, paragraphStyle: NSParagraphStyle) {
        textView.defaultParagraphStyle = paragraphStyle
        
        // タイピング属性を先に設定（新規入力時の属性を確実に設定）
        textView.typingAttributes = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]
        
        // 既存のテキストへの適用は削除（makeNSViewで属性付き文字列として設定するため）
    }
    
    private func updateLineNumberView(scrollView: NSScrollView, lineHeight: CGFloat) {
        if scrollView.verticalRulerView == nil {
            guard let textView = scrollView.documentView as? NSTextView else { return }
            let lineNumberView = SimpleLineNumberRulerView(textView: textView)
            lineNumberView.fixedLineHeight = lineHeight
            scrollView.verticalRulerView = lineNumberView
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = true
        } else if let lineNumberView = scrollView.verticalRulerView as? SimpleLineNumberRulerView {
            lineNumberView.fixedLineHeight = lineHeight
        }
        
        scrollView.verticalRulerView?.needsDisplay = true
    }
}
