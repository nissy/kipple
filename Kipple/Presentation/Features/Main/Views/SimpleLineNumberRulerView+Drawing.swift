//
//  SimpleLineNumberRulerView+Drawing.swift
//  Kipple
//
//  Created by Codex on 2025/09/23.
//

import AppKit

extension SimpleLineNumberRulerView {
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let dirtyRect = rect.intersection(bounds)
        guard !dirtyRect.isEmpty else { return }

        drawBackground(in: dirtyRect)
        let (fontSize, textAttributes) = setupFontAttributes(textView: textView)
        let fullText = textView.string as NSString

        if fullText.length == 0 {
            drawEmptyTextLineNumber(
                textView: textView,
                layoutManager: layoutManager,
                textContainer: textContainer,
                textAttributes: textAttributes,
                fontSize: fontSize
            )
            return
        }

        drawEditableSelectionHighlight(
            textView: textView,
            layoutManager: layoutManager,
            fullText: fullText
        )

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

        drawLastEmptyLine(
            fullText: fullText,
            layoutManager: layoutManager,
            textView: textView,
            textAttributes: textAttributes,
            rect: rect,
            fontSize: fontSize
        )
    }

    func drawBackground(in rect: NSRect) {
        guard backgroundColor.alphaComponent > 0 else { return }
        backgroundColor.set()
        rect.fill()
    }

    func drawEditableSelectionHighlight(
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        fullText: NSString
    ) {
        return
    }

    func drawBorder(in rect: NSRect) {
        return
    }

    func setupFontAttributes(textView: NSTextView) -> (CGFloat, [NSAttributedString.Key: Any]) {
        let fontSize = textView.font?.pointSize ?? 14
        let lineNumberFont = NSFont.monospacedSystemFont(ofSize: fontSize * 0.7, weight: .regular)

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: lineNumberFont,
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.72)
        ]

        return (fontSize, textAttributes)
    }

    func drawEmptyTextHighlight(textView: NSTextView) {
        return
    }

    func drawEmptyTextLineNumber(
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer,
        textAttributes: [NSAttributedString.Key: Any],
        fontSize: CGFloat
    ) {
        let lineString = "1"
        let size = lineString.size(withAttributes: textAttributes)
        let lineNumberFont = textAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: fontSize)

        _ = textView.visibleRect
        let containerOrigin = textView.textContainerOrigin
        let textContainerInset = textView.textContainerInset

        let paragraphStyle = textView.defaultParagraphStyle
        let lineHeight = paragraphStyle?.minimumLineHeight ?? fixedLineHeight

        let lineRect = NSRect(x: 0, y: 0, width: 100, height: lineHeight)
        let lineY = lineRect.origin.y + containerOrigin.y - textView.visibleRect.origin.y

        let lineNumberHeight = lineNumberFont.ascender - lineNumberFont.descender
        let lineCenterY = lineY + textContainerInset.height + (lineHeight / 2)
        let offset = FontManager.currentEditorLayoutSettings().lineNumberVerticalOffset
        let drawingY = lineCenterY - (lineNumberHeight / 2) - lineNumberFont.descender + offset

        let drawingPoint = NSPoint(
            x: ruleThickness - size.width - 5,
            y: drawingY
        )

        lineString.draw(at: drawingPoint, withAttributes: textAttributes)
    }

    func drawLastEmptyLine(
        fullText: NSString,
        layoutManager: NSLayoutManager,
        textView: NSTextView,
        textAttributes: [NSAttributedString.Key: Any],
        rect: NSRect,
        fontSize: CGFloat
    ) {
        guard fullText.length > 0 && fullText.hasSuffix("\n") else { return }

        let totalLineCount = SimpleLineNumberRulerView.countLines(in: fullText)
        let lastLineNumber = totalLineCount
        let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: fullText.length - 1)
        if lastGlyphIndex < layoutManager.numberOfGlyphs {
            let lastLineRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
            let containerOrigin = textView.textContainerOrigin
            let lineY = lastLineRect.maxY + containerOrigin.y - textView.visibleRect.origin.y

            let lineString = "\(lastLineNumber)"
            let size = lineString.size(withAttributes: textAttributes)
            let lineNumberFont = textAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: fontSize)
            let lineNumberHeight = lineNumberFont.ascender - lineNumberFont.descender
            let lineCenterY = lineY + textView.textContainerInset.height + (fixedLineHeight / 2)
            let offset = FontManager.currentEditorLayoutSettings().lineNumberVerticalOffset
            let drawingY = lineCenterY - (lineNumberHeight / 2) - lineNumberFont.descender + offset

            guard drawingY + lineNumberHeight >= -200,
                  drawingY <= bounds.height + 200 else {
                return
            }

            let drawingPoint = NSPoint(
                x: ruleThickness - size.width - 5,
                y: drawingY
            )

            lineString.draw(at: drawingPoint, withAttributes: textAttributes)
        }
    }
}
