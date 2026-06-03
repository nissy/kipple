//
//  LiveEditorTextView.swift
//  Kipple
//
//  Created by Codex on 2026/05/31.
//

import AppKit

final class LiveEditorTextView: NSTextView {
    var onDisplayModeDoubleClick: (() -> Void)?
    var onEscape: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if !isEditable, event.clickCount >= 2 {
            onDisplayModeDoubleClick?()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.window?.makeFirstResponder(self)
            }
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isEditable, event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
