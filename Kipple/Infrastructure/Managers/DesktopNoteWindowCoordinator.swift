import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class DesktopNoteWindowCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = DesktopNoteWindowCoordinator()

    @Published private var notes: [UUID: DesktopNotePanel] = [:]
    private var closingNotes: [UUID: Task<Void, Never>] = [:]
    private let adapter: ModernClipboardServiceAdapter
    private var historyObservation: AnyCancellable?
    private var transparencyObservation: AnyCancellable?

    init(adapter: ModernClipboardServiceAdapter = .shared) {
        self.adapter = adapter
        super.init()
        historyObservation = adapter.$history.sink { [weak self] history in
            self?.updateOpenNotes(from: history)
        }
        let settings = AppSettings.shared
        transparencyObservation = settings.objectWillChange
            .receive(on: RunLoop.main)
            .map { settings.desktopNoteTransparency }
            .removeDuplicates()
            .sink { [weak self] value in
                self?.notes.values.forEach { $0.applyTransparency(value) }
            }
    }

    func isPosted(_ id: UUID) -> Bool {
        notes[id] != nil
    }

    func toggle(_ itemID: UUID, on screen: NSScreen?) async {
        if let note = notes[itemID] {
            if closingNotes[itemID] == nil { note.performClose(nil) }
            await closingNotes[itemID]?.value
            return
        }
        guard let screen = screen ?? NSScreen.main,
              let item = await adapter.protectHistoryForDesktopNote(itemID) else { return }

        let note = DesktopNotePanel(
            item: item,
            screenFrame: screen.visibleFrame,
            displayMode: AppSettings.shared.desktopNoteDefaultDisplayMode,
            onSave: { [adapter] text in
                try await adapter.updateDetails(itemID: itemID, title: nil, content: text, categoryChanges: [:])
            },
            onChangeCategory: { [adapter] change in
                try await adapter.updateCategories(itemID: itemID, change: change)
            }
        )
        note.delegate = self
        note.setFrameOrigin(initialOrigin(for: note.frame.size, in: screen.visibleFrame))
        notes[itemID] = note
        note.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard let note = notification.object as? DesktopNotePanel,
              let id = notes.first(where: { $0.value === note })?.key,
              closingNotes[id] == nil else { return }
        closingNotes[id] = Task { [weak self, adapter] in
            await adapter.removeDesktopNoteProtection(id)
            self?.notes.removeValue(forKey: id)
            self?.closingNotes.removeValue(forKey: id)
        }
    }

    private func updateOpenNotes(from history: [ClipItem]) {
        guard !notes.isEmpty else { return }
        for item in history {
            notes[item.id]?.update(from: item)
        }
    }

    private func initialOrigin(for size: NSSize, in frame: NSRect) -> NSPoint {
        let margin: CGFloat = 24
        let occupied = notes.values.map { NSPoint(x: $0.frame.minX, y: $0.frame.maxY) }
        let positions = (0..<8).map { index in
            let offset = margin * CGFloat(index + 1)
            return NSPoint(
                x: max(frame.minX, min(frame.minX + offset, frame.maxX - size.width)),
                y: max(frame.minY + size.height, frame.maxY - offset)
            )
        }
        let topLeft = positions.first { !occupied.contains($0) } ?? positions[0]
        return NSPoint(x: topLeft.x, y: topLeft.y - size.height)
    }
}

final class DesktopNotePanel: NSPanel {
    private enum PointerGesture {
        case move(start: NSPoint)
        case select(start: NSPoint, didDrag: Bool)
    }

    private static let minimumResizeSize = NSSize(width: 170, height: 120)
    private let glassController: GlassWindowContentController<DesktopNoteContent>
    private let colorStrip = NSView()
    private let initialScreenFrame: NSRect
    private let onSave: ((String) async throws -> Void)?
    private let onChangeCategory: ((ClipCategoryChange) async throws -> Void)?
    private let openLink: (URL) -> Void
    private var categoryControl: NSHostingView<DesktopNoteCategoryMenu>?
    private var displayModeButton: NSButton?
    private var controls: [NSView] = []
    private var displayMode: AppSettings.DesktopNoteDisplayMode
    private var selectedColor = DesktopNoteColor.none
    private let textHitViews = NSHashTable<DesktopNoteTextHitView>.weakObjects()
    private var pointerGesture: PointerGesture?
    private var pendingLink: URL?
    private var manualSize: NSSize?
    private var editor: DesktopNoteEditor?
    private var isSaving = false
    private var closeAfterSave = false
    private var changeDisplayModeAfterSave = false

