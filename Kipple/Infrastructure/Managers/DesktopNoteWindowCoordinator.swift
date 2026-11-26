import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import SwiftUI

@MainActor
struct DesktopNoteDisplay: Identifiable {
    let id: String
    let screen: NSScreen

    init?(screen: NSScreen) {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        id = CFUUIDCreateString(nil, uuid) as String
        self.screen = screen
    }

    static var connected: [Self] {
        NSScreen.screens.compactMap(Self.init)
    }

    static func destination(preferredID: String, originatingScreen: NSScreen?, among screens: [NSScreen]) -> NSScreen? {
        let displays = screens.compactMap(Self.init)
        let fallbackID = originatingScreen.flatMap(Self.init)?.id
        let mainScreen = NSScreen.main
        return displays.first { $0.id == preferredID }?.screen
            ?? displays.first { $0.id == fallbackID }?.screen
            ?? screens.first { $0 == originatingScreen }
            ?? screens.first { $0 == mainScreen }
            ?? screens.first
    }
}

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
    private var repeatedCopyObservation: AnyCancellable?

    init(adapter: ModernClipboardServiceAdapter = .shared, defaults: UserDefaults? = nil) {
        self.adapter = adapter
        self.defaults = defaults
        placements = defaults.map { DesktopNotePlacement.load(from: $0) } ?? [:]
        super.init()
        historyObservation = adapter.$history.sink { [weak self] history in
            self?.updateOpenNotes(from: history)
        }
        repeatedCopyObservation = adapter.repeatedCopyDesktopNoteRequests.sink { [weak self] itemID in
            Task { await self?.post(itemID, on: nil) }
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
        await post(itemID, on: screen)
    }

    private func post(_ itemID: UUID, on screen: NSScreen?) async {
        guard !isTerminating, notes[itemID] == nil, !NSScreen.screens.isEmpty,
              let item = await adapter.protectHistoryForDesktopNote(itemID) else { return }
        guard !isTerminating, let destination = DesktopNoteDisplay.destination(
            preferredID: AppSettings.shared.desktopNoteDisplayID, originatingScreen: screen, among: NSScreen.screens
        ) else {
            await adapter.removeDesktopNoteProtection(itemID)
            return
        }
        openNote(for: item, on: destination)
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
        case select(start: NSPoint, didDrag: Bool, anchor: NSPoint? = nil)
        case sourceLink(didDrag: Bool)
    }

    private static let minimumResizeWidth: CGFloat = 170
    private static let toolbarItemSpace: CGFloat = 28
    private static let copyImage = makeCopyImage("doc.on.doc")
    private static let copiedImage = makeCopyImage("checkmark", tint: .controlAccentColor)
    private static let contextClickMonitor = NSEvent.addLocalMonitorForEvents(
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
    private static let pointerNotes = NSHashTable<DesktopNotePanel>.weakObjects()
    private static var pointerTimer: DispatchSourceTimer?
    private static var lastPolledPointer: NSPoint?
    private static var pointerSettleDeadline: TimeInterval = 0
    private static var pointerRefreshPending = false
    static let moveCursor: NSCursor = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        guard let glyph = NSImage(systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
                                  accessibilityDescription: nil),
              let arrow = glyph.withSymbolConfiguration(configuration.applying(.init(paletteColors: [.black]))),
              let outline = glyph.withSymbolConfiguration(configuration.applying(.init(paletteColors: [.white]))) else {
            return .openHand
        }
        let size = NSSize(width: 26, height: 26)
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        let image = NSImage(size: size, flipped: false) { _ in
            let frame = NSRect(x: center.x - arrow.size.width / 2, y: center.y - arrow.size.height / 2,
                               width: arrow.size.width, height: arrow.size.height)
            // Keep the black arrow legible over dark and light content.
            outline.draw(in: frame.offsetBy(dx: -1, dy: 0))
            outline.draw(in: frame.offsetBy(dx: 1, dy: 0))
            outline.draw(in: frame.offsetBy(dx: 0, dy: -1))
            outline.draw(in: frame.offsetBy(dx: 0, dy: 1))
            arrow.draw(in: frame)
            return true
        }
        return NSCursor(image: image, hotSpot: center)
    }()
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
    private var pointerCursor: NSCursor?
    private var pointerLocation: NSPoint?
    private var showingContextMenu = false
    private var pendingLink: URL?
    private var sourceLinkOpenTask: Task<Void, Never>?
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
    weak var sourceLinkRegion: NSView?
    var onPlacementChange: (() -> Void)?

    var placement: DesktopNotePlacement {
        let size = previewSizeBeforeEditing ?? frame.size
        let savedFrame = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        return DesktopNotePlacement(frame: savedFrame, color: selectedColor, usesManualSize: manualSize != nil)
    }

    override var canBecomeKey: Bool { true }
    fileprivate var needsBackgroundCursor: Bool { !isKeyWindow || !NSApp.isActive }

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
        acceptsMouseMovedEvents = true
        _ = Self.contextClickMonitor
        Self.observePointer(for: self)
        noteContentController.view.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self, userInfo: nil
        ))
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
                let hasDragged = didDrag || isPoint(start, in: sourceLinkRegion)
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

    private func handlePointerTracking(_ event: NSEvent) {
        defer { Self.refreshPointerCursorAfterTracking() }
        let location = event.type == .mouseMoved ? event.locationInWindow : mouseLocationOutsideOfEventStream
        if displayMode == .markdown, let pointerLocation, isPoint(pointerLocation, in: sourceLinkRegion),
           !isPoint(location, in: sourceLinkRegion), NSCursor.current === NSCursor.pointingHand {
            // Textual should not inherit the cursor from the separately hosted source link.
            setPointerCursor(.iBeam)
        }
        super.sendEvent(event)
        if event.type == .mouseExited, event.trackingArea?.owner as AnyObject? === self {
            if case .move = pointerGesture { return }
            if Self.noteUnderPointer()?.note === self {
                updatePointerCursor(at: location)
            } else {
                clearPointerCursor()
            }
        } else {
            updatePointerCursor(at: location)
        }
    }

    private static func isContextClick(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }

    private func handleContextClick(_ event: NSEvent) {
        guard !showingContextMenu else { return }
        cancelSourceLinkOpen()
        pendingLink = nil
        clearPointerCursor()
        showingContextMenu = true
        defer {
            showingContextMenu = false
            Self.refreshPointerCursorAfterTracking()
        }

        if let context = contextMenu(for: event) {
            let location = context.view.convert(event.locationInWindow, from: nil)
            context.menu.popUp(positioning: nil, at: location, in: context.view)
        } else if event.type == .rightMouseDown {
            super.sendEvent(event)
        } else if let click = contextEvent(event, at: event.locationInWindow) {
            super.sendEvent(click)
        }
    }

    func contextMenu(for event: NSEvent) -> (menu: NSMenu, view: NSView)? {
        let point = event.locationInWindow
        guard let contentView else { return nil }
        if let menu = sourceLinkMenu(at: point) { return (menu, contentView) }
        if let menu = automaticSizeMenu(at: point) {
            addCopyNoteItem(to: menu)
            return (menu, contentView)
        }

        let gesture = initialPointerGesture(at: point, textInset: 5)
        let anchor: NSPoint
        if case .select(_, _, let margin)? = gesture, let margin {
            anchor = margin
        } else {
            anchor = point
        }
        let hitPoint = contentView.superview?.convert(anchor, from: nil) ?? anchor
        if let click = contextEvent(event, at: anchor) {
            var view = contentView.hitTest(hitPoint)
            while let target = view {
                if let nativeMenu = target.menu(for: click), !nativeMenu.items.isEmpty {
                    if editor == nil, gesture != nil, let menu = nativeMenu.copy() as? NSMenu {
                        noteContentController.selectionMayExist = true
                        let copy = #selector(NSText.copy(_:))
                        if target.responds(to: copy) {
                            for item in menu.items where item.action == copy && item.target == nil {
                                item.target = target
                            }
                        }
                        addCopyNoteItem(to: menu)
                        return (menu, target)
                    }
                    return (nativeMenu, target)
                }
                if target === contentView { break }
                view = target.superview
            }
        }
        guard editor == nil, gesture != nil else { return nil }
        let menu = NSMenu()
        addCopyNoteItem(to: menu)
        return (menu, contentView)
    }

    private func addCopyNoteItem(to menu: NSMenu) {
        let action = #selector(copyNote)
        guard menu.items.allSatisfy({ $0.action != action }) else { return }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let title = AppSettings.shared.localizedString("Copy Entire Note")
        menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
    }

    private func contextEvent(_ event: NSEvent, at point: NSPoint) -> NSEvent? {
        NSEvent.mouseEvent(
            with: .rightMouseDown, location: point, modifierFlags: event.modifierFlags,
            timestamp: event.timestamp, windowNumber: windowNumber, context: nil,
            eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure
        )
    }

    func registerTextHitView(_ view: DesktopNoteTextHitView) {
        textHitViews.add(view)
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
        let copy = #selector(NSText.copy(_:))
        if let selection = firstResponder as? NSView, isPoint(point, in: selection), selection.responds(to: copy) {
            let title = AppSettings.shared.localizedString("Copy")
            menu.addItem(withTitle: title, action: copy, keyEquivalent: "").target = selection
        }
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

    private func containsPreviewText(at point: NSPoint) -> Bool {
        textHitViews.allObjects.contains { $0.containsText(at: point) }
    }

    private func initialPointerGesture(at point: NSPoint, textInset: CGFloat = 0.5) -> PointerGesture? {
        let isSourceLink = isPoint(point, in: sourceLinkRegion)
        let selectsText = (editor == nil || isSourceLink) && containsPreviewText(at: point)
        guard isNoteBody(at: point, includingSource: selectsText || isSourceLink) else { return nil }
        if selectsText { return .select(start: point, didDrag: false) }
        if isSourceLink { return .sourceLink(didDrag: false) }
        let anchors = editor == nil ? textHitViews.allObjects.compactMap {
            $0.nearbySelectionStart(at: point, horizontalInset: textInset)
        } : []
        if let anchor = anchors.min(by: {
            hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y)
        }) {
            return .select(start: point, didDrag: false, anchor: anchor)
        }
        return .move(start: point, didDrag: false)
    }

    private func updatePointerCursor(at point: NSPoint, useNativeMarkdownCursor: Bool = true) {
        guard !showingContextMenu else { return }
        pointerLocation = point
        switch pointerGesture {
        case .move: setPointerCursor(Self.moveCursor)
        case .select: setPointerCursor(.iBeam)
        case .sourceLink: setPointerCursor(.pointingHand)
        case nil: setPointerCursor(hoverCursor(at: point, useNativeMarkdownCursor: useNativeMarkdownCursor))
        }
    }

    private func hoverCursor(at point: NSPoint, useNativeMarkdownCursor: Bool) -> NSCursor? {
        guard NSRect(origin: .zero, size: frame.size).contains(point) else { return nil }
        if isPoint(point, in: sourceLinkRegion) { return .pointingHand }
        if let textView = editor?.textView, textView.visibleRect.contains(textView.convert(point, from: nil)) {
            return .iBeam
        }
        if controls.contains(where: { isPoint(point, in: $0) }) { return .arrow }
        switch initialPointerGesture(at: point) {
        case .move: return Self.moveCursor
        case .select(_, _, .some): return .iBeam
        case .select:
            if useNativeMarkdownCursor, editor == nil, displayMode == .markdown, !isPoint(point, in: sourceRegion),
               NSCursor.current === NSCursor.pointingHand {
                return .pointingHand
            }
            return .iBeam
        case .sourceLink: return .pointingHand
        case nil: break
        }
        #if !KIPPLE_APP_STORE
        if needsBackgroundCursor { return resizeCursor(at: point) ?? .arrow }
        #endif
        return nil
    }

    #if !KIPPLE_APP_STORE
    private func resizeCursor(at point: NSPoint) -> NSCursor? {
        let bounds = NSRect(origin: .zero, size: frame.size)
        guard styleMask.contains(.resizable), bounds.contains(point) else { return nil }

        let left = point.x
        let right = bounds.maxX - point.x
        let top = bounds.maxY - point.y
        let bottom = point.y
        let horizontal = min(left, right)
        let vertical = min(top, bottom)
        // The native resize band sits inside the wider margin reserved from window dragging.
        let isCorner = horizontal <= 3 && vertical <= 3
        guard horizontal < 3 || vertical < 3 || isCorner else { return nil }

        let position: NSCursor.FrameResizePosition
        if horizontal < 16 && vertical < 16 {
            if top < bottom {
                position = left < right ? .topLeft : .topRight
            } else {
                position = left < right ? .bottomLeft : .bottomRight
            }
        } else if horizontal < vertical {
            position = left < right ? .left : .right
        } else {
            position = top < bottom ? .top : .bottom
        }
        return .frameResize(position: position, directions: .all)
    }
    #endif

    private func setPointerCursor(_ cursor: NSCursor?) {
        if let cursor {
            DesktopNotePointerCursor.set(cursor, for: self)
        } else {
            DesktopNotePointerCursor.clear(pointerCursor, for: self)
        }
        pointerCursor = cursor
    }

    private func clearPointerCursor() {
        pointerLocation = nil
        setPointerCursor(nil)
    }

    private static func noteUnderPointer(at position: NSPoint = NSEvent.mouseLocation) -> (note: DesktopNotePanel, point: NSPoint)? {
        guard pointerNotes.allObjects.contains(where: { $0.isVisible && $0.frame.contains(position) }) else { return nil }
        let number = NSWindow.windowNumber(at: position, belowWindowWithWindowNumber: 0)
        guard let note = NSApp.window(withWindowNumber: number) as? DesktopNotePanel,
              note.isVisible, !note.ignoresMouseEvents, note.frame.contains(position) else { return nil }
        return (note, note.convertPoint(fromScreen: position))
    }

    private static func observePointer(for note: DesktopNotePanel) {
        pointerNotes.add(note)
        guard pointerTimer == nil else { return }
        // AppKit can defer tracking events during a transition between windows or after a menu.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(40), leeway: .milliseconds(8))
        timer.setEventHandler {
            MainActor.assumeIsolated {
                let position = NSEvent.mouseLocation
                let now = ProcessInfo.processInfo.systemUptime
                if position != lastPolledPointer {
                    lastPolledPointer = position
                    pointerSettleDeadline = now + 0.25
                } else {
                    // Menu dismissal or a deferred exit can replace the cursor at a stationary point.
                    let owner = DesktopNotePointerCursor.owner
                    let cursorChanged = owner?.pointerCursor.map { NSCursor.current !== $0 } ?? false
                    guard cursorChanged || (owner == nil && now < pointerSettleDeadline) else { return }
                }
                refreshPointerCursor(at: position)
            }
        }
        pointerTimer = timer
        timer.activate()
    }

    private static func refreshPointerCursor(at position: NSPoint) {
        // An active gesture keeps its cursor even when the pointer leaves that note.
        let owner = DesktopNotePointerCursor.owner
        guard owner?.pointerGesture == nil, owner?.showingContextMenu != true else { return }
        guard let (note, point) = noteUnderPointer(at: position) else {
            owner?.clearPointerCursor()
            return
        }
        guard note.pointerGesture == nil else { return }
        note.updatePointerCursor(at: point, useNativeMarkdownCursor: note.pointerLocation == point)
    }

    private static func refreshPointerCursorAfterTracking() {
        guard !pointerRefreshPending else { return }
        pointerRefreshPending = true
        // An exit from one note can be delivered after the enter on another note.
        DispatchQueue.main.async {
            pointerRefreshPending = false
            refreshPointerCursor(at: NSEvent.mouseLocation)
        }
    }

    private func handleMouseDown(_ event: NSEvent) -> Bool {
        pendingLink = nil
        let point = event.locationInWindow
        if event.clickCount > 1, isPoint(point, in: sourceLinkRegion) { cancelSourceLinkOpen() }
        pointerGesture = initialPointerGesture(at: point)
        if case .move = pointerGesture {
            setPointerCursor(Self.moveCursor)
            return true
        }
        updatePointerCursor(at: point)
        // Handle a press in the link's icon or spacing without starting native button tracking.
        if case .sourceLink = pointerGesture { return true }
        if case .select(_, _, let anchor) = pointerGesture {
            if event.clickCount > 1 || event.modifierFlags.contains(.shift) {
                noteContentController.selectionMayExist = true
            }
            // An event starting in the margin still needs to reach the native text selection view.
            if let anchor, let textEvent = NSEvent.mouseEvent(
                with: .leftMouseDown, location: anchor, modifierFlags: event.modifierFlags,
                timestamp: event.timestamp, windowNumber: windowNumber, context: nil,
                eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure
            ) {
                super.sendEvent(textEvent)
                return true
            }
        }
        return false
    }

    private func finishPointerGesture(_ event: NSEvent) -> Bool {
        guard let pointerGesture else { return false }
        let point = event.locationInWindow
        let isSingleClick = event.clickCount == 1 && !event.modifierFlags.contains(.shift)
        if case .select(let start, let didDrag, _) = pointerGesture {
            let startsInSourceLink = isPoint(start, in: sourceLinkRegion)
            super.sendEvent(event)
            let bodyLink = startsInSourceLink || didDrag ? nil : pendingLink
            self.pointerGesture = nil
            pendingLink = nil
            if isSingleClick, !didDrag, !startsInSourceLink, noteContentController.selectionMayExist {
                noteContentController.clearSelection()
            }
            if let bodyLink { openLink(bodyLink) }
            if startsInSourceLink, isSingleClick, !didDrag, !event.modifierFlags.contains(.control),
               let url = sourceWebURL(at: point) {
                openSourceLinkAfterSingleClick(url)
            }
            updatePointerCursor(at: point)
        } else if case .sourceLink(let didDrag) = pointerGesture {
            self.pointerGesture = nil
            if isSingleClick, !didDrag, !event.modifierFlags.contains(.control), let url = sourceWebURL(at: point) {
                cancelSourceLinkOpen()
                noteContentController.clearSelection()
                openLink(url)
            }
            updatePointerCursor(at: point)
        } else if case .move(_, let didDrag) = pointerGesture {
            let pointer = convertPoint(toScreen: point)
            self.pointerGesture = nil
            if didDrag {
                growToFitAfterMoving()
                onPlacementChange?()
            } else if editor == nil {
                noteContentController.clearSelection()
            }
            updatePointerCursor(at: convertPoint(fromScreen: pointer))
        }
        Self.refreshPointerCursorAfterTracking()
        return true
    }

    private func sourceWebURL(at point: NSPoint) -> URL? {
        guard isPoint(point, in: sourceLinkRegion) else { return nil }
        return noteContentController.hostingController.rootView.item.metadata?.sourceWebURL
    }

    private func openSourceLinkAfterSingleClick(_ url: URL) {
        cancelSourceLinkOpen()
        // Give AppKit time to recognize a double-click for word selection.
        sourceLinkOpenTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            sourceLinkOpenTask = nil
            openLink(url)
        }
    }

    private func cancelSourceLinkOpen() {
        sourceLinkOpenTask?.cancel()
        sourceLinkOpenTask = nil
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
        if case .move(_, let didDrag) = pointerGesture {
            if didDrag { onPlacementChange?() }
        }
        pointerGesture = nil
        pendingLink = nil
        if editor == nil { noteContentController.clearSelection() }
        saveEditing()
        Self.refreshPointerCursorAfterTracking()
    }

    override func close() {
        cancelSourceLinkOpen()
        clearPointerCursor()
        Self.pointerNotes.remove(self)
        if Self.pointerNotes.allObjects.isEmpty {
            Self.pointerTimer?.cancel()
            Self.pointerTimer = nil
            Self.lastPolledPointer = nil
            Self.pointerSettleDeadline = 0
        }
        super.close()
        Self.refreshPointerCursorAfterTracking()
    }

    override func orderOut(_ sender: Any?) {
        cancelSourceLinkOpen()
        clearPointerCursor()
        super.orderOut(sender)
        Self.refreshPointerCursorAfterTracking()
    }

    private func isNoteBody(at point: NSPoint, includingSource: Bool = false) -> Bool {
        guard let contentView else { return false }
        let location = contentView.convert(point, from: nil)
        let inset = DesktopNoteContent.windowBorderInset
        // AppKit handles the frame outside the note's interactive surface.
        guard contentView.bounds.insetBy(dx: inset, dy: inset).contains(location),
              !(contentView.hitTest(location) is NSScroller) else { return false }
        let interactiveViews = controls + [editor?.view, includingSource ? nil : sourceRegion].compactMap { $0 }
        return !interactiveViews.contains { isPoint(point, in: $0) }
    }

    private func isPoint(_ point: NSPoint, in view: NSView?) -> Bool {
        guard let view, view.window === self, !view.isHiddenOrHasHiddenAncestor else { return false }
        return view.bounds.contains(view.convert(point, from: nil))
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

@MainActor
private enum DesktopNotePointerCursor {
    private(set) static weak var owner: DesktopNotePanel?
    #if !KIPPLE_APP_STORE
    private static let connection = BackgroundCursorConnection()
    private static var previousBackgroundSetting: Bool?
    #endif

    static func set(_ cursor: NSCursor, for note: DesktopNotePanel) {
        owner = note
        #if !KIPPLE_APP_STORE
        if note.needsBackgroundCursor, previousBackgroundSetting == nil,
           let connection, let wasEnabled = connection.isEnabled(),
           wasEnabled || connection.setEnabled(true) {
            previousBackgroundSetting = wasEnabled
        }
        #endif
        cursor.set()
    }

    static func clear(_ cursor: NSCursor?, for note: DesktopNotePanel) {
        guard owner === note else { return }
        #if !KIPPLE_APP_STORE
        // Give the foreground app its cursor back before changing the local cursor.
        if let previousBackgroundSetting {
            guard previousBackgroundSetting || connection?.setEnabled(false) == true else {
                Logger.shared.log("Unable to restore the desktop note cursor setting", level: .warning)
                return
            }
            self.previousBackgroundSetting = nil
        }
        #endif
        owner = nil
        if NSApp.isActive, let cursor, NSCursor.current === cursor {
            NSCursor.arrow.set()
        }
    }
}

#if !KIPPLE_APP_STORE
private struct BackgroundCursorConnection {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyProperty = @convention(c) (
        Int32, Int32, CFString, UnsafeMutablePointer<Unmanaged<CFTypeRef>?>
    ) -> Int32
    private typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    private let id: Int32
    private let copyProperty: CopyProperty
    private let setProperty: SetProperty
    private let property = "SetsCursorInBackground" as CFString

    init?() {
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        else { return nil }
        guard let main = dlsym(library, "CGSMainConnectionID"),
              let copy = dlsym(library, "CGSCopyConnectionProperty"),
              let set = dlsym(library, "CGSSetConnectionProperty") else {
            dlclose(library)
            return nil
        }
        id = unsafeBitCast(main, to: MainConnection.self)()
        copyProperty = unsafeBitCast(copy, to: CopyProperty.self)
        setProperty = unsafeBitCast(set, to: SetProperty.self)
    }

    func isEnabled() -> Bool? {
        var value: Unmanaged<CFTypeRef>?
        let status = copyProperty(id, id, property, &value)
        let current = value?.takeRetainedValue()
        guard status == 0 else { return nil }
        return current == nil ? false : current as? Bool
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        setProperty(id, id, property, enabled ? kCFBooleanTrue : kCFBooleanFalse) == 0
    }
}
#endif

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
