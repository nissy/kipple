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

    private var lastSelectedLine: Int = 1
    var cachedLineCount: Int = 0
    var cachedTextLength: Int = 0

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
}
