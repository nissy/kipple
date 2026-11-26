import AppKit
import Carbon.HIToolbox
import SwiftUI

final class DesktopNotePanel: NSPanel {
    private static let minimumResizeWidth: CGFloat = 170
    static let toolbarItemSpace: CGFloat = 28
    let noteContentController: DesktopNoteContentController
    let colorStrip = NSView()
    private let initialScreenFrame: NSRect
    let onSave: ((String, Bool) async throws -> Void)?
    let onChangeCategory: ((ClipCategoryChange) async throws -> Void)?
    let openLink: (URL) -> Void
    let copyItem: (ClipItem, @escaping () -> Void) -> Void
    var categoryControl: NSHostingView<DesktopNoteCategoryMenu>?
    var editorToolsButton: NSButton?
    var copyButton: NSButton?
    var editButton: NSButton?
    var latestCopyRequest: UUID?
    var copyFeedbackTask: Task<Void, Never>?
    var paletteButton: NSButton?
    var displayModeButton: NSButton?
    var controls: [NSView] = []
    var closeButton: NSButton?
    var displayMode: AppSettings.DesktopNoteDisplayMode
    var selectedColor = DesktopNoteColor.none {
        didSet {
            colorStrip.layer?.backgroundColor = selectedColor.fill?.cgColor
            colorStrip.isHidden = selectedColor == .none
        }
    }
    let textHitViews = NSHashTable<DesktopNoteTextHitView>.weakObjects()
    var pointerGesture: PointerGesture?
    var pointerCursor: NSCursor?
    var pointerLocation: NSPoint?
    var showingContextMenu = false
    var pendingLink: URL?
    var sourceLinkOpenTask: Task<Void, Never>?
    var manualSize: NSSize?
    private var usesSavedFrame = false
    private var measuredPreviewSize: NSSize?
    private var liveResizeStartSize: NSSize?
    var editor: DesktopNoteEditor?
    private var previewSizeBeforeEditing: NSSize?
    private(set) var isSaving = false
    private var closeAfterSave = false
    var changeDisplayModeAfterSave = false
    weak var sourceRegion: NSView?
    weak var sourceLinkRegion: NSView?
    var onPlacementChange: (() -> Void)?

    var placement: DesktopNotePlacement {
        let size = previewSizeBeforeEditing ?? frame.size
        let savedFrame = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        return DesktopNotePlacement(frame: savedFrame, color: selectedColor, usesManualSize: manualSize != nil)
    }

    override var canBecomeKey: Bool { true }
    var needsBackgroundCursor: Bool { !isKeyWindow || !NSApp.isActive }

    init(
        item: ClipItem,
        screenFrame: NSRect,
        displayMode: AppSettings.DesktopNoteDisplayMode = .plainText,
        onSave: ((String, Bool) async throws -> Void)? = nil,
        onChangeCategory: ((ClipCategoryChange) async throws -> Void)? = nil,
        copyLink: @escaping (String) -> Void = { ModernClipboardServiceAdapter.shared.writeToClipboardOnly($0) },
        copyItem: @escaping (ClipItem, @escaping () -> Void) -> Void = {
            ModernClipboardServiceAdapter.shared.recopyFromHistory($0, onSuccess: $1)
        },
        openLink: @escaping (URL) -> Void = { _ = NSWorkspace.shared.open($0) }
    ) {
        var content = DesktopNoteContent(item: item, displayMode: displayMode, copyLink: copyLink)
        let size = content.estimatedWindowSize(in: screenFrame, minimumWidth: Self.minimumResizeWidth)
        initialScreenFrame = screenFrame
        self.displayMode = displayMode
        self.onSave = onSave
        self.onChangeCategory = onChangeCategory
        self.copyItem = copyItem
        self.openLink = openLink
        noteContentController = DesktopNoteContentController(rootView: content)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        // Stay immediately below regular application windows.
        level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        title = HistoryItemPreviewContent.nonempty(item.title) ?? ""
        content.openURL = OpenURLAction { [weak self] url in
            guard let self else { return .discarded }
            // Textual can request a link on mouse down. Open it only after a click completes.
            if case .select(_, _, let anchor) = self.pointerGesture {
                if anchor == nil { self.pendingLink = url }
            } else {
                self.openLink(url)
            }
            return .handled
        }
        content.onDocumentHeightChange = { [weak self] height, id in self?.fitRenderedDocument(id: id, height: height) }
        content.onBlockWidthChange = { [weak self] width, id in self?.fitRenderedDocument(id: id, minimumWidth: width) }
        noteContentController.setContent(content)
        contentViewController = noteContentController
        configureNativeFrame()
        installPointerTracking()
        setContentSize(size)
        installColorStrip(in: noteContentController.view)
        installControls(in: noteContentController.view, for: item)
        updateResizeLimits()
        resize(to: size)
        let notifications = NotificationCenter.default
        notifications.addObserver(self, selector: #selector(didResize),
                                  name: NSWindow.didResizeNotification, object: self)
        notifications.addObserver(self, selector: #selector(willStartLiveResize),
                                  name: NSWindow.willStartLiveResizeNotification, object: self)
        notifications.addObserver(self, selector: #selector(didEndLiveResize),
                                  name: NSWindow.didEndLiveResizeNotification, object: self)
    }

