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
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }
        
        // テキストビューの設定
        setupTextView(textView, context: context)
        
        // 段落スタイルの設定
        let lineHeight = calculateFixedLineHeight(for: font)
        let paragraphStyle = createParagraphStyle(lineHeight: lineHeight)
        setupParagraphStyle(textView: textView, paragraphStyle: paragraphStyle)
        
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
            
            applyParagraphStyle(
                to: textView,
                paragraphStyle: paragraphStyle,
                text: text,
                font: font
            )
            
            updateLineNumberView(scrollView: scrollView, lineHeight: lineHeight)
        }
    }
    
    private func createParagraphStyle(lineHeight: CGFloat) -> NSMutableParagraphStyle {
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
            // 循環更新を防ぐためにフラグを設定（Coordinatorにアクセスできないため、ここではテキストを直接設定）
            textView.string = text
        }
        
        // 段落スタイルを適用（IME入力中はスキップ）
        if !textView.hasMarkedText() && !textView.string.isEmpty {
            let range = NSRange(location: 0, length: textView.string.count)
            textView.textStorage?.beginEditing()
            textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
            textView.textStorage?.endEditing()
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
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor
        
        // CotEditorから学んだ重要な設定
        textView.layoutManager?.usesFontLeading = false
        
        // カスタムレイアウトマネージャーを設定
        if let layoutManager = textView.layoutManager {
            layoutManager.delegate = context.coordinator
        }
        
        // テキストコンテナの設定
        let verticalPadding = FontManager.shared.editorLayoutSettings.verticalPadding
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
        
        // 既存のテキストに適用
        if !text.isEmpty {
            let range = NSRange(location: 0, length: text.count)
            textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
        }
        
        // タイピング属性にも設定
        textView.typingAttributes = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]
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
    
    class Coordinator: NSObject, NSTextViewDelegate, NSLayoutManagerDelegate {
        var parent: SimpleLineNumberView
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var paragraphStyle = NSMutableParagraphStyle()
        private var notificationObserver: NSObjectProtocol?
        private var lastSelectedLine: Int = 1
        var isUpdatingText = false
        
        init(_ parent: SimpleLineNumberView) {
            self.parent = parent
            super.init()
        }
        
        deinit {
            if let observer = notificationObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        func setupNotifications() {
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
            
            // 再計算と再描画
            let font = textView.font ?? NSFont.systemFont(ofSize: 14)
            let lineHeight = calculateFixedLineHeight(for: font)
            let paragraphStyle = parent.createParagraphStyle(lineHeight: lineHeight)
            
            textView.defaultParagraphStyle = paragraphStyle
            self.paragraphStyle = paragraphStyle
            
            // テキストコンテナのパディングを更新
            let verticalPadding = FontManager.shared.editorLayoutSettings.verticalPadding
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
            // 固定行高を強制
            guard let textView = textView,
                  let font = textView.font else { return false }
            
            let fixedLineHeight = calculateFixedLineHeight(for: font)
            
            // 行の高さを固定値に強制設定
            let currentHeight = lineFragmentRect.pointee.height
            if currentHeight < fixedLineHeight {
                // 行フラグメントの高さを固定値に設定
                lineFragmentRect.pointee.size.height = fixedLineHeight
                lineFragmentUsedRect.pointee.size.height = fixedLineHeight
            }
            
            // テキストのベースラインオフセットを調整
            let textBaselineOffset = FontManager.shared.editorLayoutSettings.textBaselineOffset
            
            // ベースラインを行の中央に配置
            let lineCenter = fixedLineHeight / 2.0
            let fontHeight = font.ascender - font.descender
            let newBaseline = lineCenter + (fontHeight / 2.0) + font.descender
            
            baselineOffset.pointee = newBaseline + textBaselineOffset
            
            return true
        }
    }
}

// 行番号描画のコンテキストを表す構造体
private struct LineNumberDrawingContext {
    let textView: NSTextView
    let layoutManager: NSLayoutManager
    let textContainer: NSTextContainer
    let fullText: NSString
    let textAttributes: [NSAttributedString.Key: Any]
    let rect: NSRect
    let fontSize: CGFloat
}

// 行番号描画のパラメータをまとめた構造体
private struct DrawLineNumberParams {
    let lineRect: NSRect
    let glyphRange: NSRange
    var currentLineNumber: Int
    let lineNumberFont: NSFont
    let visibleRect: NSRect
    let containerOrigin: NSPoint
    let textContainerInset: NSSize
    var previousCharacterLocation: Int = -1  // 前の行フラグメントの終了位置を追跡
}

