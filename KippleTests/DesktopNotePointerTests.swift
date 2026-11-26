import AppKit
import XCTest
@testable import Kipple

@MainActor
final class DesktopNotePointerTests: XCTestCase {
    private let screenFrame = NSRect(x: 0, y: 0, width: 900, height: 700)

    func testClickingBlankSpaceMakesTheNoteKeyAtItsCurrentLevel() throws {
        let note = DesktopNotePanel(item: ClipItem(content: "Short line"), screenFrame: screenFrame)
        note.setContentSize(NSSize(width: 260, height: 160))
        note.orderFrontRegardless()
        defer { note.close() }

        let originalLevel = note.level
        let originalFrame = note.frame
        let frontmostProcess = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let point = NSPoint(x: 180, y: 100)
        XCTAssertFalse(note.isKeyWindow)

        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: point, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: point, for: note))

        XCTAssertTrue(note.isKeyWindow)
        XCTAssertEqual(note.level, originalLevel)
        XCTAssertEqual(note.frame, originalFrame)
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.processIdentifier, frontmostProcess)
    }

    func testDraggingBlankSpaceAfterAPlainTextLineMovesTheNote() async throws {
        let previousCursor = NSCursor.current
        defer { previousCursor.set() }
        let note = DesktopNotePanel(item: ClipItem(content: "Short line"), screenFrame: screenFrame)
        note.setContentSize(NSSize(width: 260, height: 160))
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }
        let contentView = try XCTUnwrap(note.contentView)
        contentView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let start = try desktopNoteBodyPoint(in: note, x: 180)
        let origin = note.frame.origin
        let end = NSPoint(x: start.x + 100, y: start.y + 80)
        let moveCursor = DesktopNotePanel.moveCursor
        XCTAssertNotIdentical(moveCursor, NSCursor.openHand)

        note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: start, for: note))
        XCTAssertIdentical(NSCursor.current, moveCursor)
        let text = try desktopNoteBodyPoint(in: note, x: 29)
        note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: text, for: note))
        XCTAssertFalse(NSCursor.current === moveCursor)
        let border = NSPoint(x: 2, y: start.y)
        note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: start, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: border, for: note))
        XCTAssertFalse(NSCursor.current === moveCursor)

        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
        XCTAssertIdentical(NSCursor.current, moveCursor)
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: note))
        XCTAssertIdentical(NSCursor.current, moveCursor)
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: start, for: note))
        XCTAssertIdentical(NSCursor.current, moveCursor)

        XCTAssertEqual(note.frame.origin, NSPoint(x: origin.x + 100, y: origin.y + 80))
    }

    func testDraggingFromBesideTextSelectsThePreviewWithoutMovingTheNote() async throws {
        let previousCursor = NSCursor.current
        defer { previousCursor.set() }
        for mode in [AppSettings.DesktopNoteDisplayMode.plainText, .markdown] {
            let note = DesktopNotePanel(item: ClipItem(content: "Select this text"), screenFrame: screenFrame, displayMode: mode)
            simulateDesktopNoteLiveResize(note, to: NSSize(width: 300, height: 160))
            note.makeKeyAndOrderFront(nil)
            defer { note.close() }
            let controller = try XCTUnwrap(note.contentViewController as? DesktopNoteContentController)
            controller.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            let row = try XCTUnwrap(textBounds(in: controller.view).first)
            let originalFrame = note.frame
            let end = NSPoint(x: row.midX, y: row.midY)
            let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")

            for x in [row.minX - 8, row.maxX + 8] {
                let start = NSPoint(x: x, y: row.midY)
                note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: start, for: note))
                XCTAssertIdentical(NSCursor.current, NSCursor.iBeam)
                note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
                note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: note))
                note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: end, for: note))
                let responder = try XCTUnwrap(note.firstResponder)
                XCTAssertNotIdentical(responder, note)
                XCTAssertTrue(responder.responds(to: try XCTUnwrap(copy.action)), "\(mode), x: \(x)")
                if mode == .markdown {
                    let selection = try XCTUnwrap(responder as? NSUserInterfaceValidations)
                    XCTAssertTrue(selection.validateUserInterfaceItem(copy))
                }
                XCTAssertEqual(note.frame, originalFrame)
                controller.clearSelection()
                controller.view.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func textBounds(in view: NSView) -> [NSRect] {
        let bounds = (view as? DesktopNoteTextHitView).map { hit in
            hit.lines.map { hit.convert($0, to: nil) }
        } ?? []
        return bounds + view.subviews.flatMap(textBounds(in:))
    }

    #if !KIPPLE_APP_STORE
    func testUnselectedNoteUsesTextAndResizeCursorsBeforeClicking() async throws {
        let previousCursor = NSCursor.current
        defer { previousCursor.set() }
        let note = DesktopNotePanel(item: ClipItem(content: "Short line"), screenFrame: screenFrame)
        simulateDesktopNoteLiveResize(note, to: NSSize(width: 260, height: 160))
        note.orderFrontRegardless()
        defer { note.close() }
        note.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(note.isKeyWindow)

        let text = try desktopNoteBodyPoint(in: note, x: 29)
        note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: text, for: note))
        XCTAssertTrue(NSCursor.current === NSCursor.iBeam)

        let width = note.frame.width
        let height = note.frame.height
        let resizePoints: [(NSPoint, NSCursor.FrameResizePosition)] = [
            (NSPoint(x: 2, y: 80), .left),
            (NSPoint(x: width - 2, y: 80), .right),
            (NSPoint(x: 130, y: height - 2), .top),
            (NSPoint(x: 130, y: 2), .bottom),
            (NSPoint(x: 3, y: height - 3), .topLeft),
            (NSPoint(x: width - 3, y: height - 3), .topRight),
            (NSPoint(x: 3, y: 3), .bottomLeft),
            (NSPoint(x: width - 3, y: 3), .bottomRight)
        ]
        for (point, position) in resizePoints {
            note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: point, for: note))
            let expected = NSCursor.frameResize(position: position, directions: .all)
            XCTAssertEqual(NSCursor.current.image.tiffRepresentation, expected.image.tiffRepresentation)
        }
        XCTAssertFalse(note.isKeyWindow)
    }
    #endif

    func testClearsPreviewSelectionOnBlankClickAndFocusLoss() async throws {
        let note = DesktopNotePanel(
            item: ClipItem(content: "Select this Markdown text"), screenFrame: screenFrame, displayMode: .markdown
        )
        simulateDesktopNoteLiveResize(note, to: NSSize(width: 260, height: 160))
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }
        let controller = try XCTUnwrap(note.contentViewController as? DesktopNoteContentController)
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let initialFrame = note.frame
        let start = try desktopNoteBodyPoint(in: note, x: 27)
        let end = NSPoint(x: 122, y: start.y)

        func selectPreviewText() throws {
            note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
            note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: note))
            note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: end, for: note))
            let copyItem = NSMenuItem(title: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: "")
            let selection = try XCTUnwrap(note.firstResponder as? NSUserInterfaceValidations)
            XCTAssertTrue(selection.validateUserInterfaceItem(copyItem))
        }

        try selectPreviewText()
        let blank = NSPoint(x: 195, y: 80)
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: blank, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: blank, for: note))

        XCTAssertIdentical(note.firstResponder, note)
        XCTAssertEqual(controller.hostingController.rootView.selectionRevision, 1)
        XCTAssertEqual(note.frame, initialFrame)

        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        try selectPreviewText()
        let otherWindow = NSWindow(contentRect: initialFrame, styleMask: [.titled], backing: .buffered, defer: false)
        otherWindow.isReleasedWhenClosed = false
        defer { otherWindow.close() }
        otherWindow.makeKeyAndOrderFront(nil)

        XCTAssertFalse(note.isKeyWindow)
        XCTAssertEqual(controller.hostingController.rootView.selectionRevision, 2)
    }

    func testSourceAppWindowAndAddressSupportTextSelection() async throws {
        let previousCursor = NSCursor.current
        defer { previousCursor.set() }
        var opened: [URL] = []
        let item = ClipItem(
            content: "Note body", sourceApp: "Source Browser", windowTitle: "Project window",
            metadata: ClipMetadata(sourceURI: "https://example.com/tasks/42")
        )
        let openLink: (URL) -> Void = { opened.append($0) }
        let note = DesktopNotePanel(item: item, screenFrame: screenFrame, openLink: openLink)
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }
        let controller = try XCTUnwrap(note.contentViewController as? DesktopNoteContentController)
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let source = try XCTUnwrap(note.sourceRegion)
        let sourceFrame = source.convert(source.bounds, to: nil)
        let noteFrame = note.frame

        let rows = textBounds(in: controller.view)
            .filter { sourceFrame.contains(NSPoint(x: $0.midX, y: $0.midY)) }
            .sorted { $0.midY > $1.midY }
        XCTAssertEqual(rows.count, 3)
        let address = try XCTUnwrap(rows.last)
        let linkPoint = NSPoint(x: address.midX, y: address.midY)
        note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: linkPoint, for: note))
        XCTAssertTrue(NSCursor.current === NSCursor.pointingHand)
        let copy = NSSelectorFromString("copy:")
        for (index, row) in rows.enumerated() {
            let start = NSPoint(x: row.minX + 3, y: row.midY)
            let end = NSPoint(x: row.maxX - 3, y: row.midY)
            note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
            note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: note))
            note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: end, for: note))
            let responder = try XCTUnwrap(note.firstResponder)
            XCTAssertNotIdentical(responder, note, "Source row \(index + 1)")
            XCTAssertTrue(responder.responds(to: copy), "Source row \(index + 1)")
            XCTAssertTrue(opened.isEmpty)
            XCTAssertEqual(note.frame, noteFrame)

            controller.clearSelection()
            controller.view.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func testSourceContextMenuSupportsRightClickAndControlClick() async throws {
        let url = "https://example.com/tasks/42"
        var copied: [String] = []
        var opened: [URL] = []
        let note = DesktopNotePanel(
            item: ClipItem(content: "Note body", metadata: ClipMetadata(sourceURI: url)),
            screenFrame: screenFrame,
            copyLink: { copied.append($0) },
            openLink: { opened.append($0) }
        )
        note.orderFrontRegardless()
        defer { note.close() }
        note.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let link = try XCTUnwrap(note.sourceLinkRegion)
        let point = link.convert(NSPoint(x: link.bounds.midX, y: link.bounds.midY), to: nil)
        let position = note.frame

        for (type, modifiers): (NSEvent.EventType, NSEvent.ModifierFlags) in [
            (.rightMouseDown, []), (.leftMouseDown, .control)
        ] {
            let click = try desktopNoteMouseEvent(type, at: point, for: note, modifiers: modifiers)
            let menu = try XCTUnwrap(note.contextMenu(for: click)?.menu)
            let copyURL = try XCTUnwrap(menu.items.firstIndex { $0.representedObject as? String == url })
            menu.performActionForItem(at: copyURL)
        }

        XCTAssertEqual(copied, [url, url])
        XCTAssertTrue(opened.isEmpty)
        XCTAssertFalse(note.isKeyWindow)
        XCTAssertEqual(note.frame, position)
    }

    func testMarkdownContextMenuDoesNotSelectTextAtTextOrMargins() async throws {
        let note = DesktopNotePanel(
            item: ClipItem(content: "Select this Markdown text"), screenFrame: screenFrame, displayMode: .markdown
        )
        simulateDesktopNoteLiveResize(note, to: NSSize(width: 300, height: 160))
        note.orderFrontRegardless()
        defer { note.close() }
        let view = try XCTUnwrap(note.contentView)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let row = try XCTUnwrap(textBounds(in: view).first)
        let responder = note.firstResponder

        for x in [row.minX - 5, row.midX, row.maxX + 5] {
            let point = NSPoint(x: x, y: row.midY)
            let click = try desktopNoteMouseEvent(.rightMouseDown, at: point, for: note)
            let context = try XCTUnwrap(note.contextMenu(for: click), "x: \(x)")
            let copyTitle = AppSettings.shared.localizedString("Copy Entire Note")
            XCTAssertEqual(context.menu.items.map(\.title), [copyTitle])
            XCTAssertIdentical(note.firstResponder, responder)
            XCTAssertFalse(note.noteContentController.selectionMayExist)
            XCTAssertNil(note.automaticSizeMenu(at: point))
        }

        let blank = NSPoint(x: 170, y: 60)
        let click = try desktopNoteMouseEvent(.leftMouseDown, at: blank, for: note, modifiers: .control)
        let menu = try XCTUnwrap(note.contextMenu(for: click)?.menu)
        XCTAssertEqual(menu.items.first?.title, AppSettings.shared.localizedString("Fit Note to Content"))
    }

    func testAutomaticNoteBlankSpaceOffersCopyWithoutTakingFocus() async throws {
        let content = "Copy the entire note"
        var copies: [String] = []
        let copyItem: (ClipItem, @escaping () -> Void) -> Void = { item, _ in
            copies.append(item.content)
        }
        let note = DesktopNotePanel(item: ClipItem(content: content), screenFrame: screenFrame, copyItem: copyItem)
        note.restorePlacement(.init(frame: NSRect(x: 50, y: 80, width: 300, height: 160),
                                    color: .none, usesManualSize: false), in: screenFrame)
        note.orderFrontRegardless()
        defer { note.close() }
        note.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let point = NSPoint(x: 210, y: 60)
        let title = AppSettings.shared.localizedString("Copy Entire Note")

        for (type, modifiers): (NSEvent.EventType, NSEvent.ModifierFlags) in [
            (.rightMouseDown, []), (.leftMouseDown, .control)
        ] {
            let click = try desktopNoteMouseEvent(type, at: point, for: note, modifiers: modifiers)
            let menu = try XCTUnwrap(note.contextMenu(for: click)?.menu)
            XCTAssertEqual(menu.items.map(\.title), [title])
            menu.performActionForItem(at: 0)
        }

        XCTAssertEqual(copies, [content, content])
        XCTAssertFalse(note.isKeyWindow)
    }

    func testContextClickOffersExistingPreviewSelectionInBothDisplayModes() async throws {
        for mode in [AppSettings.DesktopNoteDisplayMode.plainText, .markdown] {
            try await verifyContextClickPreservesSelection(in: mode)
        }
    }

    private func verifyContextClickPreservesSelection(in mode: AppSettings.DesktopNoteDisplayMode) async throws {
        let note = DesktopNotePanel(item: ClipItem(content: "Select this text"), screenFrame: screenFrame, displayMode: mode)
        simulateDesktopNoteLiveResize(note, to: NSSize(width: 280, height: 160))
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }
        let view = try XCTUnwrap(note.contentView)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let row = try XCTUnwrap(textBounds(in: view).first)
        let start = NSPoint(x: row.minX + 2, y: row.midY)
        let end = NSPoint(x: row.midX, y: row.midY)
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: end, for: note))
        let responder = try XCTUnwrap(note.firstResponder)
        let outsideSelection = NSPoint(x: row.maxX - 2, y: row.midY)
        for (type, modifiers): (NSEvent.EventType, NSEvent.ModifierFlags) in [
            (.rightMouseDown, []), (.leftMouseDown, .control)
        ] {
            let click = try desktopNoteMouseEvent(type, at: outsideSelection, for: note, modifiers: modifiers)
            let menu = try XCTUnwrap(note.contextMenu(for: click)?.menu)
            let copy = try XCTUnwrap(menu.items.first { $0.action == #selector(NSText.copy(_:)) })
            XCTAssertIdentical(copy.target, responder)
            XCTAssertIdentical(note.firstResponder, responder)
        }
    }

    func testHoverTransitionsBetweenSourceLinkMarkdownTextBlankAndToolbar() async throws {
        let previousCursor = NSCursor.current
        defer { previousCursor.set() }
        let note = DesktopNotePanel(
            item: ClipItem(content: "Ordinary Markdown text", metadata: ClipMetadata(sourceURI: "https://example.com")),
            screenFrame: screenFrame,
            displayMode: .markdown
        )
        simulateDesktopNoteLiveResize(note, to: NSSize(width: 320, height: 230))
        note.orderFrontRegardless()
        defer { note.close() }
        let view = try XCTUnwrap(note.contentView)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let link = try XCTUnwrap(note.sourceLinkRegion)
        let address = link.convert(NSPoint(x: link.bounds.midX, y: link.bounds.midY), to: nil)
        let text = try desktopNoteBodyPoint(in: note, x: 29)
        let blank = NSPoint(x: 210, y: 65)
        let toolbar = try XCTUnwrap(view.subviews.compactMap { $0 as? NSStackView }.first)
        let button = try XCTUnwrap(toolbar.views.compactMap { $0 as? NSButton }.first { !$0.isHidden })
        let control = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)

        for (point, expected) in [
            (address, NSCursor.pointingHand), (text, .iBeam), (blank, DesktopNotePanel.moveCursor),
            (control, .arrow), (address, .pointingHand), (text, .iBeam)
        ] {
            note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: point, for: note))
            XCTAssertIdentical(NSCursor.current, expected, "Cursor at \(point)")
        }
    }

    func testContextClickEndsAnInterruptedNoteMove() throws {
        let note = DesktopNotePanel(item: ClipItem(content: "Short line"), screenFrame: screenFrame)
        note.setContentSize(NSSize(width: 260, height: 160))
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }
        let start = NSPoint(x: 180, y: 70)
        let end = NSPoint(x: 220, y: 85)
        var saved: [NSRect] = []
        note.onPlacementChange = { [weak note] in
            if let note { saved.append(note.frame) }
        }

        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: note))
        let moved = note.frame
        let border = NSPoint(x: 2, y: 85)
        note.sendEvent(try desktopNoteMouseEvent(.rightMouseDown, at: border, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: note))

        XCTAssertNil(note.pointerGesture)
        XCTAssertEqual(note.frame, moved)
        XCTAssertEqual(saved, [moved])
    }
}

