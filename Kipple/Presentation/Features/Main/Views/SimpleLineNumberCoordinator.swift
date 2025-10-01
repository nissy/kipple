//
//  SimpleLineNumberCoordinator.swift
//  Kipple
//
//  Created by Codex on 2025/09/23.
//

import SwiftUI
import AppKit

final class SimpleLineNumberCoordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
    var parent: SimpleLineNumberView
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?
    var paragraphStyle = NSMutableParagraphStyle()
    private var notificationObserver: NSObjectProtocol?
    private var lastSelectedLine: Int = 1
    var isUpdatingText = false
    // 固定行高を保存（フォールバック後のフォントに影響されないように）
    var fixedLineHeight: CGFloat = 0
    
    init(parent: SimpleLineNumberView) {
        self.parent = parent
        super.init()
    }
    
    deinit {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func setupNotifications() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .editorLayoutSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateLayout()
        }
    }
    
    func updateLayout() {
        guard let textView = textView else { return }
        
        // 再計算と再描画（parent.fontを使用してオリジナルのフォントから計算）
        let font = parent.font
        let lineHeight = calculateFixedLineHeight(for: font)
        let paragraphStyle = parent.createParagraphStyle(lineHeight: lineHeight)
        
        // 固定行高を更新
        self.fixedLineHeight = lineHeight
        
        textView.defaultParagraphStyle = paragraphStyle
        self.paragraphStyle = paragraphStyle
        
        // テキストコンテナのパディングを更新
        let verticalPadding = FontManager.currentEditorLayoutSettings().verticalPadding
        textView.textContainerInset = NSSize(width: 8, height: verticalPadding)
        
        if !textView.string.isEmpty {
            let range = NSRange(location: 0, length: textView.string.count)
            textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
        
        // 行番号ビューを更新
        if let lineNumberView = scrollView?.verticalRulerView as? SimpleLineNumberRulerView {
            lineNumberView.fixedLineHeight = lineHeight
            lineNumberView.needsDisplay = true
        }
    }
    
    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        
        // 更新中の場合は処理をスキップ（循環更新を防ぐ）
        if isUpdatingText {
            return
        }
        
        // IME入力中（marked text がある場合）は処理をスキップ
        if textView.hasMarkedText() {
            return
        }
        
        // 同期的に親のテキストを更新（英数字入力時の問題を解決）
        parent.text = textView.string
        
        // 常に行番号エリアを再描画（行番号が消える問題を防ぐため）
        if let rulerView = scrollView?.verticalRulerView as? SimpleLineNumberRulerView {
            rulerView.needsDisplay = true
        }
    }
    
    func textViewDidChangeSelection(_ notification: Notification) {
        // 選択行が変わった場合は行番号エリア全体を再描画
        guard let textView = notification.object as? NSTextView,
              let rulerView = scrollView?.verticalRulerView as? SimpleLineNumberRulerView else { return }
        
        let newLine = calculateSelectedLineNumber(textView: textView)
        if newLine != lastSelectedLine {
            lastSelectedLine = newLine
            
            // 行番号エリア全体を再描画
            rulerView.needsDisplay = true
        }
    }
    
    private func calculateSelectedLineNumber(textView: NSTextView) -> Int {
        let selectedRange = textView.selectedRange()
        let text = textView.string as NSString
        
        if selectedRange.location == 0 {
            return 1
        }
        
        // カーソルが最後の位置にあり、テキストが改行で終わっている場合
        if selectedRange.location == text.length && text.length > 0 && text.hasSuffix("\n") {
            return text.components(separatedBy: "\n").count
        }
        
        let textBeforeSelection = text.substring(to: min(selectedRange.location, text.length))
        return textBeforeSelection.components(separatedBy: "\n").count
    }
    
    func textView(
        _ textView: NSTextView,
        shouldChangeTextIn affectedCharRange: NSRange,
        replacementString: String?
    ) -> Bool {
        // デフォルトの動作を維持
        return true
    }
    
    // MARK: - NSLayoutManagerDelegate
    
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        // 保存された固定行高を使用（初期化時に計算された値）
        let fixedLineHeight = self.fixedLineHeight > 0 ?
            self.fixedLineHeight :
            calculateFixedLineHeight(for: parent.font)
        
        // 行の高さを固定値に無条件で強制設定
        lineFragmentRect.pointee.size.height = fixedLineHeight
        lineFragmentUsedRect.pointee.size.height = fixedLineHeight
        
        // テキストのベースラインオフセットを調整
        let textBaselineOffset = FontManager.currentEditorLayoutSettings().textBaselineOffset
        
        // ベースラインを行の中央に配置（オリジナルフォントのメトリクスを使用）
        let lineCenter = fixedLineHeight / 2.0
        let originalFont = parent.font
        let fontHeight = originalFont.ascender - originalFont.descender
        let newBaseline = lineCenter + (fontHeight / 2.0) + originalFont.descender
        
        baselineOffset.pointee = newBaseline + textBaselineOffset
        
        return true
    }
    }
