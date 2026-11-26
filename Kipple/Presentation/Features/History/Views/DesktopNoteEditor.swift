import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class DesktopNoteEditor: NSObject {
    private static let spacing: CGFloat = 6
    private static let toolbarGap: CGFloat = 8
    private static let titleHeight: CGFloat = 26
    private static let errorHeight: CGFloat = 28

    let originalText: String
    let view: NSStackView
    let textView: LiveEditorTextView
    let titleField: NSTextField
    private let originalTitle: String
    private let onSave: () -> Void
    private let coordinator: SimpleLineNumberCoordinator
    private let actionsView: NSHostingView<DesktopNoteEditActions>
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var topConstraint: NSLayoutConstraint?
    private var asksToSaveAsPlainText = false

    var additionalHeight: CGFloat {
        let fieldsAndActions = Self.titleHeight + DesktopNoteEditActions.height + 2 * Self.spacing + Self.toolbarGap
        return fieldsAndActions + (errorLabel.isHidden ? 0 : Self.errorHeight + Self.spacing)
    }

    var isConfirmingPlainTextSave: Bool { asksToSaveAsPlainText && !errorLabel.isHidden }
    var hasMarkedText: Bool { textView.hasMarkedText() || titleEditor?.hasMarkedText() == true }
    var editedTitle: String? {
        let title = titleEditor?.string ?? titleField.stringValue
        return title == originalTitle ? nil : title
    }
    var editedText: String? { textView.string == originalText ? nil : textView.string }
    private var titleEditor: NSTextView? { titleField.currentEditor() as? NSTextView }

    init(title: String?, text: String, onCancel: @escaping () -> Void, onSave: @escaping () -> Void) {
        let editor = SimpleLineNumberView(
            text: .constant(text), font: FontManager.shared.editorFont, isEditable: true,
            onDoubleClick: nil, onEscape: nil, textColor: .textColor, onScrollChange: nil
        )
        let coordinator = editor.makeCoordinator()
        let (scroll, textView) = editor.makeEditor(using: coordinator)
        originalTitle = title ?? ""
        originalText = text
        titleField = NSTextField(string: title ?? "")
        self.textView = textView
        self.onSave = onSave
        self.coordinator = coordinator
        actionsView = NSHostingView(rootView: DesktopNoteEditActions(onCancel: onCancel, onSave: onSave))
        scroll.scrollerStyle = .overlay
        textView.setAccessibilityLabel(AppSettings.shared.localizedString("Content"))
        titleField.placeholderString = AppSettings.shared.localizedString("Title")
        titleField.setAccessibilityLabel(titleField.placeholderString)
        titleField.bezelStyle = .roundedBezel
        titleField.usesSingleLineMode = true
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleField.heightAnchor.constraint(equalToConstant: Self.titleHeight).isActive = true

        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.maximumNumberOfLines = 2
        errorLabel.isHidden = true
        errorLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let scrollContainer = NSView()
        scrollContainer.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: scrollContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: scrollContainer.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: scrollContainer.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: scrollContainer.bottomAnchor)
        ])
        view = NSStackView(views: [titleField, scrollContainer, errorLabel, actionsView])
        super.init()
        titleField.target = self
        titleField.action = #selector(focusBody)
        titleField.nextKeyView = textView
        view.orientation = .vertical
        view.alignment = .width
        view.spacing = Self.spacing
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    func install(in container: NSView, headerHeight: CGFloat) {
        let padding = HistoryItemPreviewContent.contentPadding
        container.addSubview(view)
        let top = view.topAnchor.constraint(equalTo: container.topAnchor, constant: headerHeight)
        topConstraint = top
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            top,
            view.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -(DesktopNoteContent.controlsHeight + Self.toolbarGap)
            )
        ])
    }

    func updateHeader(height: CGFloat) {
        topConstraint?.constant = height
    }

    func setSaving(_ isSaving: Bool) {
        titleField.isEditable = !isSaving
        textView.isEditable = !isSaving
        actionsView.rootView.isSaving = isSaving
    }

    func commitTextInput() {
        titleEditor?.unmarkText()
        titleField.validateEditing()
        textView.unmarkText()
    }

    @objc private func focusBody() {
        titleField.window?.makeFirstResponder(textView)
    }

    func focus(in window: NSWindow, scrollProgress: CGFloat) {
        window.makeFirstResponder(textView)
        let index = scrollProgress > 0 ? scrollTo(progress: scrollProgress) : 0
        let offset = max(0, min(index, originalText.utf16.count))
        let range = NSRange(location: offset, length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    private func scrollTo(progress: CGFloat) -> Int {
        guard let scroll = textView.enclosingScrollView, let container = textView.textContainer else { return 0 }
        textView.layoutManager?.ensureLayout(for: container)
        scroll.layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        let document = clip.documentRect
        let offset = document.minY + progress * max(0, document.height - clip.bounds.height)
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: offset))
        scroll.reflectScrolledClipView(clip)
        let point = NSPoint(x: textView.textContainerOrigin.x, y: clip.documentVisibleRect.minY + 1)
        return textView.characterIndexForInsertion(at: point)
    }

    func handleShortcut(_ event: NSEvent) -> Bool {
        switch AppSettings.shared.editorHotkey(for: event) {
        case .save:
            onSave()
        case .clear:
            guard titleEditor == nil else { return false }
            clear()
        case nil:
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard modifiers == .command,
                  event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter else { return false }
            onSave()
        }
        return true
    }

    func makeToolsMenu() -> NSMenu {
        let menu = NSMenu()
        addTool("editor.trim", action: #selector(trim), to: menu)
        for format in ClipboardTextFormat.allCases {
            let item = addTool("editor.format.\(format.rawValue)", action: #selector(formatText(_:)), to: menu)
            item.representedObject = format.rawValue
        }
        menu.addItem(.separator())
        addTool("Clear", action: #selector(clear), to: menu)
        return menu
    }

    func showError(_ message: String) {
        asksToSaveAsPlainText = false
        errorLabel.stringValue = message
        errorLabel.toolTip = message
        errorLabel.isHidden = false
    }

    func showSaveError(_ error: Error) {
        showError(AppSettings.shared.localizedString(clipItemEditErrorMessage(error)))
        if case .richTextLossRequiresConfirmation = error as? ClipItemEditError {
            asksToSaveAsPlainText = true
        }
    }

    @discardableResult
    private func addTool(_ key: String, action: Selector, to menu: NSMenu) -> NSMenuItem {
        let title = AppSettings.shared.localizedString(key)
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func trim() {
        textView.unmarkText()
        replaceText(with: textView.string.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @objc private func formatText(_ item: NSMenuItem) {
        guard let key = item.representedObject as? String, let format = ClipboardTextFormat(rawValue: key) else { return }
        textView.unmarkText()
        do {
            replaceText(with: try ClipboardTextFormatter.format(textView.string, as: format))
        } catch {
            let detail = (error as? ClipboardTextFormatter.FormatError)?.detail ?? error.localizedDescription
            let message = AppSettings.shared.localizedString("editor.format.error.invalid")
            showError(String(format: message, format.localizedName, detail))
        }
    }

    @objc private func clear() {
        textView.unmarkText()
        replaceText(with: "")
    }

    private func replaceText(with text: String) {
        errorLabel.isHidden = true
        guard textView.isEditable, text != textView.string else { return }
        let range = NSRange(location: 0, length: textView.attributedString().length)
        textView.breakUndoCoalescing()
        _ = textView.performValidatedReplacement(in: range, with: NSAttributedString(string: text))
        textView.breakUndoCoalescing()
    }
}

private struct DesktopNoteEditActions: View {
    static let height: CGFloat = 28

    let onCancel: () -> Void
    let onSave: () -> Void
    var isSaving = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Button("Cancel", action: onCancel)
                .buttonStyle(style(
                    fill: colorScheme == .dark ? .white.opacity(0.055) : Color(nsColor: .textBackgroundColor),
                    foreground: .primary,
                    border: .primary.opacity(0.17)
                ))
            Button("Save", action: onSave)
                .buttonStyle(style(fill: ClipEditorButtonStyle.accent, foreground: .white, border: .clear))
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .trailing)
        .disabled(isSaving)
        .environment(\.locale, AppSettings.shared.appLocale)
    }

    private func style(fill: Color, foreground: Color, border: Color) -> ClipEditorButtonStyle {
        ClipEditorButtonStyle(fill: fill, foreground: foreground, border: border, horizontalPadding: 8, height: Self.height)
    }
}