    func update(from item: ClipItem) {
        if let categoryControl, categoryControl.rootView.item.categoryIDs != item.categoryIDs {
            categoryControl.rootView.item = item
        }
        let previous = noteContentController.hostingController.rootView.item
        let headerChanged = item.title != previous.title || item.sourceApp != previous.sourceApp ||
            item.windowTitle != previous.windowTitle || item.metadata?.sourceWebURL != previous.metadata?.sourceWebURL
        guard item.content != previous.content || headerChanged else { return }
        reloadPreview(for: item, headerChanged: headerChanged)
    }

    func restorePlacement(_ placement: DesktopNotePlacement, in screenFrame: NSRect) {
        selectedColor = placement.color
        usesSavedFrame = true
        let saved = placement.frame
        let width = min(max(saved.width, minSize.width), screenFrame.width)
        let height = min(max(saved.height, minSize.height), screenFrame.height)
        let x = min(max(saved.minX, screenFrame.minX), screenFrame.maxX - width)
        let y = min(max(saved.maxY - height, screenFrame.minY), screenFrame.maxY - height)
        if placement.usesManualSize { manualSize = NSSize(width: width, height: height) }
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
    }

    func reloadPreview(for item: ClipItem, headerChanged: Bool = false, restoringSize: NSSize? = nil) {
        let previous = noteContentController.hostingController.rootView
        if item.metadata?.sourceWebURL != previous.item.metadata?.sourceWebURL { cancelSourceLinkOpen() }
        var content = DesktopNoteContent(item: item, displayMode: displayMode, copyLink: previous.copyLink)
        content.showsBody = editor == nil
        content.openURL = previous.openURL
        content.onDocumentHeightChange = previous.onDocumentHeightChange
        content.onBlockWidthChange = previous.onBlockWidthChange
        content.allowsRemoteImages = item.content == previous.item.content && previous.allowsRemoteImages
        if restoringSize == nil { usesSavedFrame = false }
        measuredPreviewSize = nil
        title = HistoryItemPreviewContent.nonempty(item.title) ?? ""
        noteContentController.setContent(content)
        updateResizeLimits()
        updateControlLabels()
        if headerChanged {
            editor?.updateHeader(height: content.headerHeight(at: frame.width))
        }
        if !inLiveResize, editor == nil {
            if let size = manualSize ?? restoringSize {
                resize(to: size)
            } else {
                resizeAutomatically(to: content.estimatedWindowSize(in: availableFrame, minimumWidth: minSize.width))
            }
            onPlacementChange?()
        } else if editor != nil {
            resize(to: frame.size)
        }
    }

