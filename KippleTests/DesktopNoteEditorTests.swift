import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Kipple

@MainActor
final class DesktopNoteEditorTests: XCTestCase {
    private let screenFrame = NSRect(x: 0, y: 0, width: 900, height: 700)

    func testSwitchingFromTheEditorSavesTheOriginalMarkdownSource() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let settings = AppSettings.shared
        let previous = settings.desktopNoteDefaultDisplayMode
        settings.desktopNoteDefaultDisplayMode = .markdown
        defer { settings.desktopNoteDefaultDisplayMode = previous }

        let service = ModernClipboardService(testRepository: try SwiftDataRepository.make(inMemory: true))
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter)
        let title = UUID().uuidString
        let source = "# Heading\n\n**Original** Markdown text"
        try await adapter.createHistoryItem(title: title, content: source, categoryChanges: [:])
        let item = try XCTUnwrap(adapter.history.first)
        await coordinator.toggle(item.id, on: screen)
        let note = try XCTUnwrap(NSApp.windows.first { $0.title == title } as? DesktopNotePanel)
        defer { note.close() }

        let stack = try XCTUnwrap(note.contentView?.subviews.compactMap { $0 as? NSStackView }.first)
        let showPlainText = settings.localizedString("Show Plain Text")
        let button = try XCTUnwrap(stack.views.compactMap { $0 as? NSButton }.first { $0.toolTip == showPlainText })
        XCTAssertNotNil(button.image)
        XCTAssertEqual(adapter.history.first?.content, source)

        try desktopNoteEditButton(in: note).performClick(nil)
        let editor = try XCTUnwrap(note.firstResponder as? NSTextView)
        XCTAssertEqual(editor.string, source)

        let edited = "# Heading\n\n**Edited** Markdown text"
        editor.string = edited
        let showMarkdown = settings.localizedString("Show Markdown")
        button.performClick(nil)
        for _ in 0..<30 where button.toolTip != showMarkdown {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(adapter.history.first?.content, edited)
        XCTAssertEqual(button.toolTip, showMarkdown)

        button.performClick(nil)
        XCTAssertEqual(button.toolTip, showPlainText)
        XCTAssertEqual(adapter.history.first?.content, edited)
    }

    func testDoubleClickKeepsPreviewAndEditButtonOpensFullText() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let service = ModernClipboardService(testRepository: try SwiftDataRepository.make(inMemory: true))
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter)
        let original = String(repeating: "Editable note content. ", count: 30)
        let title = UUID().uuidString
        try await adapter.createHistoryItem(title: title, content: original, categoryChanges: [BuiltInCategory.ocr: true])
        let item = try XCTUnwrap(adapter.history.first)
        await coordinator.toggle(item.id, on: screen)
        let note = try XCTUnwrap(NSApp.windows.first { $0.title == title } as? DesktopNotePanel)
        defer { note.close() }
        note.makeKeyAndOrderFront(nil)
        note.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let point = try desktopNoteBodyPoint(in: note)

        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: point, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: point, for: note))
        XCTAssertFalse(note.firstResponder is NSTextView)

        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: point, for: note, clickCount: 2))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: point, for: note, clickCount: 2))
        XCTAssertFalse(note.firstResponder is LiveEditorTextView)
        let controller = try XCTUnwrap(note.contentViewController as? DesktopNoteContentController)
        XCTAssertTrue(controller.selectionMayExist)

        let editButton = try desktopNoteEditButton(in: note)
        editButton.performClick(nil)
        XCTAssertTrue(editButton.isHidden)
        let editor = try XCTUnwrap(note.firstResponder as? LiveEditorTextView)
        XCTAssertTrue(editor.enclosingScrollView?.verticalRulerView is SimpleLineNumberRulerView)
        XCTAssertEqual(editor.font, FontManager.shared.editorFont)
        XCTAssertFalse(editor.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertEqual(editor.string, original)
        XCTAssertLessThan(editor.selectedRange().location, 40)
        let updated = "Edited " + original
        editor.string = updated
        let saved = expectation(description: "Edited note saved to history")
        let observation = adapter.$history.first { $0.first?.content == updated }.sink { _ in saved.fulfill() }
        defer { observation.cancel() }
        note.resignKey()
        await fulfillment(of: [saved], timeout: 2)
        XCTAssertEqual(adapter.history.first?.title, title)
        XCTAssertEqual(adapter.history.first?.categoryIDs, [BuiltInCategory.ocr])
        XCTAssertFalse(editButton.isHidden)
    }
    func testEscapeCancelsEditingWithoutUnpinningTheNote() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let service = ModernClipboardService(testRepository: try SwiftDataRepository.make(inMemory: true))
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter)
        let title = UUID().uuidString
        let original = "Original note content"
        try await adapter.createHistoryItem(title: title, content: original, categoryChanges: [:])
        let item = try XCTUnwrap(adapter.history.first)
        await coordinator.toggle(item.id, on: screen)
        let note = try XCTUnwrap(NSApp.windows.first { $0.title == title } as? DesktopNotePanel)
        defer { note.close() }
        simulateDesktopNoteLiveResize(note, to: note.minSize)
        let viewingFrame = note.frame
        try desktopNoteEditButton(in: note).performClick(nil)
        let editor = try XCTUnwrap(note.firstResponder as? LiveEditorTextView)
        XCTAssertGreaterThan(note.minSize.height, viewingFrame.height)
        XCTAssertGreaterThanOrEqual(note.frame.height, note.minSize.height)
        editor.string = "Unsaved draft"
        let escape = try desktopNoteKeyEvent(kVK_Escape, characters: "\u{1B}", modifiers: [], for: note)

        note.sendEvent(escape)
        XCTAssertFalse(note.firstResponder is LiveEditorTextView)
        XCTAssertEqual(adapter.history.first?.content, original)
        XCTAssertEqual(note.frame, viewingFrame)

        note.sendEvent(escape)
        await Task.yield()
        XCTAssertTrue(note.isVisible)
        XCTAssertTrue(coordinator.isPosted(item.id))
    }

    func testDesktopNoteEditingToolsModifyTheDraftAndSupportUndo() throws {
        let original = "  {\"例\":\"📝\"} \n"
        let editor = DesktopNoteEditor(text: original, onCancel: {}, onSave: {})
        let window = NSWindow(contentRect: screenFrame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        editor.view.translatesAutoresizingMaskIntoConstraints = true
        window.contentView = editor.view
        window.makeFirstResponder(editor.textView)
        let menu = editor.makeToolsMenu()
        let undo = try XCTUnwrap(editor.textView.undoManager)

        undo.beginUndoGrouping()
        menu.performActionForItem(at: 0)
        undo.endUndoGrouping()
        XCTAssertEqual(editor.textView.string, "{\"例\":\"📝\"}")
        undo.undo()
        XCTAssertEqual(editor.textView.string, original)

        let jsonIndex = try XCTUnwrap(menu.items.firstIndex {
            $0.representedObject as? String == ClipboardTextFormat.json.rawValue
        })
        menu.performActionForItem(at: jsonIndex)
        XCTAssertEqual(editor.textView.string, try ClipboardTextFormatter.format(original, as: .json))

        let yaml = "tasks: [first, second]"
        editor.textView.string = yaml
        menu.performActionForItem(at: jsonIndex)
        XCTAssertEqual(editor.textView.string, yaml)
        let yamlIndex = try XCTUnwrap(menu.items.firstIndex {
            $0.representedObject as? String == ClipboardTextFormat.yaml.rawValue
        })
        menu.performActionForItem(at: yamlIndex)
        XCTAssertEqual(editor.textView.string, try ClipboardTextFormatter.format(yaml, as: .yaml))

        menu.performActionForItem(at: menu.numberOfItems - 1)
        XCTAssertTrue(editor.textView.string.isEmpty)
        XCTAssertEqual(editor.originalText, original)
    }

    func testContextClickKeepsTheEditorSelection() async throws {
        let onSave: (String, Bool) async throws -> Void = { _, _ in }
        let note = DesktopNotePanel(item: ClipItem(content: "First and second word"), screenFrame: screenFrame, onSave: onSave)
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }
        try desktopNoteEditButton(in: note).performClick(nil)
        let editor = try XCTUnwrap(note.firstResponder as? NSTextView)
        editor.layoutSubtreeIfNeeded()
        let position = NSPoint(x: editor.visibleRect.midX, y: editor.visibleRect.midY)
        let point = editor.convert(position, to: nil)

        for range in [NSRange(location: 0, length: 0), NSRange(location: 0, length: 5)] {
            editor.setSelectedRange(range)
            let click = try desktopNoteMouseEvent(.rightMouseDown, at: point, for: note)
            let context = try XCTUnwrap(note.contextMenu(for: click))
            XCTAssertIdentical(context.view, editor)
            XCTAssertTrue(context.menu.items.contains { $0.action == #selector(NSText.paste(_:)) })
            XCTAssertEqual(editor.selectedRange(), range)
        }
    }
}
