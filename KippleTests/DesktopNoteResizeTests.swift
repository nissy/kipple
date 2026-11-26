import AppKit
import XCTest
@testable import Kipple

@MainActor
final class DesktopNoteResizeTests: XCTestCase {
    private let screenFrame = NSRect(x: 0, y: 0, width: 900, height: 700)

    func testDesktopNotesUseTheNativeResizableFrameWithFullSizeContent() {
        let note = DesktopNotePanel(item: ClipItem(content: "Short note"), screenFrame: screenFrame)
        defer { note.close() }

        XCTAssertTrue(note.styleMask.contains(.resizable))
        XCTAssertTrue(note.styleMask.contains(.titled))
        XCTAssertTrue(note.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(note.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(note.isMovable)
        XCTAssertEqual(note.contentView?.frame.size, note.frame.size)
        XCTAssertEqual(note.minSize, NSSize(width: 170, height: 120))
    }

    func testAnUnchangedLiveResizeDoesNotDisableAutomaticSizing() {
        var item = ClipItem(content: "Short note")
        let note = DesktopNotePanel(item: item, screenFrame: screenFrame)
        note.setFrameTopLeftPoint(NSPoint(x: 40, y: 600))
        defer { note.close() }
        let start = note.frame

        simulateDesktopNoteLiveResize(note, to: start.size)
        item = item.replacingContent(with: String(repeating: "A longer note body.\n\n", count: 15))
        note.update(from: item)

        XCTAssertGreaterThan(note.frame.height, start.height)
        XCTAssertEqual(note.frame.maxY, start.maxY)
    }

    func testNoteFooterOnlyShowsAndOpensWebSourceURLs() async throws {
        var item = ClipItem(content: "Review the project plan")
        let source = "https://example.com/tasks/42"
        item.metadata?.sourceURI = source
        var opened: [URL] = []
        let note = DesktopNotePanel(item: item, screenFrame: screenFrame, onSave: nil, onChangeCategory: nil) { url in
            opened.append(url)
        }
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }
        let contentView = try XCTUnwrap(note.contentView)
        let origin = note.frame.origin
        let minimumHeightWithSourceLink = note.minSize.height
        let point = NSPoint(x: 30, y: DesktopNoteContent.controlsHeight + 11)

        func clickSourceLink() async throws {
            contentView.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: point, for: note))
            note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: point, for: note))
        }

        try await clickSourceLink()
        XCTAssertEqual(opened.map(\.absoluteString), [source])
        XCTAssertEqual(note.frame.origin, origin)

        item.metadata?.sourceURI = "slack://channel?team=T123&id=C456"
        note.update(from: item)
        XCTAssertLessThan(note.minSize.height, minimumHeightWithSourceLink)
        try await clickSourceLink()
        XCTAssertEqual(opened.map(\.absoluteString), [source])

        let updatedSource = "http://example.com/tasks/43"
        item.metadata?.sourceURI = updatedSource
        note.update(from: item)
        XCTAssertEqual(note.minSize.height, minimumHeightWithSourceLink)
        try await clickSourceLink()
        XCTAssertEqual(opened.map(\.absoluteString), [source, updatedSource])
    }

    func testNativeTitleBarAndButtonsStayHiddenWhenHistoryTitleChanges() {
        let item = ClipItem(content: "Short note")
        let note = DesktopNotePanel(item: item, screenFrame: screenFrame)
        defer { note.close() }

        note.update(from: ClipItem(content: item.content, metadata: ClipMetadata(title: "History title")))
        XCTAssertEqual(note.title, "History title")
        XCTAssertEqual(note.titleVisibility, .hidden)
        XCTAssertTrue(note.titlebarAppearsTransparent)
        XCTAssertEqual(note.titlebarSeparatorStyle, .none)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            XCTAssertTrue(note.standardWindowButton(button)?.isHidden ?? true)
        }
    }
}

@MainActor
func simulateDesktopNoteLiveResize(_ note: DesktopNotePanel, to size: NSSize) {
    let notifications = NotificationCenter.default
    notifications.post(name: NSWindow.willStartLiveResizeNotification, object: note)
    note.setFrame(NSRect(x: note.frame.minX, y: note.frame.maxY - size.height,
                         width: size.width, height: size.height), display: true)
    notifications.post(name: NSWindow.didEndLiveResizeNotification, object: note)
}
