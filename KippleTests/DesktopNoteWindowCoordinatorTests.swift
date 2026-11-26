import AppKit
import Carbon.HIToolbox
import Combine
import XCTest
@testable import Kipple

@MainActor
final class DesktopNoteWindowCoordinatorTests: XCTestCase {
    private let screenFrame = NSRect(x: 0, y: 0, width: 900, height: 700)

    func testCopyButtonRecopiesTheHistoryItemWithItsFormatting() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let entry = NSPasteboardItem()
        entry.setString("Sample note", forType: .string)
        entry.setString("<strong>Sample note</strong>", forType: .html)
        pasteboard.writeObjects([entry])
        let richText = try XCTUnwrap(ClipboardRichText(pasteboard: pasteboard))
        pasteboard.clearContents()

        let repository = try SwiftDataRepository.make(inMemory: true)
        let title = UUID().uuidString
        let item = ClipItem(content: "Sample note", metadata: ClipMetadata(title: title), richText: richText)
        try await repository.save([item, ClipItem(content: "Newer item")])
        let service = ModernClipboardService(testRepository: repository, loadOnStartup: true) { item in
            ClipboardRichText.write(item, to: pasteboard)
        }
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter)
        await coordinator.toggle(item.id, on: screen)
        let note = try XCTUnwrap(NSApp.windows.first { $0.title == title } as? DesktopNotePanel)
        defer { note.close() }
        let toolbar = try XCTUnwrap(note.contentView?.subviews.compactMap { $0 as? NSStackView }.first)
        let copyButton = try XCTUnwrap(toolbar.views.first as? NSButton)
        XCTAssertEqual(copyButton.toolTip, AppSettings.shared.localizedString("Copy"))
        let originalIcon = try XCTUnwrap(copyButton.image)
        note.setContentSize(NSSize(width: 340, height: 220))
        note.contentView?.layoutSubtreeIfNeeded()
        let toolbarFrames = toolbar.views.map(\.frame)

        copyButton.performClick(nil)
        await adapter.flushPendingSaves()

        XCTAssertEqual(pasteboard.string(forType: .string), item.content)
        XCTAssertEqual(ClipboardRichText(pasteboard: pasteboard), richText)
        XCTAssertEqual(adapter.history.first?.id, item.id)
        XCTAssertEqual(adapter.history.count, 2)
        XCTAssertTrue(note.isVisible)
        XCTAssertNotIdentical(try XCTUnwrap(copyButton.image), originalIcon)
        note.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(toolbar.views.map(\.frame), toolbarFrames)
        try await Task.sleep(for: .milliseconds(1_100))
        XCTAssertIdentical(copyButton.image, originalIcon)
    }

    func testCopyButtonDoesNotShowSuccessWhenTheClipboardWriteFails() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let repository = try SwiftDataRepository.make(inMemory: true)
        let service = ModernClipboardService(testRepository: repository) { _ in -1 }
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter)
        let title = UUID().uuidString
        try await adapter.createHistoryItem(title: title, content: "Test note", categoryChanges: [:])
        let item = try XCTUnwrap(adapter.history.first)
        await coordinator.toggle(item.id, on: screen)
        let note = try XCTUnwrap(NSApp.windows.first { $0.title == title } as? DesktopNotePanel)
        defer { note.close() }
        let toolbar = try XCTUnwrap(note.contentView?.subviews.compactMap { $0 as? NSStackView }.first)
        let button = try XCTUnwrap(toolbar.views.first as? NSButton)
        let originalIcon = try XCTUnwrap(button.image)
        button.performClick(nil)
        await adapter.flushPendingSaves()
        XCTAssertIdentical(button.image, originalIcon)
    }

    func testRestoresPositionSizeAndColorFromAnOlderHistoryItem() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let previousLimit = AppSettings.shared.maxHistoryItems
        let previousDisplay = AppSettings.shared.desktopNoteDisplayID
        AppSettings.shared.desktopNoteDisplayID = ""
        defer {
            defaults.removePersistentDomain(forName: suite)
            AppSettings.shared.maxHistoryItems = previousLimit
            AppSettings.shared.desktopNoteDisplayID = previousDisplay
        }
        let repository = try SwiftDataRepository.make(inMemory: true)
        let adapter = ModernClipboardServiceAdapter(
            modernService: ModernClipboardService(testRepository: repository), refreshPeriodically: false
        )
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter, defaults: defaults)
        let title = UUID().uuidString
        try await adapter.createHistoryItem(title: title, content: "Restorable note", categoryChanges: [:])
        let item = try XCTUnwrap(adapter.history.first)
        await coordinator.toggle(item.id, on: screen)
        let original = try XCTUnwrap(NSApp.windows.first { $0.title == title } as? DesktopNotePanel)
        original.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 54, y: screen.visibleFrame.maxY - 60))
        simulateDesktopNoteLiveResize(original, to: NSSize(width: 274, height: 179))
        let resized = original.frame
        XCTAssertEqual(DesktopNotePlacement.load(from: defaults)[item.id]?.frame, resized)
        let point = NSPoint(x: 150, y: 90)
        let end = NSPoint(x: point.x + 35, y: point.y - 24)
        original.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: point, for: original))
        original.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: original))
        original.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: point, for: original))
        XCTAssertEqual(original.frame.origin, NSPoint(x: resized.minX + 35, y: resized.minY - 24))
        XCTAssertEqual(DesktopNotePlacement.load(from: defaults)[item.id]?.frame, original.frame)
        let color = NSMenuItem()
        color.representedObject = DesktopNoteColor.pink.rawValue
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("changeColor:"), to: original, from: color))
        let saved = try XCTUnwrap(DesktopNotePlacement.load(from: defaults)[item.id])
        XCTAssertEqual(saved.frame, original.frame)
        XCTAssertEqual(saved.color, .pink)
        XCTAssertTrue(saved.usesManualSize)
        coordinator.prepareForTermination()
        original.close()

        try await repository.save((1...16).map { ClipItem(content: "Newer item \($0)") })
        AppSettings.shared.maxHistoryItems = 1
        let recentItems = try await repository.load(limit: 12)
        XCTAssertFalse(recentItems.contains { $0.id == item.id })
        let reopenedService = ModernClipboardService(
            testRepository: repository, loadOnStartup: true, desktopNoteItemIDs: [item.id]
        )
        let reopenedAdapter = ModernClipboardServiceAdapter(modernService: reopenedService, refreshPeriodically: false)
        let reopened = DesktopNoteWindowCoordinator(adapter: reopenedAdapter, defaults: defaults)
        AppSettings.shared.desktopNoteDisplayID = DesktopNoteDisplay.connected.first {
            $0.screen.frame != screen.frame
        }?.id ?? UUID().uuidString
        await reopened.restoreNotes()
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == title && $0.isVisible } as? DesktopNotePanel)
        defer { window.close() }
        XCTAssertNotIdentical(window, original)
        XCTAssertTrue(reopened.isPosted(item.id))
        XCTAssertEqual(window.frame, saved.frame)
        XCTAssertEqual(window.placement.color, .pink)

        let retained = try await repository.load(ids: [item.id])
        XCTAssertEqual(retained.map(\.id), [item.id])
        await reopened.toggle(item.id, on: screen)
        XCTAssertTrue(DesktopNotePlacement.load(from: defaults).isEmpty)
        await reopened.restoreNotes()
        XCTAssertFalse(reopened.isPosted(item.id))
    }

    func testNewNotesUseTheSelectedDisplayWithTheOriginatingDisplayAsFallback() async throws {
        let displays = DesktopNoteDisplay.connected
        let originating = try XCTUnwrap(displays.first)
        let selected = try XCTUnwrap(displays.last)
        let settings = AppSettings.shared
        let previousDisplay = settings.desktopNoteDisplayID
        defer { settings.desktopNoteDisplayID = previousDisplay }
        let service = ModernClipboardService(testRepository: try SwiftDataRepository.make(inMemory: true))
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter)

        settings.desktopNoteDisplayID = selected.id
        let title = UUID().uuidString
        try await adapter.createHistoryItem(title: title, content: "Selected display note", categoryChanges: [:])
        let item = try XCTUnwrap(adapter.history.first)
        await coordinator.toggle(item.id, on: originating.screen)
        let note = try XCTUnwrap(NSApp.windows.first { $0.title == title } as? DesktopNotePanel)
        defer { note.close() }
        XCTAssertTrue(selected.screen.visibleFrame.contains(note.frame))
        let originalFrame = note.frame

        let unavailable = UUID().uuidString
        settings.desktopNoteDisplayID = unavailable
        let fallbackTitle = UUID().uuidString
        try await adapter.createHistoryItem(title: fallbackTitle, content: "Fallback display note", categoryChanges: [:])
        let fallbackItem = try XCTUnwrap(adapter.history.first)
        await coordinator.toggle(fallbackItem.id, on: originating.screen)
        let fallback = try XCTUnwrap(NSApp.windows.first { $0.title == fallbackTitle } as? DesktopNotePanel)
        defer { fallback.close() }
        XCTAssertTrue(originating.screen.visibleFrame.contains(fallback.frame))
        XCTAssertEqual(settings.desktopNoteDisplayID, unavailable)
        XCTAssertEqual(note.frame, originalFrame)
    }

    func testDisplaySelectionResolvesAgainWhenTheSavedMonitorIsAvailable() throws {
        let displays = DesktopNoteDisplay.connected
        let selected = try XCTUnwrap(displays.last)
        let fallback = displays.first { $0.id != selected.id }
        let remaining = displays.filter { $0.id != selected.id }.map(\.screen)

        let whileDisconnected = DesktopNoteDisplay.destination(
            preferredID: selected.id, originatingScreen: fallback?.screen, among: remaining
        )
        XCTAssertEqual(whileDisconnected?.frame, fallback?.screen.frame)
        let afterReconnect = DesktopNoteDisplay.destination(
            preferredID: selected.id, originatingScreen: fallback?.screen, among: displays.map(\.screen)
        )
        XCTAssertEqual(afterReconnect?.frame, selected.screen.frame)
    }

    func testRestoreKeepsNotesOnScreenAndRemovesMissingHistoryReferences() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let suite = UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let existing = ClipItem(content: "Note from another display", metadata: ClipMetadata(title: UUID().uuidString))
        let missing = UUID()
        let placement = DesktopNotePlacement(
            frame: CGRect(x: 100_000, y: 100_000, width: 250, height: 150), color: .none, usesManualSize: false
        )
        DesktopNotePlacement.save([existing.id: placement, missing: placement], to: defaults)
        let repository = try SwiftDataRepository.make(inMemory: true)
        try await repository.save([existing])
        let service = ModernClipboardService(
            testRepository: repository, loadOnStartup: true, desktopNoteItemIDs: [existing.id, missing]
        )
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        let coordinator = DesktopNoteWindowCoordinator(adapter: adapter, defaults: defaults)
        await coordinator.restoreNotes()
        let note = try XCTUnwrap(NSApp.windows.first { $0.title == existing.title } as? DesktopNotePanel)
        defer { note.close() }
        XCTAssertTrue(screen.visibleFrame.contains(note.frame))
        XCTAssertEqual(note.placement.color, .none)
        XCTAssertNil(DesktopNotePlacement.load(from: defaults)[missing])
        await coordinator.restoreNotes()
        XCTAssertEqual(NSApp.windows.filter { $0.title == existing.title && $0.isVisible }.count, 1)
    }

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
        XCTAssertTrue(firstNote.canBecomeKey)
        XCTAssertGreaterThan(firstNote.level.rawValue, Int(CGWindowLevelForKey(.desktopIconWindow)))
        XCTAssertEqual(firstNote.level.rawValue, NSWindow.Level.normal.rawValue - 1)

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
        let content = try XCTUnwrap(note.contentView)
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
        XCTAssertIdentical(note.contentView, content)
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

    func testNoteRendersAnOpaqueBackgroundInLightAndDarkAppearances() throws {
        let note = DesktopNotePanel(item: ClipItem(content: "Short note"), screenFrame: screenFrame)
        note.setContentSize(NSSize(width: 260, height: 160))
        defer { note.close() }
        let content = try XCTUnwrap(note.contentView)
        note.appearance = NSAppearance(named: .aqua)
        let light = try renderNoteBackground(in: content)
        let colors = DesktopNoteColor.allCases.compactMap { $0.fill?.cgColor }
        let strip = try XCTUnwrap(content.subviews.first { view in
            view.layer?.backgroundColor.map { colors.contains($0) } ?? false
        })
        XCTAssertFalse(strip.isHidden)

        let orange = NSMenuItem()
        orange.representedObject = "Orange Note Color"
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("changeColor:"), to: note, from: orange))
        XCTAssertEqual(strip.layer?.backgroundColor, NSColor.systemOrange.cgColor)

        note.appearance = NSAppearance(named: .darkAqua)
        let dark = try renderNoteBackground(in: content)
        XCTAssertEqual(light.alphaComponent, 1)
        XCTAssertEqual(dark.alphaComponent, 1)
        XCTAssertGreaterThan(light.redComponent, dark.redComponent)
        XCTAssertEqual(strip.alphaValue, 1)
        XCTAssertEqual(strip.layer?.backgroundColor?.alpha, 1)
        XCTAssertFalse(strip.isHidden)

        let none = NSMenuItem()
        none.representedObject = "No Note Color"
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("changeColor:"), to: note, from: none))
        XCTAssertTrue(strip.isHidden)
    }

    private func renderNoteBackground(in content: NSView) throws -> NSColor {
        content.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let sample = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
        return try XCTUnwrap(sample?.usingColorSpace(.deviceRGB))
    }

    func testNoteFitsShortAndWrappedContentAndCapsInitialHeight() {
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
        XCTAssertEqual(long.frame.height, screenFrame.height)
        XCTAssertTrue(short.title.isEmpty)
        XCTAssertEqual(short.titleVisibility, .hidden)
    }

    func testMarkdownNoteFitsItsRenderedBodyWithoutMovingItsTopEdge() async throws {
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let content = """
        # Work items

        ## Release

        | Item | Status |
        | --- | --- |
        | Review | Done |
        | Publish | Waiting |

        ```
        make run
        ```

        ## Next steps

        Follow up after the release.
        """
        var item = ClipItem(content: content)
        let note = DesktopNotePanel(item: item, screenFrame: screen, displayMode: .markdown)
        let topLeft = NSPoint(x: screen.minX + 40, y: screen.maxY - 40)
        note.setFrameTopLeftPoint(topLeft)
        let estimatedHeight = note.frame.height
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }

        let view = try XCTUnwrap(note.contentView)
        let clip = try XCTUnwrap(firstScrollView(in: view)).contentView
        for _ in 0..<50 {
            if note.frame.height > estimatedHeight,
               clip.documentRect.height <= clip.bounds.height + 1,
               let table = firstScrollView(in: clip)?.contentView,
               table.documentRect.width <= table.bounds.width + 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(note.frame.height, estimatedHeight)
        XCTAssertGreaterThan(clip.documentRect.height, 150)
        XCTAssertLessThanOrEqual(clip.documentRect.height, clip.bounds.height + 1)
        let table = try XCTUnwrap(firstScrollView(in: clip)).contentView
        XCTAssertLessThanOrEqual(table.documentRect.width, table.bounds.width + 1)
        XCTAssertEqual(note.frame.minX, topLeft.x)
        XCTAssertEqual(note.frame.maxY, topLeft.y)

        item = item.replacingContent(with: "[Open](https://example.com/\(String(repeating: "a", count: 400)))")
        note.update(from: item)
        XCTAssertEqual(note.frame.width, note.minSize.width)
        XCTAssertEqual(note.frame.height, note.minSize.height)
        XCTAssertEqual(note.frame.maxY, topLeft.y)
    }

    func testRestoredAutomaticNoteKeepsItsSizeUntilTheContentChanges() async throws {
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let text = (1...6).map { "## Step \($0)\n\nReview the release notes." }.joined(separator: "\n\n")
        let item = ClipItem(content: text)
        let note = DesktopNotePanel(item: item, screenFrame: screen, displayMode: .markdown) { _, _ in }
        let saved = NSRect(x: screen.minX + 40, y: screen.maxY - 220, width: 265, height: 180)
        note.restorePlacement(DesktopNotePlacement(frame: saved, color: .none, usesManualSize: false), in: screen)
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }

        let view = try XCTUnwrap(note.contentView)
        let clip = try XCTUnwrap(firstScrollView(in: view)).contentView
        for _ in 0..<50 where clip.documentRect.height <= clip.bounds.height {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertGreaterThan(clip.documentRect.height, clip.bounds.height)
        XCTAssertEqual(note.frame, saved)
        XCTAssertFalse(note.placement.usesManualSize)

        try desktopNoteEditButton(in: note).performClick(nil)
        let editor = try XCTUnwrap(note.firstResponder as? LiveEditorTextView)
        editor.string = "Unsaved draft"
        let escape = try desktopNoteKeyEvent(kVK_Escape, characters: "\u{1B}", modifiers: [], for: note)
        note.sendEvent(escape)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(note.frame, saved)
        XCTAssertFalse(note.placement.usesManualSize)

        note.update(from: item.replacingContent(with: "Ready"))
        XCTAssertLessThan(note.frame.height, saved.height)
        XCTAssertEqual(note.frame.maxY, saved.maxY)
    }

    func testMovingAScreenLimitedNoteUpGivesTheBodyMoreSpace() async throws {
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let item = ClipItem(content: "Follow-up")
        let note = DesktopNotePanel(item: item, screenFrame: screen)
        let top = NSPoint(x: screen.minX + 75, y: screen.minY + 175)
        note.setFrameTopLeftPoint(top)
        note.makeKeyAndOrderFront(nil)
        defer { note.close() }

        note.update(from: item.replacingContent(with: (1...20).map { "Item \($0)" }.joined(separator: "\n")))
        let view = try XCTUnwrap(note.contentView)
        let clip = try XCTUnwrap(firstScrollView(in: view)).contentView
        try await Task.sleep(for: .milliseconds(100))
        let before = note.frame
        XCTAssertEqual(before.minY, screen.minY)
        XCTAssertGreaterThan(clip.documentRect.height, clip.bounds.height)

        let start = NSPoint(x: before.width - 32, y: before.height - 48)
        let distance = screen.maxY - 40 - top.y
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: NSPoint(x: start.x, y: start.y + distance), for: note))
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: start, for: note))

        XCTAssertGreaterThan(note.frame.height, before.height)
        XCTAssertEqual(note.frame.minX, before.minX)
        XCTAssertEqual(note.frame.maxY, screen.maxY - 40)
        XCTAssertFalse(note.placement.usesManualSize)
    }

    func testFitToContentMenuResumesAutomaticSizing() async throws {
        let screen = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let item = ClipItem(content: "Short note")
        let note = DesktopNotePanel(item: item, screenFrame: screen)
        defer { note.close() }
        let saved = NSRect(x: screen.minX + 75, y: screen.maxY - 280, width: 295, height: 200)
        note.restorePlacement(DesktopNotePlacement(frame: saved, color: .yellow, usesManualSize: true), in: screen)
        note.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(50))

        let text = try desktopNoteBodyPoint(in: note, x: 29)
        XCTAssertNil(note.automaticSizeMenu(at: text))
        let blank = NSPoint(x: 120, y: 65)
        let menu = try XCTUnwrap(note.automaticSizeMenu(at: blank))
        XCTAssertEqual(menu.items.first?.title, AppSettings.shared.localizedString("Fit Note to Content"))
        menu.performActionForItem(at: 0)

        XCTAssertFalse(note.placement.usesManualSize)
        XCTAssertEqual(note.placement.color, .yellow)
        XCTAssertEqual(note.frame.minX, saved.minX)
        XCTAssertEqual(note.frame.maxY, saved.maxY)
        XCTAssertLessThan(note.frame.height, saved.height)
        XCTAssertNil(note.automaticSizeMenu(at: blank))

        let height = note.frame.height
        note.update(from: item.replacingContent(with: String(repeating: "Longer note content.\n", count: 12)))
        XCTAssertGreaterThan(note.frame.height, height)
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView { return scrollView }
        for child in view.subviews {
            if let scrollView = firstScrollView(in: child) { return scrollView }
        }
        return nil
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

    func testManuallyResizedNoteKeepsSizeWhenItsContentOrDisplayModeChanges() throws {
        var item = ClipItem(content: "Short note")
        let note = DesktopNotePanel(item: item, screenFrame: screenFrame)
        note.setFrameTopLeftPoint(NSPoint(x: 40, y: 600))
        defer { note.close() }

        let start = note.frame
        simulateDesktopNoteLiveResize(note, to: NSSize(width: start.width + 120, height: start.height + 160))
        let resized = note.frame
        XCTAssertEqual(resized.width, start.width + 120)
        XCTAssertEqual(resized.height, start.height + 160)
        XCTAssertEqual(resized.minX, start.minX)
        XCTAssertEqual(resized.maxY, start.maxY)

        item = item.replacingContent(with: String(repeating: "A longer note body.\n\n", count: 120))
        note.update(from: item)
        XCTAssertEqual(note.frame, resized)

        let stack = try XCTUnwrap(note.contentView?.subviews.compactMap { $0 as? NSStackView }.first)
        let showMarkdown = AppSettings.shared.localizedString("Show Markdown")
        let button = try XCTUnwrap(stack.views.compactMap { $0 as? NSButton }.first { $0.toolTip == showMarkdown })
        button.performClick(nil)
        XCTAssertEqual(note.frame, resized)
    }

    func testManuallyResizedNoteReservesReadingSpaceWhenATitleIsAdded() {
        var item = ClipItem(content: "Note body")
        let note = DesktopNotePanel(item: item, screenFrame: screenFrame)
        note.setFrameTopLeftPoint(NSPoint(x: 40, y: 600))
        defer { note.close() }

        note.setContentSize(NSSize(width: 240, height: 160))
        simulateDesktopNoteLiveResize(note, to: note.minSize)
        let untitled = note.frame
        XCTAssertEqual(untitled.height, 86)

        item.metadata = ClipMetadata(title: "A long history title that wraps onto two lines")
        note.update(from: item)
        let titled = note.frame
        XCTAssertGreaterThan(titled.height, untitled.height)
        XCTAssertEqual(titled.width, untitled.width)
        XCTAssertEqual(titled.maxY, untitled.maxY)

        XCTAssertEqual(titled.height, note.minSize.height)
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

        note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: start, for: note))
        XCTAssertTrue(NSCursor.current === NSCursor.openHand)
        let text = try desktopNoteBodyPoint(in: note, x: 29)
        note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: text, for: note))
        XCTAssertFalse(NSCursor.current === NSCursor.openHand)
        let border = NSPoint(x: 2, y: start.y)
        note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: start, for: note))
        note.sendEvent(try desktopNoteMouseEvent(.mouseMoved, at: border, for: note))
        XCTAssertFalse(NSCursor.current === NSCursor.openHand)

        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: start, for: note))
        XCTAssertTrue(NSCursor.current === NSCursor.closedHand)
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: note))
        XCTAssertTrue(NSCursor.current === NSCursor.closedHand)
        note.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: start, for: note))
        XCTAssertTrue(NSCursor.current === NSCursor.openHand)

        XCTAssertEqual(note.frame.origin, NSPoint(x: origin.x + 100, y: origin.y + 80))
    }

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
}

