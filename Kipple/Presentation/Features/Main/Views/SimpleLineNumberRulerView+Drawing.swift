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
        drawBorder(in: dirtyRect)
        let (fontSize, textAttributes) = setupFontAttributes(textView: textView)
        let fullText = textView.string as NSString

        if fullText.length == 0 {
            drawEmptyTextHighlight(textView: textView)
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

        drawLastEmptyLine(context: drawingContext)
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
        guard textView.isEditable else { return }
        let selectedLineNumber = calculateSelectedLineNumber(
            fullText: fullText,
            selectedRange: textView.selectedRange()
        )
        drawSelectedLineBackground(
            textView: textView,
            layoutManager: layoutManager,
            fullText: fullText,
            selectedLineNumber: selectedLineNumber
        )
    }

    func drawBorder(in rect: NSRect) {
        NSColor.separatorColor.withAlphaComponent(0.45).set()
        let borderPath = NSBezierPath()
        let x = ruleThickness - 0.5
        borderPath.move(to: NSPoint(x: x, y: bounds.minY))
        borderPath.line(to: NSPoint(x: x, y: bounds.maxY))
        borderPath.lineWidth = 1
        borderPath.stroke()
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
        guard textView.isEditable else { return }

        let height = max(fixedLineHeight - textView.textContainerInset.height * 2, 1)
        let y = textView.textContainerInset.height - textView.visibleRect.origin.y
        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.12).set()
        NSBezierPath(rect: NSRect(
            x: 0,
            y: y,
            width: ruleThickness,
            height: height
        )).fill()
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

    func drawLastEmptyLine(context: LineNumberDrawingContext) {
        guard context.fullText.length > 0 && context.fullText.hasSuffix("\n") else { return }

        let totalLineCount = SimpleLineNumberRulerView.countLines(in: context.fullText)
        let lastLineNumber = totalLineCount
        let lastGlyphIndex = context.layoutManager.glyphIndexForCharacter(at: context.fullText.length - 1)
        if lastGlyphIndex < context.layoutManager.numberOfGlyphs {
            let lastLineRect = context.layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
            let containerOrigin = context.textView.textContainerOrigin
            let lineY = lastLineRect.maxY + containerOrigin.y - context.textView.visibleRect.origin.y

            let lineString = "\(lastLineNumber)"
            let drawingAttributes = lineNumberAttributes(
                context: context,
                lineNumber: lastLineNumber
            )
            let size = lineString.size(withAttributes: drawingAttributes)
            let lineNumberFont = context.textAttributes[.font] as? NSFont ??
                NSFont.systemFont(ofSize: context.fontSize)
            let lineNumberHeight = lineNumberFont.ascender - lineNumberFont.descender
            let lineCenterY = lineY + context.textView.textContainerInset.height + (fixedLineHeight / 2)
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

            lineString.draw(at: drawingPoint, withAttributes: drawingAttributes)
        }
    }
}
