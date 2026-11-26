import AppKit
import Carbon.HIToolbox
import Combine
import XCTest
@testable import Kipple

@MainActor
final class DesktopNoteHotkeyTests: XCTestCase {
    func testDesktopNoteUsesLiveEditorHotkeySettings() async throws {
        let settings = AppSettings.shared
        let saveKey = settings.editorCopyHotkeyKeyCode
        let saveFlags = settings.editorCopyHotkeyModifierFlags
        let clearKey = settings.editorClearHotkeyKeyCode
        let clearFlags = settings.editorClearHotkeyModifierFlags
        let saveModifiers: NSEvent.ModifierFlags = [.control, .option]
        let clearModifiers: NSEvent.ModifierFlags = [.command, .shift]
        settings.editorCopyHotkeyKeyCode = kVK_ANSI_A
        settings.editorCopyHotkeyModifierFlags = Int(saveModifiers.rawValue)
        settings.editorClearHotkeyKeyCode = kVK_Escape
        settings.editorClearHotkeyModifierFlags = Int(clearModifiers.rawValue)
        defer {
            settings.editorCopyHotkeyKeyCode = saveKey
            settings.editorCopyHotkeyModifierFlags = saveFlags
            settings.editorClearHotkeyKeyCode = clearKey
            settings.editorClearHotkeyModifierFlags = clearFlags
        }

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

        let clear = try desktopNoteKeyEvent(kVK_Escape, characters: "\u{1B}", modifiers: clearModifiers, for: note)
        note.sendEvent(clear)
        XCTAssertFalse(note.firstResponder is LiveEditorTextView)
        try desktopNoteEditButton(in: note).performClick(nil)
        let editor = try XCTUnwrap(note.firstResponder as? LiveEditorTextView)
        XCTAssertEqual(editor.string, original)
        note.sendEvent(clear)
        XCTAssertTrue(editor.string.isEmpty)
        XCTAssertEqual(adapter.history.first?.content, original)

        let updated = "Updated with the configured save shortcut"
        editor.string = updated
        let saved = expectation(description: "Configured hotkey updates the note's history")
        let observation = adapter.$history.first { $0.first?.content == updated }.sink { _ in saved.fulfill() }
        defer { observation.cancel() }
        note.sendEvent(try desktopNoteKeyEvent(kVK_ANSI_A, characters: "a", modifiers: saveModifiers, for: note))
        await fulfillment(of: [saved], timeout: 2)
        for _ in 0..<20 where note.firstResponder is LiveEditorTextView {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(note.firstResponder is LiveEditorTextView)
        XCTAssertEqual(adapter.history.map(\.id), [item.id])
        XCTAssertTrue(coordinator.isPosted(item.id))
    }
}