extension DesktopNoteWindowCoordinatorTests {
    func testThirdExternalCopyPostsOneNoteForTheExistingHistoryItem() async throws {
        let settings = AppSettings.shared
        let previous = settings.desktopNoteOnRepeatedCopy
        let previousDisplay = settings.desktopNoteDisplayID
        let selected = try XCTUnwrap(DesktopNoteDisplay.connected.last)
        settings.desktopNoteOnRepeatedCopy = true
        settings.desktopNoteDisplayID = selected.id
        defer {
            settings.desktopNoteOnRepeatedCopy = previous
            settings.desktopNoteDisplayID = previousDisplay
        }
        let fixture = try RepeatedCopyFixture()
        defer { fixture.pasteboard.releaseGlobally() }
        let text = "Review the desktop release checklist"

        let first = await fixture.copy(text)
        let original = try XCTUnwrap(first)
        _ = await fixture.copy(text)
        await fixture.service.checkClipboardForTesting()
        await fixture.service.recopyFromHistory(original)
        await fixture.service.checkClipboardForTesting()
        XCTAssertTrue(fixture.requests.isEmpty)

        let third = await fixture.copy(text)
        XCTAssertEqual(third?.id, original.id)
        for _ in 0..<50 where !fixture.coordinator.isPosted(original.id) {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(fixture.coordinator.isPosted(original.id))
        let window = try XCTUnwrap(fixture.noteWindow(for: original.id))
        defer { window.close() }
        XCTAssertTrue(selected.screen.visibleFrame.contains(window.frame))

        for _ in 0..<3 { _ = await fixture.copy(text) }
        for _ in 0..<50 where fixture.requests.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(fixture.requests, [original.id, original.id])
        XCTAssertIdentical(fixture.noteWindow(for: original.id), window)
        XCTAssertTrue(fixture.coordinator.isPosted(original.id))
        let history = await fixture.service.getHistory()
        XCTAssertEqual(history.map(\.id), [original.id])
    }

    func testRepeatedCopiesStartOverAfterATimeoutOrDifferentText() async throws {
        let settings = AppSettings.shared
        let previous = settings.desktopNoteOnRepeatedCopy
        settings.desktopNoteOnRepeatedCopy = true
        defer { settings.desktopNoteOnRepeatedCopy = previous }
        let fixture = try RepeatedCopyFixture()
        defer { fixture.pasteboard.releaseGlobally() }
        let text = "Follow up on the action item"

        _ = await fixture.copy(text)
        _ = await fixture.copy(text)
        try await Task.sleep(for: .milliseconds(5_100))
        _ = await fixture.copy(text)
        XCTAssertTrue(fixture.requests.isEmpty)
        _ = await fixture.copy("Another action item")
        _ = await fixture.copy(text)
        _ = await fixture.copy(text)
        XCTAssertTrue(fixture.requests.isEmpty)
        let third = await fixture.copy(text)
        let itemID = try XCTUnwrap(third?.id)
        for _ in 0..<50 where !fixture.coordinator.isPosted(itemID) {
            try await Task.sleep(for: .milliseconds(10))
        }
        defer { fixture.noteWindow(for: itemID)?.close() }
        XCTAssertEqual(fixture.requests, [itemID])
        XCTAssertTrue(fixture.coordinator.isPosted(itemID))
    }

    func testRepeatedCopySettingCanBeTurnedOffAndBackOn() async throws {
        let settings = AppSettings.shared
        let previous = settings.desktopNoteOnRepeatedCopy
        settings.desktopNoteOnRepeatedCopy = false
        defer { settings.desktopNoteOnRepeatedCopy = previous }
        let fixture = try RepeatedCopyFixture()
        defer { fixture.pasteboard.releaseGlobally() }
        let text = "Schedule a follow-up"

        for _ in 0..<3 { _ = await fixture.copy(text) }
        XCTAssertTrue(fixture.requests.isEmpty)

        settings.desktopNoteOnRepeatedCopy = true
        _ = await fixture.copy(text)
        _ = await fixture.copy(text)
        settings.desktopNoteOnRepeatedCopy = false
        settings.desktopNoteOnRepeatedCopy = true
        _ = await fixture.copy(text)
        _ = await fixture.copy(text)
        XCTAssertTrue(fixture.requests.isEmpty)

        let third = await fixture.copy(text)
        let itemID = try XCTUnwrap(third?.id)
        for _ in 0..<50 where !fixture.coordinator.isPosted(itemID) {
            try await Task.sleep(for: .milliseconds(10))
        }
        defer { fixture.noteWindow(for: itemID)?.close() }
        XCTAssertEqual(fixture.requests, [itemID])
        XCTAssertTrue(fixture.coordinator.isPosted(itemID))
    }

    @MainActor
    private final class RepeatedCopyFixture {
        let pasteboard = NSPasteboard.withUniqueName()
        let service: ModernClipboardService
        let coordinator: DesktopNoteWindowCoordinator
        private(set) var requests: [UUID] = []
        private var observation: AnyCancellable?

        init() throws {
            let pasteboard = self.pasteboard
            service = ModernClipboardService(
                testRepository: try SwiftDataRepository.make(inMemory: true),
                clipboardWriter: { item in
                    pasteboard.clearContents()
                    return pasteboard.setString(item.content, forType: .string) ? pasteboard.changeCount : -1
                },
                clipboardReader: ClipboardReader(
                    pasteboard: pasteboard, readAccess: { .alwaysAllow }, readSelection: { _, _ in nil }
                )
            )
            let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
            coordinator = DesktopNoteWindowCoordinator(adapter: adapter)
            observation = adapter.repeatedCopyDesktopNoteRequests.sink { [weak self] in self?.requests.append($0) }
        }

        func copy(_ content: String) async -> ClipItem? {
            pasteboard.clearContents()
            XCTAssertTrue(pasteboard.setString(content, forType: .string))
            await service.checkClipboardForTesting()
            return await service.getHistory().first
        }

        func noteWindow(for itemID: UUID) -> DesktopNotePanel? {
            NSApp.windows.compactMap { $0 as? DesktopNotePanel }.first {
                ($0.contentViewController as? DesktopNoteContentController)?.hostingController.rootView.item.id == itemID
            }
        }
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
}

@MainActor
func desktopNoteKeyEvent(
    _ keyCode: Int, characters: String, modifiers: NSEvent.ModifierFlags, for note: NSWindow
) throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
        windowNumber: note.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: UInt16(keyCode)
    ))
}

@MainActor
func desktopNoteEditButton(in note: DesktopNotePanel) throws -> NSButton {
    let toolbar = try XCTUnwrap(note.contentView?.subviews.compactMap { $0 as? NSStackView }.first)
    let title = AppSettings.shared.localizedString("editor.mode.startEditing")
    return try XCTUnwrap(toolbar.views.compactMap { $0 as? NSButton }.first { $0.toolTip == title })
}

@MainActor
func desktopNoteBodyPoint(in note: DesktopNotePanel, x: CGFloat = 35) throws -> NSPoint {
    let controller = try XCTUnwrap(note.contentViewController as? DesktopNoteContentController)
    let content = controller.hostingController.rootView
    return NSPoint(x: x, y: note.frame.height - content.headerHeight(at: note.frame.width) - 8)
}

@MainActor
func desktopNoteMouseEvent(
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
