//
//  SimpleLineNumberRulerView+LineNumbers.swift
//  Kipple
//
//  Created by Codex on 2025/09/23.
//

import AppKit

extension SimpleLineNumberRulerView {
    func drawLineNumbers(context: LineNumberDrawingContext) {
        let lineNumberFont = context.textAttributes[.font] as? NSFont ??
            NSFont.systemFont(ofSize: context.fontSize)
        let visibleRect = context.textView.visibleRect
        let containerOrigin = context.textView.textContainerOrigin
        let textContainerInset = context.textView.textContainerInset

        let visibleGlyphRange = context.layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: context.textContainer
        )
        let startLocation = max(0, visibleGlyphRange.location - 1000)
        let extendedGlyphRange = NSRange(
            location: startLocation,
            length: context.layoutManager.numberOfGlyphs - startLocation
        )

        let initialLineNumber = extendedGlyphRange.location > 0 ?
            calculateInitialLineNumber(
                context: context,
                extendedGlyphRange: extendedGlyphRange
            ) : 1

        let options = LineNumberRenderingOptions(
            extendedGlyphRange: extendedGlyphRange,
            lineNumberFont: lineNumberFont,
            visibleRect: visibleRect,
            containerOrigin: containerOrigin,
            textContainerInset: textContainerInset,
            initialLineNumber: initialLineNumber
        )

        enumerateLineFragmentsForNumbers(
            context: context,
            options: options
        )

        cachedTextLength = context.fullText.length
        cachedLineCount = Self.countLines(in: context.fullText)
    }

    private func enumerateLineFragmentsForNumbers(
        context: LineNumberDrawingContext,
        options: LineNumberRenderingOptions
    ) {
        var currentLineNumber = options.initialLineNumber
        var previousCharLocation = -1

        context.layoutManager.enumerateLineFragments(forGlyphRange: options.extendedGlyphRange) { lineRect, _, _, glyphRange, _ in
            var params = DrawLineNumberParams(
                lineRect: lineRect,
                glyphRange: glyphRange,
                currentLineNumber: currentLineNumber,
                lineNumberFont: options.lineNumberFont,
                visibleRect: options.visibleRect,
                containerOrigin: options.containerOrigin,
                textContainerInset: options.textContainerInset,
                previousCharacterLocation: previousCharLocation
            )
            self.drawLineNumber(context: context, params: &params)
            currentLineNumber = params.currentLineNumber

            let characterRange = context.layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            previousCharLocation = characterRange.location + characterRange.length
        }
    }

    private func drawLineNumber(
        context: LineNumberDrawingContext,
        params: inout DrawLineNumberParams
    ) {
        let characterRange = context.layoutManager.characterRange(
            forGlyphRange: params.glyphRange,
            actualGlyphRange: nil
        )

        if isLogicalLineStart(characterRange: characterRange, fullText: context.fullText) {
            renderLineNumber(
                context: context,
                params: params
            )
        }

        updateLineNumberCount(
            characterRange: characterRange,
            fullText: context.fullText,
            params: &params
        )
    }

    private func isLogicalLineStart(characterRange: NSRange, fullText: NSString) -> Bool {
        if characterRange.location == 0 {
            return true
        }
        guard characterRange.location > 0 && characterRange.location <= fullText.length else {
            return false
        }
        let previousCharIndex = characterRange.location - 1
        let previousChar = fullText.substring(
            with: NSRange(location: previousCharIndex, length: 1)
        )
        return previousChar == "\n"
    }

    private func renderLineNumber(
        context: LineNumberDrawingContext,
        params: DrawLineNumberParams
    ) {
        let lineY = params.lineRect.origin.y + params.containerOrigin.y - params.visibleRect.origin.y
        let lineNumberHeight = params.lineNumberFont.ascender - params.lineNumberFont.descender
        let lineCenterY = lineY + params.textContainerInset.height + (fixedLineHeight / 2)
        let offset = FontManager.currentEditorLayoutSettings().lineNumberVerticalOffset
        let drawingY = lineCenterY - (lineNumberHeight / 2) - params.lineNumberFont.descender + offset

        guard drawingY + lineNumberHeight >= -200,
              drawingY <= bounds.height + 200 else {
            return
        }

        let lineString = "\(params.currentLineNumber)"
        let size = lineString.size(withAttributes: context.textAttributes)
        let drawingPoint = NSPoint(
            x: ruleThickness - size.width - 5,
            y: drawingY
        )

        lineString.draw(at: drawingPoint, withAttributes: context.textAttributes)
    }

    private func updateLineNumberCount(
        characterRange: NSRange,
        fullText: NSString,
        params: inout DrawLineNumberParams
    ) {
        guard characterRange.location + characterRange.length <= fullText.length else {
            return
        }

        let lineText = fullText.substring(with: characterRange)
        guard lineText.contains("\n") else { return }

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

    func calculateInitialLineNumber(
        context: LineNumberDrawingContext,
        extendedGlyphRange: NSRange
    ) -> Int {
        let range = NSRange(location: 0, length: extendedGlyphRange.location)
        let characterRange = context.layoutManager.characterRange(
            forGlyphRange: range,
            actualGlyphRange: nil
        )

        return SimpleLineNumberRulerView.countLines(
            in: context.fullText,
            upTo: characterRange.location
        )
    }

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
}
