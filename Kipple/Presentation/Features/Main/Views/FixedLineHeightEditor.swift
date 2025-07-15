//
//  FixedLineHeightEditor.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI
import AppKit

// 固定行高エディタ - 日本語入力時の行高変動を完全に防ぐ
struct FixedLineHeightEditor: NSViewRepresentable {
    @Binding var text: String
    let font: NSFont
    let onScrollChange: ((CGFloat) -> Void)?
    @ObservedObject private var fontManager = FontManager.shared
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> FixedLineHeightEditorContainer {
        let container = FixedLineHeightEditorContainer()
        container.setup(font: font, text: text, coordinator: context.coordinator)
        return container
    }
    
    func updateNSView(_ container: FixedLineHeightEditorContainer, context: Context) {
        container.updateFont(font)
        if container.textView.string != text {
            container.textView.string = text
            container.applyFixedLineHeight()
            container.lineNumberView.needsDisplay = true
        }
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FixedLineHeightEditor
        
        init(_ parent: FixedLineHeightEditor) {
            self.parent = parent
            super.init()
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            
            // 固定行高を強制維持（即座に適用）
            if let container = textView.superview?.superview as? FixedLineHeightEditorContainer {
                // テキストが変更された直後に固定行高を再適用
                DispatchQueue.main.async {
                    container.applyFixedLineHeight()
                    container.lineNumberView.needsDisplay = true
                }
            }
        }
    }
}

// 固定行高エディタのコンテナ
class FixedLineHeightEditorContainer: NSView, NSLayoutManagerDelegate {
    var scrollView: NSScrollView!
    var textView: NSTextView!
    var lineNumberView: FixedLineNumberView!
    private var fixedLineHeight: CGFloat = 20
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        // スクロールビューとテキストビューの作成
        scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as? NSTextView
        
        // 行番号ビューの作成
        lineNumberView = FixedLineNumberView()
        lineNumberView.textView = textView
        
        // レイアウト設定
        addSubview(scrollView)
        addSubview(lineNumberView)
        
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        lineNumberView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // 行番号ビューを左端に固定
            lineNumberView.leadingAnchor.constraint(equalTo: leadingAnchor),
            lineNumberView.topAnchor.constraint(equalTo: topAnchor),
            lineNumberView.bottomAnchor.constraint(equalTo: bottomAnchor),
            lineNumberView.widthAnchor.constraint(equalToConstant: 50),
            
            // スクロールビューを行番号の右に配置
            scrollView.leadingAnchor.constraint(equalTo: lineNumberView.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // スクロール同期
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.lineNumberView.needsDisplay = true
        }
        
        // テキスト変更時の同期も追加
        NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.lineNumberView.needsDisplay = true
        }
    }
    
    func setup(font: NSFont, text: String, coordinator: FixedLineHeightEditor.Coordinator) {
        // 固定行高を計算（日本語フォントも考慮した最大高）
        fixedLineHeight = calculateFixedLineHeight(for: font)
        
        // テキストビューの設定
        textView.delegate = coordinator
        textView.font = font
        textView.string = text
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.labelColor
        
        // CotEditorから学んだ重要な設定：フォントリーディングを無効化
        textView.layoutManager?.usesFontLeading = false
        textView.layoutManager?.delegate = self
        
        // テキストコンテナの設定
        textView.textContainerInset = NSSize(width: 8, height: 4)
        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
        }
        
        // スクロールビューの設定
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // 固定行高を適用
        applyFixedLineHeight()
        
        // 行番号ビューの設定
        lineNumberView.fixedLineHeight = fixedLineHeight
        lineNumberView.font = font
    }
    
    func updateFont(_ font: NSFont) {
        fixedLineHeight = calculateFixedLineHeight(for: font)
        textView.font = font
        lineNumberView.font = font
        lineNumberView.fixedLineHeight = fixedLineHeight
        applyFixedLineHeight()
        lineNumberView.needsDisplay = true
    }
    
    func applyFixedLineHeight() {
        // 段落スタイルで行高を絶対固定
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = fixedLineHeight
        paragraphStyle.maximumLineHeight = fixedLineHeight
        paragraphStyle.lineHeightMultiple = 1.0
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.paragraphSpacingBefore = 0
        
        // デフォルトスタイルを設定
        textView.defaultParagraphStyle = paragraphStyle
        
        // 既存のテキストに強制適用
        if !textView.string.isEmpty {
            let range = NSRange(location: 0, length: textView.string.count)
            textView.textStorage?.beginEditing()
            textView.textStorage?.addAttribute(.paragraphStyle, value: paragraphStyle, range: range)
            textView.textStorage?.addAttribute(.font, value: textView.font!, range: range)
            textView.textStorage?.endEditing()
        }
        
        // タイピング時の新しいテキストにも適用されるように
        textView.typingAttributes = [
            .font: textView.font!,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.labelColor
        ]
        
        // レイアウトを強制更新
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    }
    
    private func calculateFixedLineHeight(for font: NSFont) -> CGFloat {
        // CotEditorから学んだ実際のフォント取得による正確な計算
        
        // 基本フォントの高さ
        var maxHeight = font.ascender - font.descender
        
        // CJKテキストサンプルでフォールバック後の実際のフォントを確認
        let cjkTestStrings = ["あ", "漢", "中", "한", "字"]
        let latinTestStrings = ["A", "g", "M"]
        
        // テストテキストストレージを作成
        let testStorage = NSTextStorage()
        let testLayoutManager = NSLayoutManager()
        let testContainer = NSTextContainer()
        
        testStorage.addLayoutManager(testLayoutManager)
        testLayoutManager.addTextContainer(testContainer)
        testLayoutManager.usesFontLeading = false
        
        // CJKフォントの実際の高さを取得
        for testChar in cjkTestStrings {
            testStorage.mutableString.setString(testChar)
            testStorage.addAttribute(.font, value: font, range: NSRange(location: 0, length: 1))
            
            // システムがフォールバック選択後の実際のフォントを取得
            if let actualFont = testStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                let height = actualFont.ascender - actualFont.descender
                maxHeight = max(maxHeight, height)
            }
        }
        
        // Latin文字の実際の高さも確認
        for testChar in latinTestStrings {
            testStorage.mutableString.setString(testChar)
            testStorage.addAttribute(.font, value: font, range: NSRange(location: 0, length: 1))
            
            if let actualFont = testStorage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                let height = actualFont.ascender - actualFont.descender
                maxHeight = max(maxHeight, height)
            }
        }
        
        // CJKテキストに適した余白（1.7倍のリーディング）
        let cjkRecommendedHeight = maxHeight * 1.7
        
        // 最小値を保証（フォントサイズの1.6倍以上）
        let minimumHeight = font.pointSize * 1.6
        
        // 最終的な固定行高（整数値に丸めて一貫性を保つ）
        return ceil(max(cjkRecommendedHeight, minimumHeight))
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
        // CotEditorから学んだ統一行高制御
        
        // 現在の行高を固定行高に設定
        var rect = lineFragmentRect.pointee
        rect.size.height = fixedLineHeight
        lineFragmentRect.pointee = rect
        
        var usedRect = lineFragmentUsedRect.pointee
        usedRect.size.height = fixedLineHeight
        lineFragmentUsedRect.pointee = usedRect
        
        // ベースラインオフセットを調整
        if let font = textView.font {
            let fontDescender = font.descender
            let fontHeight = font.ascender - font.descender
            let centerOffset = (fixedLineHeight - fontHeight) / 2
            baselineOffset.pointee = centerOffset - fontDescender
        }
        
        return true
    }
}

