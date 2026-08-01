//
//  SimpleLineNumberRulerViewTests.swift
//  KippleTests
//

import XCTest
import AppKit
@testable import Kipple

@MainActor
final class SimpleLineNumberRulerViewTests: XCTestCase {
    func testCalculateSelectedLineNumber_空白行のカーソル位置を選択行として返す() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let rulerView = SimpleLineNumberRulerView(textView: textView)
        let fullText: NSString = "one\n\nthree"

        let selectedLineNumber = rulerView.calculateSelectedLineNumber(
            fullText: fullText,
            selectedRange: NSRange(location: 4, length: 0)
        )

        XCTAssertEqual(selectedLineNumber, 2)
    }

    func testEmptyLogicalLine_内部空白行と末尾空白行を判定できる() throws {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let rulerView = SimpleLineNumberRulerView(textView: textView)
        let fullText: NSString = "one\n\nthree\n"

        let internalBlankLineStart = try XCTUnwrap(rulerView.lineStartLocation(forLineNumber: 2, in: fullText))
        let trailingBlankLineStart = try XCTUnwrap(rulerView.lineStartLocation(forLineNumber: 4, in: fullText))

        XCTAssertEqual(internalBlankLineStart, 4)
        XCTAssertEqual(trailingBlankLineStart, 11)
        XCTAssertTrue(rulerView.isEmptyLogicalLine(startLocation: internalBlankLineStart, fullText: fullText))
        XCTAssertTrue(rulerView.isEmptyLogicalLine(startLocation: trailingBlankLineStart, fullText: fullText))
    }

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
