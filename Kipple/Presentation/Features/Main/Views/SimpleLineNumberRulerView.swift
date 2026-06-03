//
//  SimpleLineNumberRulerView.swift
//  Kipple
//
//  Created by Codex on 2025/09/23.
//

import AppKit

final class SimpleLineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    var fixedLineHeight: CGFloat = 20
    var backgroundColor: NSColor = .controlBackgroundColor {
        didSet {
            needsDisplay = true
        }
    }

    private var lastSelectedLine: Int = 1
    var cachedLineCount: Int = 0
    var cachedTextLength: Int = 0
    private let glyphRangePadding = 1000

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        ruleThickness = 40
        clientView = textView
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func extendedVisibleGlyphRange(
        layoutManager: NSLayoutManager,
        visibleGlyphRange: NSRange
    ) -> NSRange {
        let glyphCount = layoutManager.numberOfGlyphs
        guard glyphCount > 0 else {
            return NSRange(location: 0, length: 0)
        }

        let start = max(0, visibleGlyphRange.location - glyphRangePadding)
        let visibleEnd = min(glyphCount, visibleGlyphRange.location + visibleGlyphRange.length)
        let end = min(glyphCount, visibleEnd + glyphRangePadding)
        return NSRange(location: start, length: max(0, end - start))
    }

    func cachedLineCount(for string: NSString) -> Int {
        cachedLineCount = Self.countLines(in: string)
        cachedTextLength = string.length
        return cachedLineCount
    }
}
