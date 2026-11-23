import AppKit
import XCTest
@testable import Kipple

@MainActor
final class WindowSheetBehaviorTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -2_000, y: -2_000, width: 420, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        return window
    }

    func testSheetKeepsParentVisibleAndAutoHideResumesAfterDismissal() async throws {
        let manager = WindowManager()
        let window = makeWindow()
        manager.setMainWindowForTesting(window)
        defer { window.close() }

        for response in [NSApplication.ModalResponse.cancel, .OK] {
            window.orderFront(nil)
            let sheet = makeWindow()
            defer { sheet.close() }

            // SwiftUI can attach its sheet after the parent's resign-key notification.
            let notification = Notification(name: NSWindow.didResignKeyNotification, object: window)
            manager.windowDidResignKey(notification)
            window.beginSheet(sheet, completionHandler: nil)
            XCTAssertTrue(window.attachedSheet === sheet)
            XCTAssertFalse(window.isKeyWindow)

            try await Task.sleep(for: .milliseconds(250))
            XCTAssertTrue(window.isVisible, "Opening details must not hide the history panel")

            window.endSheet(sheet, returnCode: response)
            sheet.orderOut(nil)
            XCTAssertNil(window.attachedSheet)
            XCTAssertTrue(window.isVisible, "Saving or cancelling details must retain the panel")

            manager.windowDidResignKey(notification)
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertFalse(window.isVisible, "Normal auto-hide must resume after the sheet closes")
        }
    }

    func testUnrelatedWindowResigningDoesNotHideMainWindow() async throws {
        let manager = WindowManager()
        let window = makeWindow()
        let otherWindow = makeWindow()
        manager.setMainWindowForTesting(window)
        defer {
            window.close()
            otherWindow.close()
        }
        window.orderFront(nil)

        manager.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: otherWindow))
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertTrue(window.isVisible)
    }

    func testItemEditorOpensAtDefaultSizeAndCenteredOnHistoryDisplay() throws {
        let manager = WindowManager()
        let mainWindow = makeWindow()
        defer { mainWindow.close() }
        let display = try XCTUnwrap(NSScreen.main)
        mainWindow.setFrameOrigin(display.visibleFrame.origin)
        manager.setMainWindowForTesting(mainWindow)

        let item = ClipItem(content: "A history item")
        let window = manager.openItemEditor(item)
        defer { window.close() }
        let visibleFrame = try XCTUnwrap((mainWindow.screen ?? NSScreen.main)?.visibleFrame)
        XCTAssertEqual(window.frame.width, min(560, visibleFrame.width), accuracy: 1)
        XCTAssertEqual(window.frame.height, min(ClipItemEditorWindow.initialContentSize.height, visibleFrame.height), accuracy: 1)
        XCTAssertEqual(window.frame.midX, visibleFrame.midX, accuracy: 1)
        XCTAssertEqual(window.frame.midY, visibleFrame.midY, accuracy: 1)
        XCTAssertTrue(visibleFrame.insetBy(dx: -1, dy: -1).contains(window.frame))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(manager.openItemEditor(item) === window)
    }

    func testItemEditorRetainsItsWindowUntilSavingCompletes() throws {
        let manager = WindowManager()
        let item = ClipItem(content: "A history item")
        let window = try XCTUnwrap(manager.openItemEditor(item) as? ClipItemEditorWindow)
        defer { window.close() }

        window.isSaving = true
        XCTAssertFalse(manager.windowShouldClose(window))
        window.isSaving = false
        XCTAssertTrue(manager.windowShouldClose(window))

        window.close()
        let reopened = manager.openItemEditor(item)
        defer { reopened.close() }
        XCTAssertFalse(reopened === window)
    }

    func testAddingHistoryOpensASeparateDraftAndReusesItWhileOpen() throws {
        let manager = WindowManager()
        let draft = try XCTUnwrap(manager.openItemEditor() as? ClipItemEditorWindow)
        let edit = manager.openItemEditor(ClipItem(content: "Existing history"))
        defer { edit.close() }
        XCTAssertEqual(draft.target, .newItem)
        XCTAssertEqual(draft.title, AppSettings.shared.localizedString("Add History Item"))
        XCTAssertTrue(manager.openItemEditor() === draft)
        XCTAssertFalse(edit === draft)

        draft.close()
        let reopened = manager.openItemEditor()
        defer { reopened.close() }
        XCTAssertFalse(reopened === draft)
    }

    func testNewItemEditorShowsTenLinesAtItsDefaultSize() async throws {
        let manager = WindowManager()
        let window = manager.openItemEditor()
        defer { window.close() }
        await Task.yield()
        window.displayIfNeeded()

        let editor = try XCTUnwrap(window.contentView.flatMap(findEditor))
        let viewport = try XCTUnwrap(editor.enclosingScrollView?.contentSize)
        let lineHeight = try XCTUnwrap(editor.defaultParagraphStyle?.minimumLineHeight)
        XCTAssertEqual(viewport.height - editor.textContainerInset.height * 2, lineHeight * 10, accuracy: 1)
    }

    private func findEditor(in view: NSView) -> LiveEditorTextView? {
        if let editor = view as? LiveEditorTextView { return editor }
        return view.subviews.lazy.compactMap { self.findEditor(in: $0) }.first
    }
}
