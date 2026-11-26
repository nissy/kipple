import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

struct DesktopNotePlacement: Codable {
    private static let defaultsKey = "desktopNotePlacements"

    let frame: CGRect
    let color: DesktopNoteColor
    let usesManualSize: Bool

    static func load(from defaults: UserDefaults) -> [UUID: Self] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([UUID: Self].self, from: data)) ?? [:]
    }

    static func save(_ placements: [UUID: Self], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(placements) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

@MainActor
final class DesktopNoteWindowCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = DesktopNoteWindowCoordinator(defaults: .standard)

    @Published private var notes: [UUID: DesktopNotePanel] = [:]
    private var closingNotes: [UUID: Task<Void, Never>] = [:]
    private let adapter: ModernClipboardServiceAdapter
    private let defaults: UserDefaults?
    private var placements: [UUID: DesktopNotePlacement]
    private var isTerminating = false
    private var historyObservation: AnyCancellable?

    init(adapter: ModernClipboardServiceAdapter = .shared, defaults: UserDefaults? = nil) {
        self.adapter = adapter
        self.defaults = defaults
        placements = defaults.map { DesktopNotePlacement.load(from: $0) } ?? [:]
        super.init()
        historyObservation = adapter.$history.sink { [weak self] history in
            self?.updateOpenNotes(from: history)
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
        openNote(for: item, on: screen)
    }

    func restoreNotes() async {
        let ids = Set(placements.keys.filter { notes[$0] == nil })
        guard !isTerminating, !ids.isEmpty, let fallbackScreen = NSScreen.main ?? NSScreen.screens.first,
              let items = await adapter.desktopNoteItemsToRestore(ids), !isTerminating else { return }
        let missing = ids.subtracting(items.map(\.id))
        for id in missing where notes[id] == nil { placements.removeValue(forKey: id) }
        for item in items {
            guard notes[item.id] == nil, let placement = placements[item.id] else { continue }
            let screen = screen(for: placement.frame) ?? fallbackScreen
            openNote(for: item, on: screen, restoring: placement)
        }
        savePlacements()
    }

    func prepareForTermination() {
        isTerminating = true
        for (id, note) in notes where closingNotes[id] == nil { placements[id] = note.placement }
        savePlacements()
    }

    private func openNote(for item: ClipItem, on screen: NSScreen, restoring placement: DesktopNotePlacement? = nil) {
        let id = item.id
        let note = DesktopNotePanel(
            item: item,
            screenFrame: screen.visibleFrame,
            displayMode: AppSettings.shared.desktopNoteDefaultDisplayMode,
            onSave: { [adapter] text, allowsRemovingRichText in
                try await adapter.updateDetails(
                    itemID: id, title: nil, content: text, categoryChanges: [:],
                    allowsRemovingRichText: allowsRemovingRichText
                )
            },
            onChangeCategory: { [adapter] change in
                try await adapter.updateCategories(itemID: id, change: change)
            },
            copyLink: adapter.writeToClipboardOnly,
            copyItem: adapter.recopyFromHistory
        )
        note.delegate = self
        if let placement {
            note.restorePlacement(placement, in: screen.visibleFrame)
        } else {
            note.setFrameOrigin(initialOrigin(for: note.frame.size, in: screen.visibleFrame))
        }
        notes[id] = note
        note.onPlacementChange = { [weak self, weak note] in
            guard let self, let note, closingNotes[id] == nil else { return }
            placements[id] = note.placement
            savePlacements()
        }
        placements[id] = note.placement
        if placement == nil { savePlacements() }
        note.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        guard !isTerminating, let note = notification.object as? DesktopNotePanel,
              let id = notes.first(where: { $0.value === note })?.key,
              closingNotes[id] == nil else { return }
        placements.removeValue(forKey: id)
        savePlacements()
        closingNotes[id] = Task { [weak self, adapter] in
            await adapter.removeDesktopNoteProtection(id)
            self?.notes.removeValue(forKey: id)
            self?.closingNotes.removeValue(forKey: id)
        }
    }

    private func savePlacements() {
        if let defaults { DesktopNotePlacement.save(placements, to: defaults) }
    }

    private func screen(for frame: CGRect) -> NSScreen? {
        NSScreen.screens.filter { $0.visibleFrame.intersects(frame) }.max { first, second in
            let a = first.visibleFrame.intersection(frame)
            let b = second.visibleFrame.intersection(frame)
            return a.width * a.height < b.width * b.height
        }
    }

    private func updateOpenNotes(from history: [ClipItem]) {
        for item in history {
            notes[item.id]?.update(from: item)
        }
        if adapter.isHistoryLoaded, placements.keys.contains(where: { notes[$0] == nil }) {
            Task { [weak self] in await self?.restoreNotes() }
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
        case move(start: NSPoint, didDrag: Bool)
        case select(start: NSPoint, didDrag: Bool)
    }

    private static let minimumResizeWidth: CGFloat = 170
    private static let toolbarItemSpace: CGFloat = 28
    private static let copyImage = makeCopyImage("doc.on.doc")
    private static let copiedImage = makeCopyImage("checkmark", tint: .controlAccentColor)
    private let noteContentController: DesktopNoteContentController
    private let colorStrip = NSView()
    private let initialScreenFrame: NSRect
    private let onSave: ((String, Bool) async throws -> Void)?
    private let onChangeCategory: ((ClipCategoryChange) async throws -> Void)?
    private let openLink: (URL) -> Void
    private let copyItem: (ClipItem, @escaping () -> Void) -> Void
    private var categoryControl: NSHostingView<DesktopNoteCategoryMenu>?
    private var editorToolsButton: NSButton?
    private var copyButton: NSButton?
    private var editButton: NSButton?
    private var latestCopyRequest: UUID?
    private var copyFeedbackTask: Task<Void, Never>?
    private var paletteButton: NSButton?
    private var displayModeButton: NSButton?
    private var controls: [NSView] = []
    private var displayMode: AppSettings.DesktopNoteDisplayMode
    private var selectedColor = DesktopNoteColor.none {
        didSet {
            colorStrip.layer?.backgroundColor = selectedColor.fill?.cgColor
            colorStrip.isHidden = selectedColor == .none
        }
    }
    private let textHitViews = NSHashTable<DesktopNoteTextHitView>.weakObjects()
    private var pointerGesture: PointerGesture?
    private var pendingLink: URL?
    private var manualSize: NSSize?
    private var usesSavedFrame = false
    private var measuredPreviewSize: NSSize?
    private var liveResizeStartSize: NSSize?
    private var editor: DesktopNoteEditor?
    private var previewSizeBeforeEditing: NSSize?
    private var isSaving = false
    private var closeAfterSave = false
    private var changeDisplayModeAfterSave = false
    weak var sourceRegion: NSView?
    var onPlacementChange: (() -> Void)?

    var placement: DesktopNotePlacement {
        let size = previewSizeBeforeEditing ?? frame.size
        let savedFrame = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        return DesktopNotePlacement(frame: savedFrame, color: selectedColor, usesManualSize: manualSize != nil)
    }

    override var canBecomeKey: Bool { true }

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
            if case .select = self.pointerGesture {
                self.pendingLink = url
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

    private func reloadPreview(for item: ClipItem, headerChanged: Bool = false, restoringSize: NSSize? = nil) {
        let previous = noteContentController.hostingController.rootView
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
            editor?.updateHeader(height: content.headerHeight(at: frame.width), bodyCloseInset: content.bodyCloseInset)
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
        let isContextClick = event.type == .rightMouseDown ||
            (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        if isContextClick, let contentView, let menu = automaticSizeMenu(at: event.locationInWindow) {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
            return
        }
        switch event.type {
        case .leftMouseDown:
            if !isKeyWindow { makeKey() }
            if handleMouseDown(event) { return }
        case .leftMouseDragged:
            let point = event.locationInWindow
            switch pointerGesture {
            case .move(let start, _):
                pointerGesture = .move(start: start, didDrag: true)
                let pointer = convertPoint(toScreen: point)
                setFrameOrigin(NSPoint(x: pointer.x - start.x, y: pointer.y - start.y))
                return
            case let .select(start, didDrag):
                let hasDragged = didDrag || hypot(point.x - start.x, point.y - start.y) >= 3
                if hasDragged { noteContentController.selectionMayExist = true }
                pointerGesture = .select(start: start, didDrag: hasDragged)
            case nil:
                break
            }
        case .leftMouseUp:
            if finishPointerGesture(event) { return }
        case .rightMouseDown:
            if editor == nil { noteContentController.selectionMayExist = true }
        case .keyDown:
            if handleNoteShortcut(event) { return }
            if editor == nil, firstResponder !== self { noteContentController.selectionMayExist = true }
        default:
            break
        }
        super.sendEvent(event)
    }

    func registerTextHitView(_ view: DesktopNoteTextHitView) {
        textHitViews.add(view)
    }

    func automaticSizeMenu(at point: NSPoint) -> NSMenu? {
        guard editor == nil, manualSize != nil, isNoteBody(at: point), !containsPreviewText(at: point) else { return nil }
        let menu = NSMenu()
        let title = AppSettings.shared.localizedString("Fit Note to Content")
        menu.addItem(withTitle: title, action: #selector(fitNoteToContent), keyEquivalent: "").target = self
        return menu
    }

    @objc private func fitNoteToContent() {
        guard editor == nil, manualSize != nil else { return }
        manualSize = nil
        reloadPreview(for: noteContentController.hostingController.rootView.item)
    }

    private func containsPreviewText(at point: NSPoint) -> Bool {
        textHitViews.allObjects.contains { $0.containsText(at: point) }
    }

    private func handleMouseDown(_ event: NSEvent) -> Bool {
        pointerGesture = nil
        pendingLink = nil
        let point = event.locationInWindow
        guard isNoteBody(at: point) else { return false }
        if editor == nil, containsPreviewText(at: point) {
            if event.clickCount > 1 || event.modifierFlags.contains(.shift) {
                noteContentController.selectionMayExist = true
            }
            pointerGesture = .select(start: point, didDrag: false)
            return false
        }
        pointerGesture = .move(start: point, didDrag: false)
        return true
    }

    private func finishPointerGesture(_ event: NSEvent) -> Bool {
        guard let pointerGesture else { return false }
        if case .select(_, let didDrag) = pointerGesture {
            super.sendEvent(event)
            let link = didDrag ? nil : pendingLink
            self.pointerGesture = nil
            pendingLink = nil
            if !didDrag, event.clickCount == 1, !event.modifierFlags.contains(.shift),
               noteContentController.selectionMayExist {
                noteContentController.clearSelection()
            }
            if let link { openLink(link) }
        } else if case .move(_, let didDrag) = pointerGesture {
            self.pointerGesture = nil
            if didDrag {
                growToFitAfterMoving()
                onPlacementChange?()
            } else if editor == nil {
                noteContentController.clearSelection()
            }
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
        if editor == nil { noteContentController.clearSelection() }
        saveEditing()
    }

    private func isNoteBody(at point: NSPoint) -> Bool {
        guard let contentView else { return false }
        let location = contentView.convert(point, from: nil)
        let inset = DesktopNoteContent.windowBorderInset
        // AppKit handles the frame outside the note's interactive surface.
        guard contentView.bounds.insetBy(dx: inset, dy: inset).contains(location),
              !(contentView.hitTest(location) is NSScroller) else { return false }
        let interactiveViews = controls + [editor?.view, sourceRegion].compactMap { $0 }
        return !interactiveViews.contains {
            $0.window === self && !$0.isHiddenOrHasHiddenAncestor && $0.bounds.contains($0.convert(point, from: nil))
        }
    }

    @objc private func beginEditing() {
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
        editor.install(
            in: noteContentController.view,
            headerHeight: content.headerHeight(at: frame.width),
            bodyCloseInset: content.bodyCloseInset
        )
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

    private func saveEditing(explicitly: Bool = false) {
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

    private func installColorStrip(in view: NSView) {
        colorStrip.wantsLayer = true
        selectedColor = DesktopNoteColor.allCases.filter { $0 != .none }.randomElement() ?? .yellow
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
        let tools = noteContentController.makeButton(
            "ellipsis.circle", labelKey: "editor.editTools", target: self, action: #selector(showEditorTools(_:))
        )
        tools.refusesFirstResponder = true
        tools.isHidden = true
        editorToolsButton = tools
        controls.append(contentsOf: [tools, noteContentController.remoteImagesButton])
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
        controls.insert(contentsOf: [copy, palette, format], at: 0)
        if onSave != nil {
            let edit = noteContentController.makeButton(
                "square.and.pencil", labelKey: "editor.mode.startEditing", titleKey: "editor.mode.editing",
                target: self, action: #selector(beginEditing)
            )
            editButton = edit
            controls.insert(edit, at: 1)
        }
        let stack = NSStackView(views: controls)
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        view.addSubview(close)
        controls.append(close)
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.topAnchor, constant: DesktopNoteContent.headerTopInset),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: HistoryItemPreviewContent.contentPadding),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -DesktopNoteContent.windowBorderInset),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4)
        ])
        updateControlLabels()
    }

    private func updateControlLabels() {
        let includesEdit = editButton?.isHidden == false
        let baseWidth: CGFloat = categoryControl == nil ? 250 : 320
        let editSpace = includesEdit ? Self.toolbarItemSpace : 0
        let imageSpace = includesEdit && !noteContentController.remoteImagesButton.isHidden ? Self.toolbarItemSpace : 0
        let showsTitle = frame.width >= baseWidth + editSpace + imageSpace
        for button in [copyButton, editButton, paletteButton, displayModeButton] {
            button?.imagePosition = showsTitle ? .imageLeading : .imageOnly
        }
        if let categoryControl, categoryControl.rootView.showsTitle != showsTitle {
            categoryControl.rootView.showsTitle = showsTitle
            categoryControl.invalidateIntrinsicContentSize()
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
        editor?.updateHeader(height: content.headerHeight(at: frame.width), bodyCloseInset: content.bodyCloseInset)
    }

    @objc private func copyNote() {
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

    private func clearCopyFeedback() {
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

private extension DesktopNotePanel {
    func configureNativeFrame() {
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

    var availableFrame: NSRect {
        (isVisible ? screen?.visibleFrame : nil) ?? initialScreenFrame
    }

    func resizeAutomatically(to size: NSSize) {
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

    func resize(to requestedSize: NSSize) {
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

    func updateResizeLimits() {
        let size = availableFrame.size
        let content = noteContentController.hostingController.rootView
        // A preview with both category and external-image controls has an extra toolbar item.
        let needsImageSpace = editButton?.isHidden == false && categoryControl != nil &&
            !noteContentController.remoteImagesButton.isHidden
        let width = min(size.width, Self.minimumResizeWidth + (needsImageSpace ? Self.toolbarItemSpace : 0))
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
