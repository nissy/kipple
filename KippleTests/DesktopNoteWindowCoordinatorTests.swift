import AppKit
import XCTest
@testable import Kipple

@MainActor
final class DesktopNoteWindowCoordinatorTests: XCTestCase {
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
        let saved = try updateSavedPlacement(of: original, on: screen, itemID: item.id, defaults: defaults)
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
        XCTAssertEqual(window.placement.color, .legacyPink)

        let retained = try await repository.load(ids: [item.id])
        XCTAssertEqual(retained.map(\.id), [item.id])
        await reopened.toggle(item.id, on: screen)
        XCTAssertTrue(DesktopNotePlacement.load(from: defaults).isEmpty)
        await reopened.restoreNotes()
        XCTAssertFalse(reopened.isPosted(item.id))
    }

    private func updateSavedPlacement(
        of original: DesktopNotePanel, on screen: NSScreen, itemID: UUID, defaults: UserDefaults
    ) throws -> DesktopNotePlacement {
        original.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.minX + 54, y: screen.visibleFrame.maxY - 60))
        simulateDesktopNoteLiveResize(original, to: NSSize(width: 274, height: 179))
        let resized = original.frame
        XCTAssertEqual(DesktopNotePlacement.load(from: defaults)[itemID]?.frame, resized)
        original.contentView?.layoutSubtreeIfNeeded()
        let point = try desktopNoteBodyPoint(in: original, x: resized.width - 50)
        let end = NSPoint(x: point.x + 35, y: point.y - 24)
        original.sendEvent(try desktopNoteMouseEvent(.leftMouseDown, at: point, for: original))
        original.sendEvent(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: original))
        original.sendEvent(try desktopNoteMouseEvent(.leftMouseUp, at: point, for: original))
        XCTAssertEqual(original.frame.origin, NSPoint(x: resized.minX + 35, y: resized.minY - 24))
        XCTAssertEqual(DesktopNotePlacement.load(from: defaults)[itemID]?.frame, original.frame)
        let color = NSMenuItem()
        color.representedObject = "Pink Note Color"
        XCTAssertTrue(NSApp.sendAction(NSSelectorFromString("changeColor:"), to: original, from: color))
        let saved = try XCTUnwrap(DesktopNotePlacement.load(from: defaults)[itemID])
        XCTAssertEqual(saved.frame, original.frame)
        XCTAssertEqual(saved.color, .legacyPink)
        XCTAssertTrue(saved.usesManualSize)
        return saved
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
    _ type: NSEvent.EventType,
    at point: NSPoint,
    for note: NSWindow,
    clickCount: Int = 1,
    modifiers: NSEvent.ModifierFlags = []
) throws -> NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(
        with: type,
        location: point,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: note.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: clickCount,
        pressure: 1
    ))
}

@MainActor
func sendDesktopNoteMouseGesture(
    to note: NSWindow,
    at point: NSPoint,
    draggingTo end: NSPoint? = nil,
    releasingAt release: NSPoint? = nil,
    clickCount: Int = 1,
    modifiers: NSEvent.ModifierFlags = []
) throws {
    let down = try desktopNoteMouseEvent(.leftMouseDown, at: point, for: note, clickCount: clickCount, modifiers: modifiers)
    var following: [NSEvent] = []
    if let end {
        following.append(try desktopNoteMouseEvent(.leftMouseDragged, at: end, for: note, modifiers: modifiers))
    }
    let up = try desktopNoteMouseEvent(
        .leftMouseUp, at: release ?? end ?? point, for: note, clickCount: clickCount, modifiers: modifiers
    )
    following.append(up)

    // Native text selection can wait for the remaining events inside mouseDown.
    for event in following.reversed() { NSApp.postEvent(event, atStart: true) }
    note.sendEvent(down)
    for event in following {
        let mask: NSEvent.EventTypeMask = event.type == .leftMouseUp ? .leftMouseUp : .leftMouseDragged
        if NSApp.nextEvent(matching: mask, until: .distantPast, inMode: .default, dequeue: false) === event {
            _ = NSApp.nextEvent(matching: mask, until: .distantPast, inMode: .default, dequeue: true)
        }
        note.sendEvent(event)
    }
}
