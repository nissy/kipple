//
//  SimpleLineNumberSupport.swift
//  Kipple
//
//  Created by Codex on 2025/09/23.
//

import AppKit

struct LineNumberDrawingContext {
    let textView: NSTextView
    let layoutManager: NSLayoutManager
    let textContainer: NSTextContainer
    let fullText: NSString
    let textAttributes: [NSAttributedString.Key: Any]
    let rect: NSRect
    let fontSize: CGFloat
}

/// Parameters used when rendering individual line numbers.
struct DrawLineNumberParams {
    let lineRect: NSRect
    let glyphRange: NSRange
    var currentLineNumber: Int
    let lineNumberFont: NSFont
    let visibleRect: NSRect
    let containerOrigin: NSPoint
    let textContainerInset: NSSize
    var previousCharacterLocation: Int = -1
}

/// State container tracked while highlighting the currently selected line.
struct SelectedLineHighlightState {
    var currentLineNumber: Int
    var lastLineProcessed: Int
    var lastLineRect: NSRect?
}

struct SelectedLineHighlightInput {
    let fullText: NSString
    let selectedLineNumber: Int
    let containerOrigin: NSPoint
    let visibleRect: NSRect
    let extendedGlyphRange: NSRange
    let initialLineNumber: Int
}

struct LineNumberRenderingOptions {
    let extendedGlyphRange: NSRange
    let lineNumberFont: NSFont
    let visibleRect: NSRect
    let containerOrigin: NSPoint
    let textContainerInset: NSSize
    let initialLineNumber: Int
}

// MARK: - Metrics

func calculateFixedLineHeight(for font: NSFont) -> CGFloat {
    let layoutSettings = FontManager.currentEditorLayoutSettings()

    var maxHeight = font.ascender - font.descender

    let japaneseTestFonts = ["HiraginoSans-W3", "YuGothic-Medium", "NotoSansCJK-Regular"]
    for fontName in japaneseTestFonts {
        if let japaneseFont = NSFont(name: fontName, size: font.pointSize) {
            let height = japaneseFont.ascender - japaneseFont.descender
            maxHeight = max(maxHeight, height)
        }
    }

    let testStrings = ["Ag", "あg", "漢字", "ÄÖÜ"]
    for testString in testStrings {
        let attributedString = NSAttributedString(string: testString, attributes: [.font: font])
        let size = attributedString.size()
        maxHeight = max(maxHeight, size.height)
    }

    let recommendedHeight = maxHeight * layoutSettings.lineHeightMultiplier
    let minimumHeight = font.pointSize * layoutSettings.minimumLineHeightMultiplier

    return ceil(max(recommendedHeight, minimumHeight) * 1.1)
}
