import AppKit

extension DesktopNotePanel {
    enum PointerGesture {
        case move(start: NSPoint, didDrag: Bool)
        case select(start: NSPoint, didDrag: Bool, anchor: NSPoint? = nil)
        case sourceLink(didDrag: Bool)
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

    func installPointerTracking() {
        acceptsMouseMovedEvents = true
        _ = Self.contextClickMonitor
        Self.observePointer(for: self)
        noteContentController.view.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self, userInfo: nil
        ))
    }

    func removePointerTracking() {
        Self.pointerNotes.remove(self)
        if Self.pointerNotes.allObjects.isEmpty {
            Self.pointerTimer?.cancel()
            Self.pointerTimer = nil
            Self.lastPolledPointer = nil
            Self.pointerSettleDeadline = 0
        }
    }

    func handlePointerTracking(_ event: NSEvent) {
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

    func registerTextHitView(_ view: DesktopNoteTextHitView) {
        textHitViews.add(view)
    }

    private func containsPreviewText(at point: NSPoint) -> Bool {
        textHitViews.allObjects.contains { $0.containsText(at: point) }
    }

    func initialPointerGesture(at point: NSPoint) -> PointerGesture? {
        let isSourceLink = isPoint(point, in: sourceLinkRegion)
        let selectsText = (editor == nil || isSourceLink) && containsPreviewText(at: point)
        guard isNoteBody(at: point, includingSource: selectsText || isSourceLink) else { return nil }
        if selectsText { return .select(start: point, didDrag: false) }
        if isSourceLink { return .sourceLink(didDrag: false) }
        let anchors = editor == nil ? textHitViews.allObjects.compactMap {
            $0.nearbySelectionStart(at: point)
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

    func setPointerCursor(_ cursor: NSCursor?) {
        if let cursor {
            DesktopNotePointerCursor.set(cursor, for: self)
        } else {
            DesktopNotePointerCursor.clear(pointerCursor, for: self)
        }
        pointerCursor = cursor
    }

    func clearPointerCursor() {
        pointerLocation = nil
        setPointerCursor(nil)
    }

    static func noteUnderPointer(at position: NSPoint = NSEvent.mouseLocation) -> (note: DesktopNotePanel, point: NSPoint)? {
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

    static func refreshPointerCursorAfterTracking() {
        guard !pointerRefreshPending else { return }
        pointerRefreshPending = true
        // An exit from one note can be delivered after the enter on another note.
        DispatchQueue.main.async {
            pointerRefreshPending = false
            refreshPointerCursor(at: NSEvent.mouseLocation)
        }
    }

    func handleMouseDown(_ event: NSEvent) -> Bool {
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

    func finishPointerGesture(_ event: NSEvent) -> Bool {
        guard let pointerGesture else { return false }
        let point = event.locationInWindow
        let isSingleClick = event.clickCount == 1 && event.modifierFlags.isDisjoint(with: [.shift, .control])
        if case .select(let start, let didDrag, _) = pointerGesture {
            let startsInSourceLink = isPoint(start, in: sourceLinkRegion)
            super.sendEvent(event)
            let clicked = isSingleClick && !didDrag
            let bodyLink = clicked && !startsInSourceLink ? pendingLink : nil
            self.pointerGesture = nil
            pendingLink = nil
            if clicked, !startsInSourceLink, noteContentController.selectionMayExist {
                noteContentController.clearSelection()
            }
            if let bodyLink { openLink(bodyLink) }
            if startsInSourceLink, clicked, let url = sourceWebURL(at: point) {
                openSourceLinkAfterSingleClick(url)
            }
            updatePointerCursor(at: point)
        } else if case .sourceLink(let didDrag) = pointerGesture {
            self.pointerGesture = nil
            if isSingleClick, !didDrag, let url = sourceWebURL(at: point) {
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

    func cancelPointerGesture() {
        let gesture = pointerGesture
        pointerGesture = nil
        pendingLink = nil
        if case .move(_, true) = gesture { onPlacementChange?() }
    }

    func sourceWebURL(at point: NSPoint) -> URL? {
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

    func cancelSourceLinkOpen() {
        sourceLinkOpenTask?.cancel()
        sourceLinkOpenTask = nil
    }

    func isNoteBody(at point: NSPoint, includingSource: Bool = false) -> Bool {
        guard let contentView else { return false }
        let location = contentView.convert(point, from: nil)
        let inset = DesktopNoteContent.windowBorderInset
        // AppKit handles the frame outside the note's interactive surface.
        guard contentView.bounds.insetBy(dx: inset, dy: inset).contains(location),
              !(contentView.hitTest(location) is NSScroller) else { return false }
        let interactiveViews = controls + [editor?.view, includingSource ? nil : sourceRegion].compactMap { $0 }
        return !interactiveViews.contains { isPoint(point, in: $0) }
    }

    func isPoint(_ point: NSPoint, in view: NSView?) -> Bool {
        guard let view, view.window === self, !view.isHiddenOrHasHiddenAncestor else { return false }
        return view.bounds.contains(view.convert(point, from: nil))
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
