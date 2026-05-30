//
//  LiveEditorTextView.swift
//  Kipple
//
//  Created by Codex on 2026/05/31.
//

import AppKit

final class LiveEditorTextView: NSTextView {
    private static var localClipboard: String?

    static func clearLocalClipboard() {
        localClipboard = nil
    }

    override func copy(_ sender: Any?) {
        copySelectionToLocalClipboard()
    }

    override func cut(_ sender: Any?) {
        let selectedRange = selectedRange()
        guard selectedRange.length > 0 else { return }

        copySelectionToLocalClipboard()
        replaceText(in: selectedRange, with: "")
    }

    override func paste(_ sender: Any?) {
        guard let localClipboard = Self.localClipboard else { return }

        replaceText(in: selectedRange(), with: localClipboard)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    override func pasteAsRichText(_ sender: Any?) {
        paste(sender)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }

        menu.items
            .filter { shouldRemoveContextMenuItem($0) }
            .forEach { menu.removeItem($0) }

        removeRedundantSeparators(from: menu)
        return menu
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(NSText.copy(_:)), #selector(NSText.cut(_:)):
            return selectedRange().length > 0
        case #selector(NSText.paste(_:)),
            #selector(NSTextView.pasteAsPlainText(_:)),
            #selector(NSTextView.pasteAsRichText(_:)):
            return Self.localClipboard != nil
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    private func copySelectionToLocalClipboard() {
        let selectedRange = selectedRange()
        guard selectedRange.length > 0 else { return }

        let text = string as NSString
        guard NSMaxRange(selectedRange) <= text.length else { return }

        Self.localClipboard = text.substring(with: selectedRange)
    }

    private func replaceText(in range: NSRange, with replacement: String) {
        guard NSMaxRange(range) <= (string as NSString).length,
              shouldChangeText(in: range, replacementString: replacement) else { return }

        let attributedString = NSAttributedString(
            string: replacement,
            attributes: typingAttributes
        )
        textStorage?.replaceCharacters(in: range, with: attributedString)
        didChangeText()

        let cursorLocation = range.location + (replacement as NSString).length
        setSelectedRange(NSRange(location: cursorLocation, length: 0))
    }

    private func shouldRemoveContextMenuItem(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return false }

        return action == #selector(NSText.copy(_:)) ||
            action == #selector(NSText.cut(_:)) ||
            action == #selector(NSText.paste(_:)) ||
            action == #selector(NSTextView.pasteAsPlainText(_:)) ||
            action == #selector(NSTextView.pasteAsRichText(_:))
    }

    private func removeRedundantSeparators(from menu: NSMenu) {
        for item in menu.items.reversed() where item.isSeparatorItem {
            guard let index = menu.items.firstIndex(of: item) else { continue }
            let previousIsSeparator = index == 0 || menu.items[index - 1].isSeparatorItem
            let nextIsSeparator = index == menu.items.count - 1 || menu.items[index + 1].isSeparatorItem
            if previousIsSeparator || nextIsSeparator {
                menu.removeItem(item)
            }
        }
    }
}
