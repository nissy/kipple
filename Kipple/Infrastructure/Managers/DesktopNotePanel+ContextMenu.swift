import AppKit

extension DesktopNotePanel {
    static let contextClickMonitor = NSEvent.addLocalMonitorForEvents(
        matching: [.rightMouseDown, .leftMouseDown]
    ) { event in
        guard isContextClick(event), !(event.window is DesktopNotePanel) else { return event }
        // Context clicks can arrive without the note as their event window.
        let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        guard let (note, location) = noteUnderPointer(at: point),
              let click = note.contextEvent(event, at: location) else { return event }
        note.handleContextClick(click)
        return nil
    }

    static func isContextClick(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }

    func handleContextClick(_ event: NSEvent) {
        guard !showingContextMenu else { return }
        cancelSourceLinkOpen()
        cancelPointerGesture()
        clearPointerCursor()
        showingContextMenu = true
        defer {
            showingContextMenu = false
            Self.refreshPointerCursorAfterTracking()
        }

        if let context = contextMenu(for: event) {
            let location = context.view.convert(event.locationInWindow, from: nil)
            context.menu.popUp(positioning: nil, at: location, in: context.view)
        }
    }

    func contextMenu(for event: NSEvent) -> (menu: NSMenu, view: NSView)? {
        let point = event.locationInWindow
        guard let contentView else { return nil }
        if let menu = sourceLinkMenu(at: point) { return (menu, contentView) }
        if let editor {
            if isPoint(point, in: editor.titleField) {
                guard editor.titleField.currentEditor() != nil || makeFirstResponder(editor.titleField),
                      let fieldEditor = editor.titleField.currentEditor() as? NSTextView else { return nil }
                return editorContextMenu(in: fieldEditor)
            }
            let location = editor.textView.convert(point, from: nil)
            return editor.textView.visibleRect.contains(location) ? editorContextMenu(in: editor.textView) : nil
        }
        guard initialPointerGesture(at: point) != nil else { return nil }
        let menu = automaticSizeMenu(at: point) ?? NSMenu()
        // Textual and AppKit may select the clicked word while building their contextual menus.
        addSelectionCopy(to: menu)
        addCopyNoteItem(to: menu)
        return (menu, contentView)
    }

    private func editorContextMenu(in textView: NSTextView) -> (menu: NSMenu, view: NSView)? {
        guard let menu = NSTextView.defaultMenu?.copy() as? NSMenu else { return nil }
        for item in menu.items where item.target == nil {
            if let action = item.action, textView.responds(to: action) { item.target = textView }
        }
        return (menu, textView)
    }

    private func addSelectionCopy(to menu: NSMenu) {
        let action = #selector(NSText.copy(_:))
        guard noteContentController.selectionMayExist, let view = firstResponder as? NSView,
              view.window === self, view.responds(to: action) else { return }
        let title = AppSettings.shared.localizedString("Copy")
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if let target = view as? NSUserInterfaceValidations, !target.validateUserInterfaceItem(item) { return }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        item.target = view
        menu.addItem(item)
    }

    private func addCopyNoteItem(to menu: NSMenu) {
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let title = AppSettings.shared.localizedString("Copy Entire Note")
        menu.addItem(withTitle: title, action: #selector(copyNote), keyEquivalent: "").target = self
    }

    private func contextEvent(_ event: NSEvent, at point: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: .rightMouseDown, location: point, modifierFlags: event.modifierFlags,
            timestamp: event.timestamp, windowNumber: windowNumber, context: nil,
            eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure
        )
    }

    func automaticSizeMenu(at point: NSPoint) -> NSMenu? {
        guard editor == nil, manualSize != nil, case .move = initialPointerGesture(at: point) else { return nil }
        let menu = NSMenu()
        let title = AppSettings.shared.localizedString("Fit Note to Content")
        menu.addItem(withTitle: title, action: #selector(fitNoteToContent), keyEquivalent: "").target = self
        return menu
    }

    private func sourceLinkMenu(at point: NSPoint) -> NSMenu? {
        guard let url = sourceWebURL(at: point) else { return nil }
        let menu = NSMenu()
        if editor == nil { addSelectionCopy(to: menu) }
        let title = AppSettings.shared.localizedString("Copy URL")
        let item = menu.addItem(withTitle: title, action: #selector(copySourceURL(_:)), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
        item.representedObject = url.absoluteString
        return menu
    }

    @objc private func copySourceURL(_ sender: NSMenuItem) {
        guard let address = sender.representedObject as? String else { return }
        noteContentController.hostingController.rootView.copyLink(address)
    }

    @objc private func fitNoteToContent() {
        guard editor == nil, manualSize != nil else { return }
        manualSize = nil
        reloadPreview(for: noteContentController.hostingController.rootView.item)
    }
}