extension DesktopNotePointerTests {
    func testDraggingAMarkdownLinkSelectsTextWithoutMovingTheNoteOrOpeningTheLink() async throws {
        var opened: [URL] = []
        let openLink: (URL) -> Void = { opened.append($0) }
        let note = DesktopNotePanel(
            item: ClipItem(content: "[Open the example](https://example.com)"),
            screenFrame: screenFrame,
            displayMode: .markdown,
            openLink: openLink
        )
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }
        let contentView = try XCTUnwrap(note.contentView)
        contentView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let start = try desktopNoteBodyPoint(in: note, x: 29)
        let origin = note.frame.origin

        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: start, for: note))
        XCTAssertEqual(opened.map(\.absoluteString), ["https://example.com"])
        XCTAssertEqual(note.frame.origin, origin)

        let end = NSPoint(x: start.x + 60, y: start.y + 45)
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: start, for: note))
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(note.frame.origin, origin)
    }

    func testSmallDragAndShiftClickOnAMarkdownLinkDoNotOpenIt() async throws {
        var opened: [URL] = []
        let openLink: (URL) -> Void = { opened.append($0) }
        let note = DesktopNotePanel(
            item: ClipItem(content: "[Open the example](https://example.com)"),
            screenFrame: screenFrame, displayMode: .markdown, openLink: openLink
        )
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }
        note.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let start = try desktopNoteBodyPoint(in: note, x: 29)
        let end = NSPoint(x: start.x + 2, y: start.y)

        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: end, for: note))
        XCTAssertTrue(opened.isEmpty)

        opened.removeAll()
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note, modifiers: .shift))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: start, for: note, modifiers: .shift))
        XCTAssertTrue(opened.isEmpty)
    }
}