    override var canBecomeKey: Bool { true }

    init(
        item: ClipItem,
        screenFrame: NSRect,
        displayMode: AppSettings.DesktopNoteDisplayMode = .plainText,
        onSave: ((String) async throws -> Void)? = nil,
        onChangeCategory: ((ClipCategoryChange) async throws -> Void)? = nil,
        openLink: @escaping (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    ) {
        var content = DesktopNoteContent(item: item, displayMode: displayMode)
        let size = Self.contentSize(for: content, screenFrame: screenFrame)
        initialScreenFrame = screenFrame
        self.displayMode = displayMode
        self.onSave = onSave
        self.onChangeCategory = onChangeCategory
        self.openLink = openLink
        glassController = GlassWindowContentController(
            rootView: content,
            cornerRadius: HistoryItemPreviewContent.cornerRadius
        )
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        // Stay above Finder's desktop icons and below regular application windows.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        title = HistoryItemPreviewContent.nonempty(item.title) ?? ""
        titleVisibility = .hidden
        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
        content.openURL = OpenURLAction { [weak self] url in
            guard let self else { return .discarded }
            // Textual can request a link on mouse down. Open it only after a click completes.
            if case .select = self.pointerGesture {
                self.pendingLink = url
            } else {
                self.openLink(url)
            }
            return .handled
        }
        glassController.hostingController.rootView = content
        contentViewController = glassController
        applyTransparency(AppSettings.shared.desktopNoteTransparency)
        setContentSize(size)
        installColorStrip(in: glassController.view)
        installControls(in: glassController.view, for: item)
    }

    func applyTransparency(_ value: Double) {
        glassController.glassOpacity = 1 - value
    }

    func update(from item: ClipItem) {
        if let categoryControl, categoryControl.rootView.item.categoryIDs != item.categoryIDs {
            categoryControl.rootView.item = item
        }
        let previous = glassController.hostingController.rootView.item
        guard item.title != previous.title || item.content != previous.content else { return }
        reloadPreview(for: item)
    }

    private func reloadPreview(for item: ClipItem) {
        var content = DesktopNoteContent(item: item, displayMode: displayMode)
        content.showsBody = editor == nil
        content.openURL = glassController.hostingController.rootView.openURL
        title = HistoryItemPreviewContent.nonempty(item.title) ?? ""
        glassController.hostingController.rootView = content
        if editor == nil { resize(to: manualSize ?? Self.contentSize(for: content, screenFrame: availableFrame)) }
    }

    private var availableFrame: NSRect { screen?.visibleFrame ?? initialScreenFrame }

    private var minimumManualHeight: CGFloat {
        // Reserve space for a title that wraps onto two lines above the document.
        title.isEmpty ? Self.minimumResizeSize.height : Self.minimumResizeSize.height + 40
    }

    private func resize(to requestedSize: NSSize) {
        let screen = availableFrame
        let height = manualSize == nil ? requestedSize.height : max(requestedSize.height, minimumManualHeight)
        let size = NSSize(width: min(requestedSize.width, screen.width), height: min(height, screen.height))
        guard size != frame.size else { return }
        let origin = NSPoint(
            x: min(frame.minX, screen.maxX - size.width),
            y: max(frame.maxY - size.height, screen.minY)
        )
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func resizeFromBottomRight(startFrame: NSRect, displacement: NSPoint) {
        let screen = availableFrame
        let minHeight = minimumManualHeight
        let maxWidth = min(screen.width, max(Self.minimumResizeSize.width, screen.maxX - startFrame.minX))
        let maxHeight = min(screen.height, max(minHeight, startFrame.maxY - screen.minY))
        let width = min(max(startFrame.width + displacement.x, Self.minimumResizeSize.width), maxWidth)
        let height = min(max(startFrame.height - displacement.y, minHeight), maxHeight)
        let size = NSSize(width: width, height: height)
        guard frame.size != size else { return }
        manualSize = size
        resize(to: size)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if handleMouseDown(event) { return }
        case .leftMouseDragged:
            let point = event.locationInWindow
            switch pointerGesture {
            case .move(let start):
                let pointer = convertPoint(toScreen: point)
                setFrameOrigin(NSPoint(x: pointer.x - start.x, y: pointer.y - start.y))
                return
            case let .select(start, didDrag):
                let distance = hypot(point.x - start.x, point.y - start.y)
                pointerGesture = .select(start: start, didDrag: didDrag || distance >= 3)
            case nil:
                break
            }
        case .leftMouseUp:
            if finishPointerGesture(event) { return }
        case .keyDown:
            if editor != nil, handleEditingKey(event) { return }
        default:
            break
        }
        super.sendEvent(event)
    }

    func registerTextHitView(_ view: DesktopNoteTextHitView) {
        textHitViews.add(view)
    }

    private func handleMouseDown(_ event: NSEvent) -> Bool {
        pointerGesture = nil
        pendingLink = nil
        let point = event.locationInWindow
        guard isNoteBody(at: point) else { return false }
        if event.clickCount == 2, editor == nil, onSave != nil {
            beginEditing(at: convertPoint(toScreen: point))
            return true
        }
        if editor == nil, textHitViews.allObjects.contains(where: { $0.containsText(at: point) }) {
            pointerGesture = .select(start: point, didDrag: false)
            if !isKeyWindow { makeKey() }
            return false
        }
        pointerGesture = .move(start: point)
        return true
    }

    private func finishPointerGesture(_ event: NSEvent) -> Bool {
        guard let pointerGesture else { return false }
        if case .select(_, let didDrag) = pointerGesture {
            super.sendEvent(event)
            let link = didDrag ? nil : pendingLink
            self.pointerGesture = nil
            pendingLink = nil
            if let link { openLink(link) }
        } else {
            self.pointerGesture = nil
        }
        return true
    }

    override func performClose(_ sender: Any?) {
        if editor == nil {
            close()
        } else {
            closeAfterSave = true
            saveEditing()
        }
    }

    override func resignKey() {
        super.resignKey()
        saveEditing()
    }

    private func isNoteBody(at point: NSPoint) -> Bool {
        guard let contentView else { return false }
        let location = contentView.convert(point, from: nil)
        guard contentView.bounds.contains(location), !(contentView.hitTest(location) is NSScroller) else { return false }
        let interactiveViews = controls + (editor.map { [$0.view] } ?? [])
        return !interactiveViews.contains { $0.bounds.contains($0.convert(point, from: nil)) }
    }

    private func beginEditing(at screenPoint: NSPoint) {
        let host = glassController.hostingController
        var content = host.rootView
        guard let editor = DesktopNoteEditor(text: content.item.content, font: content.historyFont)
        else { return }
        let padding = HistoryItemPreviewContent.contentPadding
        content.showsBody = false
        let headingHeight = title.isEmpty ? 0 : NSHostingController(rootView: content.titlePreview)
            .sizeThatFits(in: NSSize(width: frame.width - 2 * padding, height: .infinity)).height
            + HistoryItemPreviewText.spacing
        host.rootView = content

        self.editor = editor
        let container = glassController.view
        container.addSubview(editor.view)
        NSLayoutConstraint.activate([
            editor.view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            editor.view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            editor.view.topAnchor.constraint(equalTo: container.topAnchor, constant: padding + headingHeight),
            editor.view.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -DesktopNoteContent.controlsHeight)
        ])
        let height = max(frame.height, padding + headingHeight + DesktopNoteContent.controlsHeight + 40)
        resize(to: NSSize(width: frame.width, height: min(availableFrame.height, height)))
        container.layoutSubtreeIfNeeded()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(editor.textView)
        let point = editor.textView.convert(convertPoint(fromScreen: screenPoint), from: nil)
        let index = editor.textView.characterIndexForInsertion(at: point)
        let offset = min(index, (editor.originalText as NSString).length)
        editor.textView.setSelectedRange(NSRange(location: offset, length: 0))
    }

