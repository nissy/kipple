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
            return cachedLineCount(for: fullText)
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
        let extendedGlyphRange = extendedVisibleGlyphRange(
            layoutManager: layoutManager,
            visibleGlyphRange: visibleGlyphRange
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

        if !state.didDrawSelectedLine {
            drawEmptyLogicalLineHighlightIfNeeded(
                fullText: highlightInput.fullText,
                selectedLineNumber: highlightInput.selectedLineNumber,
                layoutManager: layoutManager,
                containerOrigin: highlightInput.containerOrigin,
                visibleRect: highlightInput.visibleRect,
                lastLineRect: state.lastLineRect
            )
        }
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
            lastLineRect: nil,
            didDrawSelectedLine: false
        )

        layoutManager.enumerateLineFragments(forGlyphRange: input.extendedGlyphRange) { lineRect, _, _, glyphRange, _ in
            let characterRange = layoutManager.characterRange(
                forGlyphRange: glyphRange,
                actualGlyphRange: nil
            )
            let fragmentLineNumber = SimpleLineNumberRulerView.countLines(
                in: input.fullText,
                upTo: characterRange.location
            )

            if fragmentLineNumber == input.selectedLineNumber {
                let lineY = lineRect.origin.y + input.containerOrigin.y - input.visibleRect.origin.y
                let textContainerInset = textView.textContainerInset
                self.drawCurrentLineHighlight(
                    y: lineY + textContainerInset.height,
                    height: max(self.fixedLineHeight - textContainerInset.height * 2, 1)
                )
                state.didDrawSelectedLine = true
            }

            state.currentLineNumber = fragmentLineNumber +
                self.highlightNewlineCount(in: characterRange, fullText: input.fullText)
            state.lastLineRect = lineRect
            state.lastLineProcessed = state.currentLineNumber
        }

        return state
    }

    func drawCurrentLineHighlight(y: CGFloat, height: CGFloat) {
        NSColor.systemYellow.withAlphaComponent(0.42).set()
        let path = NSBezierPath(rect: NSRect(
            x: 0,
            y: y,
            width: ruleThickness,
            height: max(height, 1)
        ))
        path.fill()
    }

    func highlightNewlineCount(in characterRange: NSRange, fullText: NSString) -> Int {
        guard characterRange.location < fullText.length else {
            return 0
        }

        let safeLength = min(characterRange.length, fullText.length - characterRange.location)
        guard safeLength > 0 else {
            return 0
        }

        let lineText = fullText.substring(
            with: NSRange(location: characterRange.location, length: safeLength)
        ) as NSString
        var count = 0
        var searchRange = NSRange(location: 0, length: lineText.length)
        while searchRange.length > 0 {
            let foundRange = lineText.range(of: "\n", options: [], range: searchRange)
            guard foundRange.location != NSNotFound else {
                break
            }
            count += 1
            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = lineText.length - searchRange.location
        }
        return count
    }

    func drawEmptyLogicalLineHighlightIfNeeded(
        fullText: NSString,
        selectedLineNumber: Int,
        layoutManager: NSLayoutManager,
        containerOrigin: NSPoint,
        visibleRect: NSRect,
        lastLineRect: NSRect?
    ) {
        guard let lineStartLocation = lineStartLocation(
            forLineNumber: selectedLineNumber,
            in: fullText
        ), isEmptyLogicalLine(startLocation: lineStartLocation, fullText: fullText) else {
            return
        }

        let lineY = emptyLogicalLineY(
            lineStartLocation: lineStartLocation,
            fullText: fullText,
            layoutManager: layoutManager,
            containerOrigin: containerOrigin,
            visibleRect: visibleRect,
            lastLineRect: lastLineRect
        )

        drawCurrentLineHighlight(
            y: lineY,
            height: fixedLineHeight
        )
    }

    func lineStartLocation(forLineNumber lineNumber: Int, in fullText: NSString) -> Int? {
        guard lineNumber >= 1 else { return nil }
        guard lineNumber > 1 else { return 0 }

        var currentLineNumber = 1
        var searchRange = NSRange(location: 0, length: fullText.length)

        while searchRange.length > 0 {
            let foundRange = fullText.range(of: "\n", options: [], range: searchRange)
            guard foundRange.location != NSNotFound else {
                return nil
            }

            currentLineNumber += 1
            if currentLineNumber == lineNumber {
                return foundRange.location + foundRange.length
            }

            searchRange.location = foundRange.location + foundRange.length
            searchRange.length = fullText.length - searchRange.location
        }

        return nil
    }

    func isEmptyLogicalLine(startLocation: Int, fullText: NSString) -> Bool {
        guard startLocation < fullText.length else {
            return true
        }

        let firstCharacter = fullText.substring(
            with: NSRange(location: startLocation, length: 1)
        )
        return firstCharacter == "\n"
    }

    func emptyLogicalLineY(
        lineStartLocation: Int,
        fullText: NSString,
        layoutManager: NSLayoutManager,
        containerOrigin: NSPoint,
        visibleRect: NSRect,
        lastLineRect: NSRect?
    ) -> CGFloat {
        guard layoutManager.numberOfGlyphs > 0 else {
            return containerOrigin.y - visibleRect.origin.y
        }

        if lineStartLocation == 0 {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: 0)
            guard glyphIndex < layoutManager.numberOfGlyphs else {
                return containerOrigin.y - visibleRect.origin.y
            }
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            return rect.origin.y + containerOrigin.y - visibleRect.origin.y
        }

        let previousCharacterIndex = min(lineStartLocation - 1, fullText.length - 1)
        let previousGlyphIndex = layoutManager.glyphIndexForCharacter(at: previousCharacterIndex)
        guard previousGlyphIndex < layoutManager.numberOfGlyphs else {
            if let lastLineRect {
                return lastLineRect.maxY + containerOrigin.y - visibleRect.origin.y
            }
            return containerOrigin.y - visibleRect.origin.y
        }

        let previousRect = layoutManager.lineFragmentRect(forGlyphAt: previousGlyphIndex, effectiveRange: nil)
        return previousRect.maxY + containerOrigin.y - visibleRect.origin.y
    }
}