    private func fitRenderedDocument(id: UUID, height: CGFloat? = nil, minimumWidth: CGFloat? = nil) {
        let width = frame.width
        // Resize after the SwiftUI layout transaction has completed.
        DispatchQueue.main.async { [weak self] in
            guard let self, isVisible, editor == nil, manualSize == nil,
                  liveResizeStartSize == nil, !inLiveResize else { return }
            let content = noteContentController.hostingController.rootView
            guard content.measurementID == id else { return }
            let previousFrame = frame
            var size = previousFrame.size
            if let height, frame.width == width {
                size.height = ceil(content.headerHeight(at: width) + height) + DesktopNoteContent.controlsHeight
                measuredPreviewSize = size
            }
            guard !usesSavedFrame else { return }
            if let minimumWidth, minimumWidth > size.width {
                size.width = max(size.width, min(DesktopNoteContent.maximumAutomaticWidth, ceil(minimumWidth)))
            }
            resizeAutomatically(to: size)
            if frame != previousFrame { onPlacementChange?() }
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if Self.isContextClick(event) {
            handleContextClick(event)
            return
        }
        switch event.type {
        case .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate:
            handlePointerTracking(event)
            return
        case .leftMouseDown:
            if !isKeyWindow { makeKey() }
            if handleMouseDown(event) { return }
        case .leftMouseDragged:
            let point = event.locationInWindow
            switch pointerGesture {
            case .move(let start, _):
                pointerGesture = .move(start: start, didDrag: true)
                setPointerCursor(Self.moveCursor)
                let pointer = convertPoint(toScreen: point)
                setFrameOrigin(NSPoint(x: pointer.x - start.x, y: pointer.y - start.y))
                return
            case let .select(start, didDrag, anchor):
                let hasDragged = didDrag || pendingLink != nil || isPoint(start, in: sourceLinkRegion)
                    || hypot(point.x - start.x, point.y - start.y) >= 3
                if hasDragged { noteContentController.selectionMayExist = true }
                pointerGesture = .select(start: start, didDrag: hasDragged, anchor: anchor)
            case .sourceLink:
                pointerGesture = .sourceLink(didDrag: true)
                return
            case nil:
                break
            }
        case .leftMouseUp:
            if finishPointerGesture(event) { return }
            Self.refreshPointerCursorAfterTracking()
        case .scrollWheel:
            Self.refreshPointerCursorAfterTracking()
        case .keyDown:
            if handleNoteShortcut(event) { return }
            if editor == nil, firstResponder !== self { noteContentController.selectionMayExist = true }
        default:
            break
        }
        super.sendEvent(event)
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
        clearPointerCursor()
        cancelPointerGesture()
        if editor == nil { noteContentController.clearSelection() }
        saveEditing()
        Self.refreshPointerCursorAfterTracking()
    }

    override func close() {
        cancelSourceLinkOpen()
        cancelPointerGesture()
        clearPointerCursor()
        removePointerTracking()
        super.close()
        Self.refreshPointerCursorAfterTracking()
    }

    override func orderOut(_ sender: Any?) {
        cancelSourceLinkOpen()
        cancelPointerGesture()
        clearPointerCursor()
        super.orderOut(sender)
        Self.refreshPointerCursorAfterTracking()
    }

    @objc func beginEditing() {
        guard editor == nil, onSave != nil else { return }
        let scrollProgress = noteContentController.previewScrollProgress
        let host = noteContentController.hostingController
        var content = host.rootView
        let editor = DesktopNoteEditor(
            text: content.item.content,
            onCancel: { [weak self] in self?.cancelEditing() },
            onSave: { [weak self] in self?.saveEditing(explicitly: true) }
        )
        content.showsBody = false
        noteContentController.setContent(content)

        previewSizeBeforeEditing = frame.size
        self.editor = editor
        clearCopyFeedback()
        copyButton?.isEnabled = false
        editButton?.isHidden = true
        editorToolsButton?.isHidden = false
        editor.install(in: noteContentController.view, headerHeight: content.headerHeight(at: frame.width))
        updateResizeLimits()
        updateControlLabels()
        resize(to: frame.size)
        noteContentController.view.layoutSubtreeIfNeeded()
        makeKeyAndOrderFront(nil)
        editor.focus(in: self, scrollProgress: scrollProgress)
    }

    private func handleNoteShortcut(_ event: NSEvent) -> Bool {
        guard editor?.textView.hasMarkedText() != true else { return false }
        if event.keyCode == kVK_Escape {
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if !modifiers.isEmpty, editor?.handleShortcut(event) == true { return true }
            cancelEditing()
            return true
        }
        return editor?.handleShortcut(event) ?? false
    }

    private func cancelEditing() {
        if !isSaving { finishEditing(keepingPreviewSize: true) }
    }

    func saveEditing(explicitly: Bool = false) {
        guard let editor, let onSave, !isSaving else { return }
        editor.textView.unmarkText()
        let text = editor.textView.string
        guard text != editor.originalText else {
            finishEditing(keepingPreviewSize: true)
            return
        }
        isSaving = true
        editor.setSaving(true)
        let allowsRemovingRichText = explicitly && editor.isConfirmingPlainTextSave
        Task { [weak self] in
            guard let self else { return }
            do {
                try await onSave(text, allowsRemovingRichText)
                isSaving = false
                finishEditing(keepingPreviewSize: false)
            } catch {
                isSaving = false
                closeAfterSave = false
                changeDisplayModeAfterSave = false
                editor.setSaving(false)
                editor.showSaveError(error)
            }
        }
    }

    private func finishEditing(keepingPreviewSize: Bool) {
        guard let editor else { return }
        let size = keepingPreviewSize && !changeDisplayModeAfterSave ? previewSizeBeforeEditing : nil
        self.editor = nil
        copyButton?.isEnabled = true
        editButton?.isHidden = false
        previewSizeBeforeEditing = nil
        editorToolsButton?.isHidden = true
        makeFirstResponder(nil)
        editor.view.removeFromSuperview()
        if changeDisplayModeAfterSave {
            changeDisplayModeAfterSave = false
            flipDisplayMode()
        }
        reloadPreview(for: noteContentController.hostingController.rootView.item, restoringSize: size)
        if closeAfterSave {
            closeAfterSave = false
            close()
        }
    }

    func didLoadRemoteImages() {
        usesSavedFrame = false
        updateResizeLimits()
        updateControlLabels()
    }

    @objc private func didResize() {
        updateControlLabels()
        let content = noteContentController.hostingController.rootView
        editor?.updateHeader(height: content.headerHeight(at: frame.width))
    }
}

extension DesktopNotePanel {
    private func configureNativeFrame() {
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        // Blank-space dragging is handled by the note; AppKit still handles resizing.
        isMovable = false
        isOpaque = false
        hasShadow = true
        backgroundColor = .clear
    }

