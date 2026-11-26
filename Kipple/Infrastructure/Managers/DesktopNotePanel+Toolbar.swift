import AppKit
import SwiftUI

extension DesktopNotePanel {
    private static let toolbarSpacing: CGFloat = 4
    private static let closeButtonInset: CGFloat = 10
    private static let closeButtonGap: CGFloat = 8
    private static let spaceForCloseButton = KippleButtonMetrics.compactIconSize + closeButtonGap + closeButtonInset
    private static let copyImage = makeCopyImage("doc.on.doc")
    private static let copiedImage = makeCopyImage("checkmark", tint: .controlAccentColor)

    func installColorStrip(in view: NSView) {
        colorStrip.wantsLayer = true
        selectedColor = DesktopNoteColor.palette.randomElement() ?? .yellow
        colorStrip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(colorStrip)
        NSLayoutConstraint.activate([
            colorStrip.leftAnchor.constraint(equalTo: view.leftAnchor),
            colorStrip.topAnchor.constraint(equalTo: view.topAnchor),
            colorStrip.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            colorStrip.widthAnchor.constraint(equalToConstant: 7)
        ])
    }

    func installControls(in view: NSView, for item: ClipItem) {
        let tools = noteContentController.makeButton(
            "ellipsis.circle", labelKey: "editor.editTools", target: self, action: #selector(showEditorTools(_:))
        )
        tools.refusesFirstResponder = true
        tools.isHidden = true
        editorToolsButton = tools
        controls.append(contentsOf: [tools, noteContentController.remoteImagesButton])
        installCategoryControl(for: item)
        let copy = noteContentController.makeButton(
            "doc.on.doc", labelKey: "Copy", titleKey: "Copy", target: self, action: #selector(copyNote)
        )
        copy.image = Self.copyImage
        copyButton = copy
        let palette = noteContentController.makeButton(
            "paintpalette", labelKey: "Desktop Note Color", titleKey: "Note Color", target: self, action: #selector(showColors(_:))
        )
        paletteButton = palette
        let format = noteContentController.makeButton(
            "chevron.left.forwardslash.chevron.right",
            labelKey: "Show Markdown",
            titleKey: "Toggle Display",
            target: self,
            action: #selector(toggleDisplayMode)
        )
        displayModeButton = format
        updateDisplayModeButton()
        let close = noteContentController.makeButton(
            "xmark", labelKey: "Remove Desktop Note", target: self, action: #selector(performClose(_:))
        )
        close.title = ""
        close.imagePosition = .imageOnly
        closeButton = close
        controls.insert(contentsOf: [copy, palette, format], at: 0)
        if onSave != nil {
            let edit = noteContentController.makeButton(
                "square.and.pencil", labelKey: "editor.mode.startEditing", titleKey: "editor.mode.editing",
                target: self, action: #selector(beginEditing)
            )
            editButton = edit
            controls.insert(edit, at: 1)
        }
        placeControls(in: view, closeButton: close)
        updateControlLabels()
    }

    private func installCategoryControl(for item: ClipItem) {
        if let onChangeCategory {
            let menu = DesktopNoteCategoryMenu(item: item, onChangeCategory: onChangeCategory) { [weak self] in
                guard let self else { return }
                CategoryManagerWindowCoordinator.shared.open(relativeTo: self)
            }
            let control = NSHostingView(rootView: menu)
            control.sizingOptions = .intrinsicContentSize
            control.translatesAutoresizingMaskIntoConstraints = false
            control.heightAnchor.constraint(equalToConstant: MainViewMetrics.HistoryColumns.controlColumnWidth).isActive = true
            categoryControl = control
            controls.append(control)
        }
    }