// シンプルな固定行番号ビュー
class FixedLineNumberView: NSView {
    weak var textView: NSTextView?
    var fixedLineHeight: CGFloat = 20
    var font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // 背景を描画（常に）
        NSColor.controlBackgroundColor.withAlphaComponent(0.9).set()
        bounds.fill()
        
        // 右境界線を描画
        NSColor.separatorColor.set()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: bounds.width - 0.5, y: 0))
        borderPath.line(to: NSPoint(x: bounds.width - 0.5, y: bounds.height))
        borderPath.lineWidth = 1.0
        borderPath.stroke()
        
        // 行番号を描画（textViewがnilでも簡単な表示）
        if let textView = textView {
            drawLineNumbers(textView: textView)
        } else {
            // textViewがない場合でも最低限の表示
            drawDefaultLineNumber()
        }
    }
    
    private func drawDefaultLineNumber() {
        let lineNumberFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        
        let lineString = "1"
        let stringSize = lineString.size(withAttributes: textAttributes)
        let drawingPoint = NSPoint(
            x: bounds.width - stringSize.width - 8,
            y: 4  // textContainerInsetに合わせる
        )
        lineString.draw(at: drawingPoint, withAttributes: textAttributes)
    }
    
    private func drawLineNumbers(textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        
        // CJKテキスト対応：行番号フォントも統一
        let lineNumberFont = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.8, weight: .regular)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        
        let text = textView.string as NSString
        
        // 空のテキストでも行番号1を表示
        if text.length == 0 {
            let lineString = "1"
            let stringSize = lineString.size(withAttributes: textAttributes)
            let textContainerInset = textView.textContainerInset.height
            let drawingPoint = NSPoint(
                x: bounds.width - stringSize.width - 8,
                y: textContainerInset
            )
            lineString.draw(at: drawingPoint, withAttributes: textAttributes)
            return
        }
        
        // CotEditorのアプローチ: NSLayoutManagerから実際の行位置を取得
        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        
        // 行番号を計算（全テキストの行数を取得）
        var lineNumber = 1
        let textBeforeRange = text.substring(to: min(glyphRange.location, text.length))
        lineNumber = textBeforeRange.components(separatedBy: "\n").count
        
        // 各行フラグメントに対して行番号を描画
        var lastY: CGFloat = -1000  // 前回描画したY位置
        
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { rect, _, _, glyphRange, _ in
            // スクロールビューからの相対位置を計算
            let containerOrigin = textView.textContainerOrigin
            let lineY = rect.origin.y + containerOrigin.y - textView.visibleRect.origin.y
            
            // 同じY位置の場合はスキップ（折り返し行）
            if abs(lineY - lastY) < 1.0 {
                return
            }
            
            // 行番号文字列
            let lineString = "\(lineNumber)"
            let stringSize = lineString.size(withAttributes: textAttributes)
            
            // 描画位置（フォントベースラインを考慮）
            let fontHeight = lineNumberFont.ascender - lineNumberFont.descender
            let baselineAdjustment = (self.fixedLineHeight - fontHeight) / 2
            let drawingPoint = NSPoint(
                x: self.bounds.width - stringSize.width - 8,
                y: lineY + baselineAdjustment
            )
            
            lineString.draw(at: drawingPoint, withAttributes: textAttributes)
            
            // 次の行番号を計算
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            let lineText = text.substring(with: characterRange)
            if lineText.contains("\n") {
                lineNumber += lineText.components(separatedBy: "\n").count - 1
            }
            
            lastY = lineY
        }
    }
    
    private func calculateLineNumber(for location: Int, in text: NSString) -> Int {
        let textBeforeLocation = text.substring(to: min(location, text.length))
        return textBeforeLocation.components(separatedBy: .newlines).count
    }
}
