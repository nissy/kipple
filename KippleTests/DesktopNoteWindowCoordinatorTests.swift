import AppKit
import Combine
import XCTest
@testable import Kipple

@MainActor
final class DesktopNoteWindowCoordinatorTests: XCTestCase {
    private let screenFrame = NSRect(x: 0, y: 0, width: 900, height: 700)

    func testClosingAndTogglingNotesUpdatesOnlyTheMatchingHistoryItem() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let service = ModernClipboardService(testRepository: try SwiftDataRepository.make(inMemory: true))
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter)
        let title = UUID().uuidString
        let secondTitle = UUID().uuidString
        try await adapter.createHistoryItem(title: title, content: "First note", categoryChanges: [:])
        let first = try XCTUnwrap(adapter.history.first)
        try await adapter.createHistoryItem(title: secondTitle, content: "Second note", categoryChanges: [:])
        let second = try XCTUnwrap(adapter.history.first)
        defer {
            for window in NSApp.windows where window.title == title || window.title == secondTitle {
                window.close()
            }
        }

        await coordinator.toggle(first.id, on: screen)
        await coordinator.toggle(second.id, on: screen)
        XCTAssertTrue(coordinator.isPosted(first.id))
        XCTAssertTrue(coordinator.isPosted(second.id))

        let firstNote = try XCTUnwrap(NSApp.windows.first { $0.title == title })
        XCTAssertTrue(firstNote.isVisible)
        XCTAssertFalse(firstNote.hidesOnDeactivate)
        XCTAssertTrue(firstNote.isMovable)
        XCTAssertGreaterThan(firstNote.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertLessThan(firstNote.level.rawValue, NSWindow.Level.normal.rawValue)

        firstNote.performClose(nil)
        XCTAssertFalse(firstNote.isVisible)
        for _ in 0..<20 where coordinator.isPosted(first.id) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(coordinator.isPosted(first.id))
        XCTAssertTrue(coordinator.isPosted(second.id))

        await coordinator.toggle(first.id, on: screen)
        await coordinator.toggle(second.id, on: screen)
        XCTAssertTrue(coordinator.isPosted(first.id))
        XCTAssertFalse(coordinator.isPosted(second.id))
    }

    func testSavingHistoryEditsUpdatesTheOpenNoteInPlace() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository)
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter)
        let originalTitle = UUID().uuidString
        try await adapter.createHistoryItem(title: originalTitle, content: "Short note", categoryChanges: [:])
        let item = try XCTUnwrap(adapter.history.first)
        await coordinator.toggle(item.id, on: screen)
        let note = try XCTUnwrap(NSApp.windows.first { $0.title == originalTitle })
        defer { note.close() }
        let topLeft = NSPoint(x: screen.visibleFrame.minX + 80, y: screen.visibleFrame.maxY - 80)
        note.setFrameTopLeftPoint(topLeft)
        let before = note.frame
        let glass = try XCTUnwrap(note.contentView?.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        let blue = NSMenuItem()
        blue.representedObject = "Blue Note Color"
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("changeColor:"), to: note, from: blue))
        let strip = try XCTUnwrap(note.contentView?.subviews.first { $0.layer?.backgroundColor == NSColor.systemBlue.cgColor })

        let text = (1...10).map { "Line \($0) of the updated note" }.joined(separator: "\n")
        try await adapter.updateDetails(itemID: item.id, title: nil, content: text, categoryChanges: [:])

        XCTAssertGreaterThan(note.frame.height, before.height)
        XCTAssertEqual(note.frame.minX, before.minX)
        XCTAssertEqual(note.frame.maxY, before.maxY)

        try await adapter.updateDetails(itemID: item.id, title: "Updated title", content: nil, categoryChanges: [:])
        XCTAssertEqual(note.title, "Updated title")

        try await adapter.updateDetails(itemID: item.id, title: "", content: nil, categoryChanges: [:])
        XCTAssertTrue(note.title.isEmpty)
        XCTAssertTrue(note.isVisible)
        XCTAssertTrue(coordinator.isPosted(item.id))
        XCTAssertIdentical(note.contentView?.subviews.first, glass)
        XCTAssertEqual(strip.layer?.backgroundColor, NSColor.systemBlue.cgColor)
    }

    func testHistoryIsProtectedUntilTheDesktopNoteIsRemoved() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository) { _ in 1 }
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter)
        let title = UUID().uuidString
        try await adapter.createHistoryItem(title: title, content: "Pinned history", categoryChanges: [:])
        let item = try XCTUnwrap(adapter.history.first)
        await coordinator.toggle(item.id, on: screen)
        let note = try XCTUnwrap(NSApp.windows.first { $0.title == title })
        defer { note.close() }

        await adapter.deleteItem(item)
        XCTAssertEqual(adapter.history.map(\.id), [item.id])

        await service.setMaxHistoryItems(1)
        try await adapter.createHistoryItem(title: nil, content: "Older history", categoryChanges: [:])
        try await adapter.createHistoryItem(title: nil, content: "Newest history", categoryChanges: [:])
        XCTAssertEqual(adapter.history.map(\.content), ["Newest history", item.content])

        // A stale row with the same content must preserve the identity used by the open note.
        await service.recopyFromHistory(ClipItem(content: item.content))
        let recopiedHistory = await service.getHistory()
        XCTAssertEqual(recopiedHistory.first?.id, item.id)
        await service.loadHistoryFromRepository()

        let cleared = try await adapter.clearHistory(keepingCategories: true).get()
        XCTAssertEqual(cleared, 1)
        XCTAssertEqual(adapter.history.map(\.id), [item.id])
        let retained = try await repository.loadAll()
        XCTAssertEqual(retained.map(\.id), [item.id])

        await coordinator.toggle(item.id, on: screen)
        XCTAssertFalse(coordinator.isPosted(item.id))
        XCTAssertEqual(adapter.history.map(\.id), [item.id])
        await adapter.deleteItem(item)
        XCTAssertTrue(adapter.history.isEmpty)

        await coordinator.toggle(item.id, on: screen)
        XCTAssertFalse(coordinator.isPosted(item.id))
    }

    func testTransparencySettingUpdatesAnOpenNoteWithoutFadingItsColorStrip() async throws {
        let settings = AppSettings.shared
        let previous = UserDefaults.standard.object(forKey: AppSettings.Keys.desktopNoteTransparency)
        defer {
            UserDefaults.standard.set(previous, forKey: AppSettings.Keys.desktopNoteTransparency)
        }
        settings.desktopNoteTransparency = 0.25
        let service = ModernClipboardService(testRepository: try SwiftDataRepository.make(inMemory: true))
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter)
        let title = UUID().uuidString
        try await adapter.createHistoryItem(title: title, content: "A translucent note", categoryChanges: [:])
        let item = try XCTUnwrap(adapter.history.first)
        await coordinator.toggle(item.id, on: try XCTUnwrap(NSScreen.main))
        let note = try XCTUnwrap(NSApp.windows.first { $0.title == title })
        defer { note.close() }
        let glass = try XCTUnwrap(note.contentView?.subviews.compactMap { $0 as? NSGlassEffectView }.first)
        XCTAssertEqual(glass.alphaValue, 0.75, accuracy: 0.001)
        let orange = NSMenuItem()
        orange.representedObject = "Orange Note Color"
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("changeColor:"), to: note, from: orange))
        let strip = try XCTUnwrap(note.contentView?.subviews.first {
            $0.layer?.backgroundColor == NSColor.systemOrange.cgColor
        })
        settings.desktopNoteTransparency = 0.8
        for _ in 0..<20 where glass.alphaValue > 0.21 {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(glass.alphaValue, 0.2, accuracy: 0.001)
        XCTAssertEqual(strip.alphaValue, 1)
        XCTAssertEqual(strip.layer?.backgroundColor?.alpha, 1)
        XCTAssertFalse(strip.isHidden)

        let none = NSMenuItem()
        none.representedObject = "No Note Color"
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("changeColor:"), to: note, from: none))
        XCTAssertTrue(strip.isHidden)
    }

    func testNoteFitsShortAndWrappedContentAndCapsLongPreview() {
        let short = DesktopNotePanel(item: ClipItem(content: "Short note"), screenFrame: screenFrame)
        let wrapped = DesktopNotePanel(
            item: ClipItem(content: String(repeating: "Text that wraps across lines. ", count: 7)),
            screenFrame: screenFrame
        )
        let long = DesktopNotePanel(
            item: ClipItem(content: String(repeating: "Another line\n", count: 90)),
            screenFrame: screenFrame
        )
        defer {
            [short, wrapped, long].forEach { $0.close() }
        }

        XCTAssertLessThan(short.frame.width, wrapped.frame.width)
        XCTAssertLessThan(short.frame.height, wrapped.frame.height)
        XCTAssertLessThan(wrapped.frame.height, long.frame.height)
        XCTAssertLessThan(long.frame.height, screenFrame.height)
        XCTAssertTrue(short.title.isEmpty)
        XCTAssertEqual(short.titleVisibility, .hidden)
    }

    func testNoteDisplaysTheHistoryTitle() {
        let title = "Review notes for the desktop release"
        let item = ClipItem(content: "Short note", metadata: ClipMetadata(title: title))
        let note = DesktopNotePanel(item: item, screenFrame: screenFrame)
        let untitled = DesktopNotePanel(item: ClipItem(content: "Short note"), screenFrame: screenFrame)
        defer {
            note.close()
            untitled.close()
        }

        XCTAssertEqual(note.title, title)
        XCTAssertGreaterThan(note.frame.height, untitled.frame.height)
    }

    func testMarkdownPreviewRendersBlocksAndInlineFormatting() throws {
        let source = """
        # Heading

        **Bold** and \\*literal\\* and `code`

        1. Numbered
           - Nested

        > Quote

        ~~~
        plain code block
        ~~~
        """
        let rendered = try XCTUnwrap(DesktopNoteMarkdown.render(source, baseFont: .systemFont(ofSize: 13)))
        let text = String(rendered.characters)
        XCTAssertTrue(text.hasPrefix("Heading\nBold and *literal* and code\n1. Numbered\n  • Nested\n│ Quote\n"))
        XCTAssertTrue(text.contains("plain code block"))
        let bold = try XCTUnwrap(rendered.runs.first { String(rendered[$0.range].characters) == "Bold" })
        XCTAssertTrue(bold.inlinePresentationIntent?.contains(.stronglyEmphasized) == true)
    }

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

        let point = NSPoint(x: 35, y: note.frame.height - 50)
        note.sendEvent(try mouseEvent(.leftMouseDown, at: point, for: note, clickCount: 2))
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

    func testDraggingTheNoteBodyMovesTheWindow() throws {
        let note = DesktopNotePanel(item: ClipItem(content: "Drag this text"), screenFrame: screenFrame)
        defer { note.close() }
        let contentView = try XCTUnwrap(note.contentView)
        let start = contentView.convert(NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY), to: nil)
        let origin = note.frame.origin
        let end = NSPoint(x: start.x + 100, y: start.y + 80)

        note.sendEvent(try mouseEvent(.leftMouseDown, at: start, for: note))
        note.sendEvent(try mouseEvent(.leftMouseDragged, at: end, for: note))
        note.sendEvent(try mouseEvent(.leftMouseUp, at: start, for: note))

        XCTAssertEqual(note.frame.origin, NSPoint(x: origin.x + 100, y: origin.y + 80))
    }

    func testClickingAMarkdownLinkOpensItAndDraggingMovesTheNote() async throws {
        var opened: [URL] = []
        let note = DesktopNotePanel(
            item: ClipItem(content: "[Open the example](https://example.com)"),
            screenFrame: screenFrame,
            displayMode: .markdown,
            onSave: nil,
            onChangeCategory: nil
        ) { url in
            opened.append(url)
            return .handled
        }
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }
        let contentView = try XCTUnwrap(note.contentView)
        contentView.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let start = NSPoint(x: 29, y: note.frame.height - 28)
        let origin = note.frame.origin

        note.sendEvent(try mouseEvent(.leftMouseDown, at: start, for: note))
        note.sendEvent(try mouseEvent(.leftMouseUp, at: start, for: note))
        XCTAssertEqual(opened.map(\.absoluteString), ["https://example.com"])
        XCTAssertEqual(note.frame.origin, origin)

        let end = NSPoint(x: start.x + 60, y: start.y + 45)
        note.sendEvent(try mouseEvent(.leftMouseDown, at: start, for: note))
        note.sendEvent(try mouseEvent(.leftMouseDragged, at: end, for: note))
        note.sendEvent(try mouseEvent(.leftMouseUp, at: start, for: note))
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(note.frame.origin, NSPoint(x: origin.x + 60, y: origin.y + 45))
    }

    func testDoubleClickEditsFullTextAndFocusLossSavesItToHistory() async throws {
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
        let point = NSPoint(x: 35, y: note.frame.height - 70)

        note.sendEvent(try mouseEvent(.leftMouseDown, at: point, for: note))
        note.sendEvent(try mouseEvent(.leftMouseUp, at: point, for: note))
        XCTAssertFalse(note.firstResponder is NSTextView)

        note.sendEvent(try mouseEvent(.leftMouseDown, at: point, for: note, clickCount: 2))
        let editor = try XCTUnwrap(note.firstResponder as? NSTextView)
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
    }

    private func mouseEvent(
        _ type: NSEvent.EventType, at point: NSPoint, for note: NSWindow, clickCount: Int = 1
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: note.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        ))
    }
}