    private func placeControls(in view: NSView, closeButton close: NSButton) {
        let stack = NSStackView(views: controls)
        stack.spacing = Self.toolbarSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(close)
        controls.append(close)
        NSLayoutConstraint.activate([
            close.centerYAnchor.constraint(equalTo: stack.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.closeButtonInset),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: HistoryItemPreviewContent.contentPadding),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -Self.closeButtonGap),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
        ])
    }

    var minimumToolbarWidth: CGFloat {
        let visible = controls.filter { !$0.isHidden && $0 !== closeButton }
        let buttons = visible.reduce(CGFloat.zero) { width, control in
            let size = control === categoryControl
                ? MainViewMetrics.HistoryColumns.rowCategoryWidth : KippleButtonMetrics.compactIconSize
            return width + size
        }
        let spacing = CGFloat(max(visible.count - 1, 0)) * Self.toolbarSpacing
        return HistoryItemPreviewContent.contentPadding + buttons + spacing + Self.spaceForCloseButton
    }

    func updateControlLabels() {
        let includesEdit = editButton?.isHidden == false
        let baseWidth: CGFloat = categoryControl == nil ? 250 : 320
        let editSpace = includesEdit ? Self.toolbarItemSpace : 0
        let imageSpace = includesEdit && !noteContentController.remoteImagesButton.isHidden ? Self.toolbarItemSpace : 0
        let showsTitle = frame.width >= baseWidth + editSpace + imageSpace + Self.spaceForCloseButton
        for button in [copyButton, editButton, paletteButton, displayModeButton] {
            button?.imagePosition = showsTitle ? .imageLeading : .imageOnly
        }
        if let categoryControl, categoryControl.rootView.showsTitle != showsTitle {
            categoryControl.rootView.showsTitle = showsTitle
            categoryControl.invalidateIntrinsicContentSize()
        }
    }

    @objc func copyNote() {
        guard editor == nil else { return }
        clearCopyFeedback()
        let request = UUID()
        latestCopyRequest = request
        copyItem(noteContentController.hostingController.rootView.item) { [weak self] in
            guard let self, latestCopyRequest == request, isVisible else { return }
            setCopyFeedback(true)
            copyFeedbackTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, latestCopyRequest == request else { return }
                clearCopyFeedback()
            }
        }
    }

    func clearCopyFeedback() {
        copyFeedbackTask?.cancel()
        copyFeedbackTask = nil
        latestCopyRequest = nil
        setCopyFeedback(false)
    }

    private func setCopyFeedback(_ copied: Bool) {
        guard let copyButton else { return }
        copyButton.image = copied ? Self.copiedImage : Self.copyImage
        copyButton.setAccessibilityValue(copied ? AppSettings.shared.localizedString("Copied to clipboard") : nil)
    }

    private static func makeCopyImage(_ symbol: String, tint: NSColor? = nil) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        // A shared canvas keeps the button width stable when the glyph changes.
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { bounds in
            let size = glyph.size
            glyph.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                       from: .zero, operation: .sourceOver, fraction: 1)
            if let tint {
                tint.setFill()
                bounds.fill(using: .sourceIn)
            }
            return true
        }
        image.isTemplate = tint == nil
        return image
    }

    @objc private func toggleDisplayMode() {
        if editor != nil {
            changeDisplayModeAfterSave = true
            saveEditing()
            return
        }
        flipDisplayMode()
        reloadPreview(for: noteContentController.hostingController.rootView.item)
    }

    func flipDisplayMode() {
        displayMode = displayMode == .plainText ? .markdown : .plainText
        updateDisplayModeButton()
    }

    private func updateDisplayModeButton() {
        let isMarkdown = displayMode == .markdown
        let label = AppSettings.shared.localizedString(isMarkdown ? "Show Plain Text" : "Show Markdown")
        displayModeButton?.contentTintColor = isMarkdown ? .controlAccentColor : .secondaryLabelColor
        displayModeButton?.toolTip = label
        displayModeButton?.setAccessibilityLabel(label)
    }

    @objc private func showColors(_ sender: NSButton) {
        let menu = noteContentController.makeColorMenu(selected: selectedColor, target: self, action: #selector(changeColor(_:)))
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY), in: sender)
    }

    @objc private func showEditorTools(_ sender: NSButton) {
        guard let editor, !isSaving else { return }
        let menu = editor.makeToolsMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY), in: sender)
    }

    @objc private func changeColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let color = DesktopNoteColor(rawValue: key) else { return }
        selectedColor = color
        onPlacementChange?()
    }
}