    private var availableFrame: NSRect {
        (isVisible ? screen?.visibleFrame : nil) ?? initialScreenFrame
    }

    private func resizeAutomatically(to size: NSSize) {
        let heightBelowTop = max(minSize.height, frame.maxY - availableFrame.minY)
        resize(to: NSSize(width: size.width, height: min(size.height, heightBelowTop)))
    }

    func growToFitAfterMoving() {
        guard editor == nil, manualSize == nil, let size = measuredPreviewSize,
              size.width == frame.width, size.height > frame.height else { return }
        let previousHeight = frame.height
        resizeAutomatically(to: size)
        if frame.height > previousHeight { usesSavedFrame = false }
    }

    private func resize(to requestedSize: NSSize) {
        let screen = availableFrame
        let size = NSSize(
            width: min(max(requestedSize.width, minSize.width), screen.width),
            height: min(max(requestedSize.height, minSize.height), screen.height)
        )
        guard size != frame.size else { return }
        let origin = NSPoint(
            x: min(frame.minX, screen.maxX - size.width),
            y: max(frame.maxY - size.height, screen.minY)
        )
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func updateResizeLimits() {
        let size = availableFrame.size
        let content = noteContentController.hostingController.rootView
        let width = min(size.width, max(Self.minimumResizeWidth, minimumToolbarWidth))
        let height = content.minimumHeight(at: width) +
            (editor == nil ? 0 : DesktopNoteEditor.actionsHeight)
        minSize = NSSize(width: width, height: min(size.height, height))
        maxSize = size
    }

    @objc func willStartLiveResize() {
        updateResizeLimits()
        liveResizeStartSize = frame.size
    }

    @objc func didEndLiveResize() {
        if let liveResizeStartSize, liveResizeStartSize != frame.size {
            manualSize = frame.size
            if editor != nil { previewSizeBeforeEditing = frame.size }
            onPlacementChange?()
        }
        liveResizeStartSize = nil
    }
}
