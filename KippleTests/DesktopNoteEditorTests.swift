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
        note.editor?.titleField.stringValue = "Updated Markdown title"
        let showMarkdown = settings.localizedString("Show Markdown")
        button.performClick(nil)
        for _ in 0..<30 where button.toolTip != showMarkdown {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(adapter.history.first?.content, edited)
        XCTAssertEqual(adapter.history.first?.title, "Updated Markdown title")
        XCTAssertEqual(note.title, "Updated Markdown title")
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
        note.editor?.titleField.stringValue = "Unsaved title"
        let escape = try desktopNoteKeyEvent(kVK_Escape, characters: "\u{1B}", modifiers: [], for: note)

        note.sendEvent(escape)
        XCTAssertFalse(note.firstResponder is LiveEditorTextView)
        XCTAssertEqual(adapter.history.first?.content, original)
        XCTAssertEqual(adapter.history.first?.title, title)
        XCTAssertEqual(note.frame, viewingFrame)

        note.sendEvent(escape)
        await Task.yield()
        XCTAssertTrue(note.isVisible)
        XCTAssertTrue(coordinator.isPosted(item.id))
    }

    func testDesktopNoteEditingToolsModifyTheDraftAndSupportUndo() throws {
        let original = "  {\"例\":\"📝\"} \n"
        let editor = DesktopNoteEditor(title: nil, text: original, onCancel: {}, onSave: {})
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
        let onSave: (String?, String?, Bool) async throws -> Void = { _, _, _ in }
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

    func testTitleOnlyEditsPreserveRichTextAndCanAddOrRemoveTheTitle() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let entry = NSPasteboardItem()
        let content = "Rich note content"
        entry.setString(content, forType: .string)
        entry.setString("<strong>Rich note content</strong>", forType: .html)
        XCTAssertTrue(pasteboard.writeObjects([entry]))
        let richText = try XCTUnwrap(ClipboardRichText(pasteboard: pasteboard))
        let item = ClipItem(content: content, metadata: ClipMetadata(sourceURI: "https://example.com/task"), richText: richText)
        let repository = try SwiftDataRepository.make(inMemory: true)
        try await repository.save([item])
        let service = ModernClipboardService(testRepository: repository, loadOnStartup: true)
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter)
        await coordinator.toggle(item.id, on: screen)
        let note = try XCTUnwrap(NSApp.windows.compactMap { $0 as? DesktopNotePanel }.first {
            $0.noteContentController.hostingController.rootView.item.id == item.id
        })
        defer { note.close() }

        for (draft, expected) in [("進捗の確認", "進捗の確認"), (" ", nil)] {
            try desktopNoteEditButton(in: note).performClick(nil)
            let titleField = try XCTUnwrap(note.editor?.titleField)
            XCTAssertEqual(titleField.stringValue, adapter.history.first?.title ?? "")
            XCTAssertTrue(note.makeFirstResponder(titleField))
            let fieldEditor = try XCTUnwrap(titleField.currentEditor() as? NSTextView)
            fieldEditor.string = draft
            let selection = NSRange(location: 0, length: 1)
            fieldEditor.setSelectedRange(selection)
            let point = titleField.convert(NSPoint(x: titleField.bounds.midX, y: titleField.bounds.midY), to: nil)
            let click = try desktopNoteMouseEvent(.rightMouseDown, at: point, for: note)
            XCTAssertIdentical(note.contextMenu(for: click)?.view, fieldEditor)
            XCTAssertEqual(fieldEditor.selectedRange(), selection)
            let save = try desktopNoteKeyEvent(kVK_Return, characters: "\r", modifiers: [.command], for: note)
            note.sendEvent(save)
            for _ in 0..<50 where note.editor != nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNil(note.editor)
            XCTAssertEqual(adapter.history.first?.title, expected)
            XCTAssertEqual(adapter.history.first?.content, content)
            XCTAssertEqual(adapter.history.first?.richText, richText)
            XCTAssertEqual(adapter.history.first?.metadata?.sourceURI, item.metadata?.sourceURI)
            XCTAssertEqual(note.title, expected ?? "")
            let stored = try await repository.load(ids: [item.id])
            XCTAssertEqual(stored.first?.title, expected)
        }
    }
}