    private func handleEditingKey(_ event: NSEvent) -> Bool {
        guard editor?.textView.hasMarkedText() != true else { return false }
        if event.keyCode == kVK_Escape, !isSaving {
            finishEditing()
            return true
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers == .command, event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter {
            saveEditing()
            return true
        }
        return false
    }

    private func saveEditing() {
        guard let editor, let onSave, !isSaving else { return }
        editor.textView.unmarkText()
        let text = editor.textView.string
        guard text != editor.originalText else {
            finishEditing()
            return
        }
        isSaving = true
        editor.textView.isEditable = false
        Task { [weak self] in
            guard let self else { return }
            do {
                try await onSave(text)
                isSaving = false
                finishEditing()
            } catch {
                isSaving = false
                closeAfterSave = false
                changeDisplayModeAfterSave = false
                editor.textView.isEditable = true
                editor.showError(AppSettings.shared.localizedString(clipItemEditErrorMessage(error)))
            }
        }
    }

    private func finishEditing() {
        guard let editor else { return }
        self.editor = nil
        makeFirstResponder(nil)
        editor.view.removeFromSuperview()
        if changeDisplayModeAfterSave {
            changeDisplayModeAfterSave = false
            flipDisplayMode()
        }
        reloadPreview(for: glassController.hostingController.rootView.item)
        if closeAfterSave {
            closeAfterSave = false
            close()
        }
    }

    private static func contentSize(for content: DesktopNoteContent, screenFrame: NSRect) -> NSSize {
        let maxWidth = min(420, screenFrame.width)
        let sizing = NSHostingController(rootView: content.sizingPreview)
        let ideal = sizing.sizeThatFits(in: NSSize(width: maxWidth, height: .infinity))
        let width = min(maxWidth, max(Self.minimumResizeSize.width, ceil(ideal.width)))
        let wrapped = sizing.sizeThatFits(in: NSSize(width: width, height: .infinity))
        let height = min(screenFrame.height, ceil(wrapped.height) + DesktopNoteContent.controlsHeight)
        return NSSize(width: width, height: height)
    }

    private func installColorStrip(in view: NSView) {
        colorStrip.wantsLayer = true
        colorStrip.isHidden = true
        colorStrip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(colorStrip)
        NSLayoutConstraint.activate([
            colorStrip.leftAnchor.constraint(equalTo: view.leftAnchor),
            colorStrip.topAnchor.constraint(equalTo: view.topAnchor),
            colorStrip.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            colorStrip.widthAnchor.constraint(equalToConstant: 7)
        ])
    }

    private func installControls(in view: NSView, for item: ClipItem) {
        if let onChangeCategory {
            let menu = DesktopNoteCategoryMenu(item: item, onChangeCategory: onChangeCategory) { [weak self] in
                guard let self else { return }
                CategoryManagerWindowCoordinator.shared.open(relativeTo: self)
            }
            let control = NSHostingView(rootView: menu)
            control.sizingOptions = []
            control.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                control.widthAnchor.constraint(equalToConstant: MainViewMetrics.HistoryColumns.rowCategoryWidth),
                control.heightAnchor.constraint(equalToConstant: MainViewMetrics.HistoryColumns.controlColumnWidth)
            ])
            categoryControl = control
            controls.append(control)
        }
        let palette = makeButton("paintpalette", labelKey: "Desktop Note Color", action: #selector(showColors(_:)))
        let format = makeButton(
            "chevron.left.forwardslash.chevron.right",
            labelKey: "Show Markdown",
            action: #selector(toggleDisplayMode)
        )
        displayModeButton = format
        updateDisplayModeButton()
        let close = makeButton("xmark", labelKey: "Remove Desktop Note", action: #selector(performClose(_:)))
        controls.append(contentsOf: [palette, format, close, DesktopNoteResizeHandle(frame: .zero)])
        let stack = NSStackView(views: controls)
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6)
        ])
    }

    @objc private func toggleDisplayMode() {
        if editor != nil {
            changeDisplayModeAfterSave = true
            saveEditing()
            return
        }
        flipDisplayMode()
        reloadPreview(for: glassController.hostingController.rootView.item)
    }

    private func flipDisplayMode() {
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

    private func makeButton(_ symbol: String, labelKey: String, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        let label = AppSettings.shared.localizedString(labelKey)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.translatesAutoresizingMaskIntoConstraints = false
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 24)
        ])
        return button
    }

    @objc private func showColors(_ sender: NSButton) {
        let menu = NSMenu()
        for color in DesktopNoteColor.allCases {
            let title = AppSettings.shared.localizedString(color.rawValue)
            let item = NSMenuItem(title: title, action: #selector(changeColor(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = color.rawValue
            item.state = color == selectedColor ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: sender.bounds.minX, y: sender.bounds.minY), in: sender)
    }

    @objc private func changeColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let color = DesktopNoteColor(rawValue: key) else { return }
        selectedColor = color
        colorStrip.layer?.backgroundColor = color.fill?.cgColor
        colorStrip.isHidden = color.fill == nil
    }
}
