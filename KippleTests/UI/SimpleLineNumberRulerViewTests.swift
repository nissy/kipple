//
//  SimpleLineNumberRulerViewTests.swift
//  KippleTests
//

import XCTest
import AppKit
@testable import Kipple

@MainActor
final class SimpleLineNumberRulerViewTests: XCTestCase {
    func testDrawSelectedLineBackgroundSkipsWhenTextContainerMissing() {
        let textView = NilTextContainerTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let layoutManager = RecordingLayoutManager()
        let rulerView = SimpleLineNumberRulerView(textView: textView)
        let fullText: NSString = "line1\nline2"

        rulerView.drawSelectedLineBackground(
            textView: textView,
            layoutManager: layoutManager,
            fullText: fullText,
            selectedLineNumber: 1
        )

        XCTAssertFalse(layoutManager.didRequestGlyphRange)
    }
}

private final class NilTextContainerTextView: NSTextView {
    override var textContainer: NSTextContainer? {
        get { nil }
        set { }
    }
}

private final class RecordingLayoutManager: NSLayoutManager {
    private(set) var didRequestGlyphRange = false

    override func glyphRange(forBoundingRect bounds: NSRect, in container: NSTextContainer) -> NSRange {
        didRequestGlyphRange = true
        return NSRange(location: 0, length: 0)
    }
}
