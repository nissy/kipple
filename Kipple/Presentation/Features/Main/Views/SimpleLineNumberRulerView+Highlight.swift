//
//  SimpleLineNumberRulerView+Highlight.swift
//  Kipple
//
//  Created by Codex on 2025/09/23.
//

import AppKit

extension SimpleLineNumberRulerView {
    func calculateSelectedLineNumber(fullText: NSString, selectedRange: NSRange) -> Int {
        if selectedRange.location == 0 {
            return 1
        }

        if selectedRange.location == fullText.length && fullText.length > 0 && fullText.hasSuffix("\n") {
            if cachedTextLength == fullText.length {
                return cachedLineCount
            }
            return SimpleLineNumberRulerView.countLines(in: fullText)
        }

        return SimpleLineNumberRulerView.countLines(
            in: fullText,
            upTo: selectedRange.location
        )
    }

    func drawSelectedLineBackground(
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        fullText: NSString,
        selectedLineNumber: Int
    ) {
        guard fullText.length > 0 else {
            drawEmptyTextHighlight(textView: textView)
            return
        }

        let visibleRect = textView.visibleRect
        guard let textContainer = textView.textContainer else { return }
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: textContainer
        )
        let startLocation = max(0, visibleGlyphRange.location - 1000)
        let extendedGlyphRange = NSRange(
            location: startLocation,
            length: layoutManager.numberOfGlyphs - startLocation
        )
        let containerOrigin = textView.textContainerOrigin

        let initialLineNumber = initialLineNumber(
            layoutManager: layoutManager,
            fullText: fullText,
            extendedGlyphRange: extendedGlyphRange
        )

        let highlightInput = SelectedLineHighlightInput(
            fullText: fullText,
            selectedLineNumber: selectedLineNumber,
            containerOrigin: containerOrigin,
            visibleRect: visibleRect,
            extendedGlyphRange: extendedGlyphRange,
            initialLineNumber: initialLineNumber
        )

        let state = highlightSelectedLineFragments(
            textView: textView,
            layoutManager: layoutManager,
            input: highlightInput
        )

        drawLastLineHighlightIfNeeded(
            fullText: highlightInput.fullText,
            selectedLineNumber: highlightInput.selectedLineNumber,
            lastLineProcessed: state.lastLineProcessed,
            layoutManager: layoutManager,
            containerOrigin: highlightInput.containerOrigin,
            lastLineRect: state.lastLineRect
        )
    }

    func initialLineNumber(
        layoutManager: NSLayoutManager,
        fullText: NSString,
        extendedGlyphRange: NSRange
    ) -> Int {
        guard extendedGlyphRange.location > 0 else {
            return 1
        }

        let range = NSRange(location: 0, length: extendedGlyphRange.location)
        let characterRange = layoutManager.characterRange(
            forGlyphRange: range,
            actualGlyphRange: nil
        )
        return SimpleLineNumberRulerView.countLines(
            in: fullText,
            upTo: characterRange.location
        )
    }

    func highlightSelectedLineFragments(
        textView: NSTextView,
        layoutManager: NSLayoutManager,
        input: SelectedLineHighlightInput
    ) -> SelectedLineHighlightState {
        var state = SelectedLineHighlightState(
            currentLineNumber: input.initialLineNumber,
            lastLineProcessed: input.initialLineNumber,
            lastLineRect: nil
        )
        var isHighlightingLine = false

        layoutManager.enumerateLineFragments(forGlyphRange: input.extendedGlyphRange) { lineRect, _, _, glyphRange, _ in
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )

            if characterRange.location == 0 {
                isHighlightingLine = (state.currentLineNumber == input.selectedLineNumber)
            } else if characterRange.location > 0 && characterRange.location <= input.fullText.length {
                let previousCharIndex = characterRange.location - 1
                let previousChar = input.fullText.substring(
                    with: NSRange(location: previousCharIndex, length: 1)
                )
                if previousChar == "\n" {
                    state.currentLineNumber += 1
                    isHighlightingLine = (state.currentLineNumber == input.selectedLineNumber)
                }
            }

           if isHighlightingLine {
               let lineY = lineRect.origin.y + input.containerOrigin.y - input.visibleRect.origin.y
               let textContainerInset = textView.textContainerInset
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

            state.lastLineRect = lineRect
            state.lastLineProcessed = state.currentLineNumber
        }

        return state
    }

    func drawLastLineHighlightIfNeeded(
        fullText: NSString,
        selectedLineNumber: Int,
        lastLineProcessed: Int,
        layoutManager: NSLayoutManager,
        containerOrigin: NSPoint,
        lastLineRect: NSRect?
    ) {
        guard fullText.length > 0 && fullText.hasSuffix("\n") else { return }

        let totalLineCount = fullText.components(separatedBy: "\n").count
        let lastLineNumber = totalLineCount

        guard selectedLineNumber == lastLineNumber else { return }

        var lineY: CGFloat

        if let lastRect = lastLineRect {
            lineY = lastRect.maxY + containerOrigin.y - (textView?.visibleRect.origin.y ?? 0)
        } else if fullText.length > 0 {
            let lastCharIndex = max(0, fullText.length - 2)
            let lastGlyphIndex = layoutManager.glyphIndexForCharacter(at: lastCharIndex)
            if lastGlyphIndex < layoutManager.numberOfGlyphs {
                let rect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyphIndex, effectiveRange: nil)
                lineY = rect.maxY + containerOrigin.y - (textView?.visibleRect.origin.y ?? 0)
            } else {
                lineY = containerOrigin.y - (textView?.visibleRect.origin.y ?? 0)
            }
        } else {
            lineY = containerOrigin.y - (textView?.visibleRect.origin.y ?? 0)
        }

        guard let textView else { return }
       let textContainerInset = textView.textContainerInset
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
}