// シンプルな行番号ルーラービュー
class SimpleLineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    var fixedLineHeight: CGFloat = 20 // 固定行高
    let fontManager = FontManager.shared
    
    // パフォーマンス最適化用のキャッシュ
    private var lastSelectedLine: Int = 1
    fileprivate var cachedLineCount: Int = 0
    fileprivate var cachedTextLength: Int = 0
    
    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.ruleThickness = 40
        self.clientView = textView
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = self.textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        
        // パフォーマンス最適化: 描画が必要な部分のみを処理
        let dirtyRect = rect.intersection(self.bounds)
        guard !dirtyRect.isEmpty else { return }
        
        // 背景と境界線を描画
        drawBackground(in: dirtyRect)
        drawBorder(in: dirtyRect)
        
        // フォント設定
        let (fontSize, textAttributes) = setupFontAttributes(textView: textView)
        
        // 全テキストの処理
        let fullText = textView.string as NSString
        
        // テキストが空の場合でも行番号1を表示
        if fullText.length == 0 {
            // 空のテキストのハイライトを描画
            drawEmptyTextHighlight(textView: textView)
            
            // 行番号を描画
            drawEmptyTextLineNumber(
                textView: textView,
                layoutManager: layoutManager,
                textContainer: textContainer,
                textAttributes: textAttributes,
                fontSize: fontSize
            )
            return
        }
        
        // 選択された行の処理
        let selectedRange = textView.selectedRange()
        let selectedLineNumber = calculateSelectedLineNumber(
            fullText: fullText,
            selectedRange: selectedRange
        )
        
        drawSelectedLineBackground(
            textView: textView,
            layoutManager: layoutManager,
            fullText: fullText,
            selectedLineNumber: selectedLineNumber
        )
        
        // 行番号を描画
        let drawingContext = LineNumberDrawingContext(
            textView: textView,
            layoutManager: layoutManager,
            textContainer: textContainer,
            fullText: fullText,
            textAttributes: textAttributes,
            rect: rect,
            fontSize: fontSize
        )
        drawLineNumbers(context: drawingContext)
        
        // 最後の空行の処理
        drawLastEmptyLine(
            fullText: fullText,
            layoutManager: layoutManager,
            textView: textView,
            textAttributes: textAttributes,
            rect: rect,
            fontSize: fontSize
        )
    }
    
    // MARK: - Helper Methods
    
    private func drawBackground(in rect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.5).set()
        rect.fill()
    }
    
    private func drawBorder(in rect: NSRect) {
        NSColor.separatorColor.set()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: ruleThickness - 0.5, y: 0))
        borderPath.line(to: NSPoint(x: ruleThickness - 0.5, y: rect.height))
        borderPath.lineWidth = 1.0
        borderPath.stroke()
    }
    
    private func setupFontAttributes(textView: NSTextView) -> (CGFloat, [NSAttributedString.Key: Any]) {
        let fontSize = textView.font?.pointSize ?? 14
        let lineNumberFont = NSFont.monospacedSystemFont(ofSize: fontSize * 0.7, weight: .regular)
        
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        
        return (fontSize, textAttributes)
    }
    
    private func calculateSelectedLineNumber(fullText: NSString, selectedRange: NSRange) -> Int {
        // パフォーマンス最適化：選択位置までのテキストのみを処理
        if selectedRange.location == 0 {
            return 1
        }
        
        // カーソルが最後の位置にあり、テキストが改行で終わっている場合
        if selectedRange.location == fullText.length && fullText.length > 0 && fullText.hasSuffix("\n") {
            // キャッシュを使用して高速化
            if cachedTextLength == fullText.length {
                return cachedLineCount
            }
            let lineCount = SimpleLineNumberRulerView.countLines(in: fullText)
            return lineCount
        }
        
        // 改行を効率的にカウント
        return SimpleLineNumberRulerView.countLines(in: fullText, upTo: selectedRange.location)
    }
    
    private func drawSelectedLineBackground(
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        fullText: NSString,
        selectedLineNumber: Int
    ) {
        // 空のテキストの場合の特別処理
        if fullText.length == 0 {
            drawEmptyTextHighlight(textView: textView)
            return
        }
        
        let visibleRect = textView.visibleRect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textView.textContainer!)
        // 行番号描画と同じ拡張範囲を使用（一貫性のため）
        let startLoc = max(0, visibleGlyphRange.location - 1000)
        // 最後まで確実に含めるため、numberOfGlyphs まで拡張
        let extendedGlyphRange = NSRange(
            location: startLoc,
            length: layoutManager.numberOfGlyphs - startLoc
        )
        
        // 基準点を正しく計算
        let containerOrigin = textView.textContainerOrigin
        
        // 論理行番号を追跡（drawLineNumbersと同じロジック）
        var currentLineNumber = 1
        if extendedGlyphRange.location > 0 {
            let range = NSRange(location: 0, length: extendedGlyphRange.location)
            let characterRange = layoutManager.characterRange(
                forGlyphRange: range,
                actualGlyphRange: nil
            )
            currentLineNumber = SimpleLineNumberRulerView.countLines(in: fullText, upTo: characterRange.location)
        }
        
        var isHighlightingLine = false
        var lastLineProcessed = currentLineNumber
        var lastLineRect: NSRect?
        
        layoutManager.enumerateLineFragments(forGlyphRange: extendedGlyphRange) { lineRect, _, _, glyphRange, _ in
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            
            // この行フラグメントが論理行の開始かどうか判定
            let isNewLogicalLine: Bool
            if characterRange.location == 0 {
                isNewLogicalLine = true
                isHighlightingLine = (currentLineNumber == selectedLineNumber)
            } else if characterRange.location > 0 && characterRange.location <= fullText.length {
                let previousCharIndex = characterRange.location - 1
                let previousChar = fullText.substring(with: NSRange(location: previousCharIndex, length: 1))
                isNewLogicalLine = (previousChar == "\n")
                if isNewLogicalLine {
                    currentLineNumber += 1
                    isHighlightingLine = (currentLineNumber == selectedLineNumber)
                }
            } else {
                isNewLogicalLine = false
            }
            
            // 選択された論理行に属するすべての行フラグメントをハイライト
            if isHighlightingLine {
                
                // 行番号の描画と完全に同じ計算を使用
                let lineY = lineRect.origin.y + containerOrigin.y - visibleRect.origin.y
                let textContainerInset = textView.textContainerInset
                
                // ハイライトの高さを固定行高を使用（行番号と一致させるため）
                let adjustedHeight = self.fixedLineHeight - textContainerInset.height * 2
                let adjustedY = lineY + textContainerInset.height
                
                NSColor.selectedTextBackgroundColor.withAlphaComponent(0.2).set()
                let path = NSBezierPath(rect: NSRect(
                    x: 0,
                    y: adjustedY,
                    width: self.ruleThickness,
                    height: adjustedHeight
                ))
                path.fill()
            }
            
            // 最後の行のrectを保存
            lastLineRect = lineRect
            lastLineProcessed = currentLineNumber
        }
        
        // 最終行が空行で選択されている場合の特別な処理
        drawLastLineHighlightIfNeeded(
            fullText: fullText,
            selectedLineNumber: selectedLineNumber,
            lastLineProcessed: lastLineProcessed,
            layoutManager: layoutManager,
            containerOrigin: containerOrigin,
            lastLineRect: lastLineRect
        )
    }
    
    private func drawLastLineHighlightIfNeeded(
        fullText: NSString,
        selectedLineNumber: Int,
        lastLineProcessed: Int,
        layoutManager: NSLayoutManager,
        containerOrigin: NSPoint,
        lastLineRect: NSRect?
    ) {
        // テキストが改行で終わっている場合
        if fullText.length > 0 && fullText.hasSuffix("\n") {
            let totalLineCount = fullText.components(separatedBy: "\n").count
            let lastLineNumber = totalLineCount
            
            // 最終行が選択されている場合
            if selectedLineNumber == lastLineNumber {
                var lineY: CGFloat
                
                // lastLineRectがある場合はそれを使用
                if let lastRect = lastLineRect {
                    // 最後の実際の行の下に空行のハイライトを描画
                    lineY = lastRect.maxY + containerOrigin.y - (self.textView?.visibleRect.origin.y ?? 0)
                } else {
                    // なければ最後のグリフから計算
                    if fullText.length > 0 {
                        // 最後の改行文字の前の文字位置を使用
                        let lastCharIndex = max(0, fullText.length - 2)
                        let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: lastCharIndex)
                        if lastGlyphIndex < layoutManager.numberOfGlyphs {
                            let rect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
                            lineY = rect.maxY + containerOrigin.y - (self.textView?.visibleRect.origin.y ?? 0)
                        } else {
                            // デフォルト位置
                            lineY = containerOrigin.y - (self.textView?.visibleRect.origin.y ?? 0)
                        }
                    } else {
                        lineY = containerOrigin.y - (self.textView?.visibleRect.origin.y ?? 0)
                    }
                }
                
                if let textView = self.textView {
                    let textContainerInset = textView.textContainerInset
                    let adjustedHeight = fixedLineHeight - textContainerInset.height * 2
                    let adjustedY = lineY + textContainerInset.height
                    
                    NSColor.selectedTextBackgroundColor.withAlphaComponent(0.2).set()
                    let path = NSBezierPath(rect: NSRect(
                        x: 0,
                        y: adjustedY,
                        width: self.ruleThickness,
                        height: adjustedHeight
                    ))
                    path.fill()
                }
            }
        }
    }
    
    private func drawEmptyTextHighlight(textView: NSTextView) {
        // 空のテキストの場合、最初の行をハイライト
        let containerOrigin = textView.textContainerOrigin
        let textContainerInset = textView.textContainerInset
        let visibleRect = textView.visibleRect
        
        // エディタの最初の行の位置に合わせてハイライトを描画
        let lineY = containerOrigin.y - visibleRect.origin.y
        let adjustedHeight = fixedLineHeight - textContainerInset.height * 2
        let adjustedY = lineY + textContainerInset.height
        
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.2).set()
        let path = NSBezierPath(rect: NSRect(
            x: 0,
            y: adjustedY,
            width: self.ruleThickness,
            height: adjustedHeight
        ))
        path.fill()
    }
    
    private func drawEmptyTextLineNumber(
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textAttributes: [NSAttributedString.Key: Any],
        fontSize: CGFloat
    ) {
        let lineString = "1"
        let size = lineString.size(withAttributes: textAttributes)
        let lineNumberFont = textAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: fontSize)
        
        // 基準点の計算（drawLineNumbersと同じ）
        _ = textView.visibleRect
        let containerOrigin = textView.textContainerOrigin
        let textContainerInset = textView.textContainerInset
        
        // 固定行高を使用（テキスト入力時と同じ高さを確保）
        // 段落スタイルから固定行高を取得
        let paragraphStyle = textView.defaultParagraphStyle
        let lineHeight = paragraphStyle?.minimumLineHeight ?? fixedLineHeight
        
        // 最初の行の矩形を仮想的に計算（固定行高を使用）
        let lineRect = NSRect(x: 0, y: 0, width: 100, height: lineHeight)
        
        // Y位置の計算（実際のレイアウトと同じ計算）
        let lineY = lineRect.origin.y + containerOrigin.y - visibleRect.origin.y
        
        // 行の中央に配置するための計算
        let lineNumberHeight = lineNumberFont.ascender - lineNumberFont.descender
        
        // 行の中央位置を計算
        let lineCenterY = lineY + textContainerInset.height + (lineHeight / 2)
        
        // 行番号を中央に配置（設定値でオフセット調整）
        let offset = fontManager.editorLayoutSettings.lineNumberVerticalOffset
        let drawingY = lineCenterY - (lineNumberHeight / 2) - lineNumberFont.descender + offset
        
        let drawingPoint = NSPoint(
            x: self.ruleThickness - size.width - 5,
            y: drawingY
        )
        
        lineString.draw(at: drawingPoint, withAttributes: textAttributes)
    }
    
    private func drawLineNumbers(context: LineNumberDrawingContext) {
        let lineNumberFont = context.textAttributes[.font] as? NSFont ??
            NSFont.systemFont(ofSize: context.fontSize)
        
        // 基準点の計算
        let visibleRect = context.textView.visibleRect
        let containerOrigin = context.textView.textContainerOrigin
        let textContainerInset = context.textView.textContainerInset
        
        // 可視範囲のグリフ範囲を取得
        let visibleGlyphRange = context.layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: context.textContainer
        )
        
        // 拡張範囲（スクロール時のちらつき防止と行番号消失防止）
        let startLoc = max(0, visibleGlyphRange.location - 1000)
        // 最後まで確実に含めるため、numberOfGlyphs まで拡張
        let extendedGlyphRange = NSRange(
            location: startLoc,
            length: context.layoutManager.numberOfGlyphs - startLoc
        )
        
        // 行番号を計算するための初期値
        var currentLineNumber = 1
        if extendedGlyphRange.location > 0 {
            currentLineNumber = calculateInitialLineNumber(
                context: context,
                extendedGlyphRange: extendedGlyphRange
            )
        }
        
        // 各行フラグメントに対して処理
        var previousCharLocation = -1
        context.layoutManager.enumerateLineFragments(
            forGlyphRange: extendedGlyphRange
        ) { lineRect, _, _, glyphRange, _ in
            var params = DrawLineNumberParams(
                lineRect: lineRect,
                glyphRange: glyphRange,
                currentLineNumber: currentLineNumber,
                lineNumberFont: lineNumberFont,
                visibleRect: visibleRect,
                containerOrigin: containerOrigin,
                textContainerInset: textContainerInset,
                previousCharacterLocation: previousCharLocation
            )
            self.drawLineNumber(context: context, params: &params)
            currentLineNumber = params.currentLineNumber
            
            // 次の反復のために文字位置を更新
            let characterRange = context.layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            previousCharLocation = characterRange.location + characterRange.length
        }
    }
    
    private func calculateInitialLineNumber(
        context: LineNumberDrawingContext,
        extendedGlyphRange: NSRange
    ) -> Int {
        let range = NSRange(location: 0, length: extendedGlyphRange.location)
        let characterRange = context.layoutManager.characterRange(
            forGlyphRange: range,
            actualGlyphRange: nil
        )
        
        // 効率的な行数カウントを使用
        return SimpleLineNumberRulerView.countLines(in: context.fullText, upTo: characterRange.location)
    }
    
    private func drawLineNumber(
        context: LineNumberDrawingContext,
        params: inout DrawLineNumberParams
    ) {
        let characterRange = context.layoutManager.characterRange(
            forGlyphRange: params.glyphRange,
            actualGlyphRange: nil
        )
        
        // この行フラグメントが論理行の開始かどうかを判定
        let isNewLogicalLine: Bool
        if characterRange.location == 0 {
            // 文書の最初は必ず論理行の開始
            isNewLogicalLine = true
        } else if characterRange.location > 0 && characterRange.location <= context.fullText.length {
            // 直前の文字が改行文字かチェック
            let previousCharIndex = characterRange.location - 1
            let previousChar = context.fullText.substring(
                with: NSRange(location: previousCharIndex, length: 1)
            )
            isNewLogicalLine = (previousChar == "\n")
        } else {
            isNewLogicalLine = false
        }
        
        // 論理行の開始の場合のみ行番号を描画
        if isNewLogicalLine {
            
            // Y位置の計算
            let lineY = params.lineRect.origin.y + params.containerOrigin.y - params.visibleRect.origin.y
            
            // 行の中央に配置するための計算
            let lineNumberHeight = params.lineNumberFont.ascender - params.lineNumberFont.descender
            let lineCenterY = lineY + params.textContainerInset.height + (self.fixedLineHeight / 2)
            
            // 行番号を中央に配置（設定値でオフセット調整）
            let offset = self.fontManager.editorLayoutSettings.lineNumberVerticalOffset
            let drawingY = lineCenterY - (lineNumberHeight / 2) -
                params.lineNumberFont.descender + offset
            
            // 描画範囲を大幅に拡張して、行番号が消えないようにする
            if drawingY + lineNumberHeight >= -200 && drawingY <= self.bounds.height + 200 {
                let lineString = "\(params.currentLineNumber)"
                let size = lineString.size(withAttributes: context.textAttributes)
                
                let drawingPoint = NSPoint(
                    x: self.ruleThickness - size.width - 5,
                    y: drawingY
                )
                
                lineString.draw(at: drawingPoint, withAttributes: context.textAttributes)
            }
        }
        
        // 次の行番号を計算（この行フラグメントに改行文字が含まれている場合のみインクリメント）
        if characterRange.location + characterRange.length <= context.fullText.length {
            let lineText = context.fullText.substring(with: characterRange)
            if lineText.contains("\n") {
                // 効率的な改行カウント
                var newlineCount = 0
                let nsLineText = lineText as NSString
                var searchRange = NSRange(location: 0, length: nsLineText.length)
                while searchRange.length > 0 {
                    let foundRange = nsLineText.range(of: "\n", options: [], range: searchRange)
                    if foundRange.location != NSNotFound {
                        newlineCount += 1
                        searchRange.location = foundRange.location + foundRange.length
                        searchRange.length = nsLineText.length - searchRange.location
                    } else {
                        break
                    }
                }
                params.currentLineNumber += newlineCount
            }
        }
    }
    
    private func drawLastEmptyLine(
        fullText: NSString,
        layoutManager: NSLayoutManager,
        textView: NSTextView,
        textAttributes: [NSAttributedString.Key: Any],
        rect: NSRect,
        fontSize: CGFloat
    ) {
        // 改行で終わる場合のみ最後の空行を処理
        guard fullText.length > 0 && fullText.hasSuffix("\n") else { return }
        
        // 最後の改行までの行数を効率的に計算
        let totalLineCount = SimpleLineNumberRulerView.countLines(in: fullText)
        
        // 最後の空行の処理（テキストが改行で終わる場合）
        if fullText.length > 0 && fullText.hasSuffix("\n") {
            let lastLineNumber = totalLineCount
            // 最後の行の位置を計算
            let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: fullText.length - 1)
            if lastGlyphIndex < layoutManager.numberOfGlyphs {
                let lastLineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
                    
                    // 基準点を正しく計算
                    let containerOrigin = textView.textContainerOrigin
                    
                    // 最後の空行のY位置計算（行番号と同じ計算）
                    let lineY = lastLineRect.maxY + containerOrigin.y - textView.visibleRect.origin.y
                    
                    let lineString = "\(lastLineNumber)"
                    let size = lineString.size(withAttributes: textAttributes)
                    
                    let lineNumberFont = textAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: fontSize)
                    
                    // 他の行と同じ計算方法を使用
                    let lineNumberHeight = lineNumberFont.ascender - lineNumberFont.descender
                    
                    // 行の中央位置を計算（固定行高を使用）
                    let lineCenterY = lineY + textView.textContainerInset.height + (fixedLineHeight / 2)
                    
                    // 行番号を中央に配置（設定値でオフセット調整）
                    let offset = fontManager.editorLayoutSettings.lineNumberVerticalOffset
                    let drawingY = lineCenterY - (lineNumberHeight / 2) - lineNumberFont.descender + offset
                    
                    // 描画範囲を大幅に拡張して、行番号が消えないようにする
                    if drawingY + lineNumberHeight >= -200 && drawingY <= self.bounds.height + 200 {
                        let drawingPoint = NSPoint(
                            x: self.ruleThickness - size.width - 5,
                            y: drawingY
                        )
                        
                        lineString.draw(at: drawingPoint, withAttributes: textAttributes)
                    }
                }
            }
        }
    
    // 効率的な行数カウント
    static func countLines(in string: NSString, upTo location: Int? = nil) -> Int {
        let searchLength = location ?? string.length
        if searchLength == 0 { return 1 }
        
        var lineCount = 1
        var searchRange = NSRange(location: 0, length: searchLength)
        
        while searchRange.length > 0 {
            let foundRange = string.range(of: "\n", options: [], range: searchRange)
            if foundRange.location != NSNotFound {
                lineCount += 1
                searchRange.location = foundRange.location + foundRange.length
                searchRange.length = searchLength - searchRange.location
            } else {
                break
            }
        }
        
        return lineCount
    }
    
    // 日本語フォントかどうかを判定
    private func isJapaneseFont(_ font: NSFont) -> Bool {
        let fontName = font.fontName.lowercased()
        return font.fontName.contains("Hiragino") ||
               font.fontName.contains("Yu") ||
               font.fontName.contains("Osaka") ||
               font.fontName.contains("Noto") && (fontName.contains("jp") || fontName.contains("cjk")) ||
               font.fontName.contains("Source Han") ||
               font.fontName.contains("ヒラギノ") ||
               font.fontName.contains("游") ||
               fontName.contains("gothic") ||
               fontName.contains("mincho")
    }
}

// 固定行高を計算するヘルパー関数
private func calculateFixedLineHeight(for font: NSFont) -> CGFloat {
    let fontManager = FontManager.shared
    
    // 基本フォントの高さ
    var maxHeight = font.ascender - font.descender
    
    // 日本語フォントの代表的なものも考慮
    let japaneseTestFonts = ["HiraginoSans-W3", "YuGothic-Medium", "NotoSansCJK-Regular"]
    for fontName in japaneseTestFonts {
        if let japaneseFont = NSFont(name: fontName, size: font.pointSize) {
            let height = japaneseFont.ascender - japaneseFont.descender
            maxHeight = max(maxHeight, height)
        }
    }
    
    // CJKテキストに適した余白（設定値を使用）
    let recommendedHeight = maxHeight * fontManager.editorLayoutSettings.lineHeightMultiplier
    
    // 最小値を保証（設定値を使用）
    let minimumHeight = font.pointSize * fontManager.editorLayoutSettings.minimumLineHeightMultiplier
    
    // 最終的な固定行高
    return ceil(max(recommendedHeight, minimumHeight))
}
