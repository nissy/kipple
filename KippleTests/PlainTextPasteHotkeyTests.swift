import AppKit
import XCTest
@testable import Kipple

@MainActor
final class PlainTextPasteHotkeyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let testModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift]

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "PlainTextPasteHotkeyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.set(40, forKey: PlainTextPasteHotkey.keyCodeDefaultsKey)
        defaults.set(Int(testModifiers.rawValue), forKey: PlainTextPasteHotkey.modifierDefaultsKey)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        try await super.tearDown()
    }

    func testDefaultIsControlShiftVWithoutWritingSettings() {
        defaults.removePersistentDomain(forName: suiteName)
        let manager = makeManager { false }
        XCTAssertEqual(manager.shortcut, .defaultShortcut)
        XCTAssertNil(defaults.object(forKey: PlainTextPasteHotkey.keyCodeDefaultsKey))
        XCTAssertFalse(manager.hasAccessibilityPermission)
    }

    func testMissingPermissionPreventsRegistrationEditingAndClearing() {
        let manager = makeManager { false }
        let previous = manager.shortcut
        manager.register()
        XCTAssertFalse(manager.isRegistered)
        XCTAssertFalse(manager.registrationFailed, "Missing permission is not a shortcut conflict")
        XCTAssertEqual(manager.apply(keyCode: 37, modifiers: testModifiers), .permissionRequired)
        XCTAssertEqual(manager.apply(keyCode: 0, modifiers: []), .permissionRequired)
        XCTAssertEqual(manager.shortcut, previous)
        XCTAssertEqual(defaults.integer(forKey: PlainTextPasteHotkey.keyCodeDefaultsKey), 40)
    }

    func testCustomShortcutPersistsIncludingTheAKey() {
        let manager = makeManager()
        XCTAssertNil(manager.apply(keyCode: 0, modifiers: testModifiers))
        XCTAssertTrue(manager.isRegistered)
        let reloaded = makeManager()
        XCTAssertEqual(reloaded.shortcut.keyCode, 0)
        XCTAssertEqual(reloaded.shortcut.modifiers, testModifiers)
        XCTAssertNotEqual(reloaded.shortcut, .disabled)
    }

    func testClearingPersistsDisabledStateAcrossPermissionRefreshAndRelaunch() {
        let manager = makeManager()
        manager.register()
        XCTAssertTrue(manager.isRegistered)
        XCTAssertNil(manager.apply(keyCode: 0, modifiers: []))
        manager.refreshPermission()
        XCTAssertFalse(manager.isRegistered)
        XCTAssertFalse(manager.registrationFailed)
        let reloaded = makeManager()
        reloaded.register()
        XCTAssertEqual(reloaded.shortcut, .disabled)
        XCTAssertFalse(reloaded.isRegistered)
    }

    func testPermissionGrantAndRevocationPreserveTheSelectedShortcut() {
        var trusted = false
        let manager = makeManager { trusted }
        let previous = manager.shortcut
        manager.register()
        XCTAssertFalse(manager.isRegistered)
        trusted = true
        manager.refreshPermission()
        XCTAssertTrue(manager.hasAccessibilityPermission)
        XCTAssertTrue(manager.isRegistered)
        trusted = false
        manager.refreshPermission()
        XCTAssertFalse(manager.hasAccessibilityPermission)
        XCTAssertFalse(manager.isRegistered)
        XCTAssertEqual(manager.shortcut, previous)
        trusted = true
        manager.refreshPermission()
        XCTAssertTrue(manager.isRegistered)
    }

    func testPermissionIsRecheckedAtEditAndTriggerTime() {
        var trusted = true
        let manager = makeManager { trusted }
        var triggers = 0
        manager.onTrigger = { triggers += 1 }
        manager.register()
        manager.triggerIfPermitted()
        XCTAssertEqual(triggers, 1)
        trusted = false
        XCTAssertEqual(manager.apply(keyCode: 37, modifiers: testModifiers), .permissionRequired)
        manager.triggerIfPermitted()
        XCTAssertEqual(triggers, 1)
        XCTAssertFalse(manager.isRegistered)
        XCTAssertEqual(manager.shortcut.keyCode, 40)
    }

    func testPermissionRefreshDoesNotResumeWhileRecording() {
        let manager = makeManager(observeChanges: true)
        manager.register()
        XCTAssertTrue(manager.isRegistered)
        NotificationCenter.default.post(name: Notification.Name("SuspendGlobalHotkeyCapture"), object: nil)
        defer {
            NotificationCenter.default.post(name: Notification.Name("ResumeGlobalHotkeyCapture"), object: nil)
        }
        manager.refreshPermission()
        XCTAssertFalse(manager.isRegistered)
        XCTAssertNil(manager.apply(keyCode: 37, modifiers: testModifiers))
        XCTAssertFalse(manager.isRegistered)
        manager.refreshPermission()
        XCTAssertFalse(manager.isRegistered)
        NotificationCenter.default.post(name: Notification.Name("ResumeGlobalHotkeyCapture"), object: nil)
        XCTAssertTrue(manager.isRegistered)
        XCTAssertEqual(manager.shortcut.keyCode, 37)
    }

    func testCommandVAndOtherKippleShortcutsCannotBeAssigned() {
        let manager = makeManager()
        manager.register()
        XCTAssertEqual(manager.apply(keyCode: 9, modifiers: .command), .shortcutUnavailable)
        defaults.set(37, forKey: "hotkeyKeyCode")
        defaults.set(Int(testModifiers.rawValue), forKey: "hotkeyModifierFlags")
        XCTAssertEqual(manager.apply(keyCode: 37, modifiers: testModifiers), .shortcutUnavailable)
        defaults.set(38, forKey: TextCaptureHotkeyManager.keyCodeDefaultsKey)
        defaults.set(Int(testModifiers.rawValue), forKey: TextCaptureHotkeyManager.modifierDefaultsKey)
        XCTAssertEqual(manager.apply(keyCode: 38, modifiers: testModifiers), .shortcutUnavailable)
        XCTAssertEqual(manager.shortcut.keyCode, 40)
        XCTAssertTrue(manager.isRegistered)
    }

    func testExternalShortcutConflictKeepsThePreviousWorkingShortcut() {
        let first = makeManager()
        first.register()
        defaults.set(37, forKey: PlainTextPasteHotkey.keyCodeDefaultsKey)
        let second = makeManager()
        second.register()
        XCTAssertTrue(first.isRegistered)
        XCTAssertTrue(second.isRegistered)
        XCTAssertEqual(second.apply(keyCode: 40, modifiers: testModifiers), .shortcutUnavailable)
        XCTAssertEqual(second.shortcut.keyCode, 37)
        XCTAssertEqual(defaults.integer(forKey: PlainTextPasteHotkey.keyCodeDefaultsKey), 37)
        XCTAssertTrue(second.isRegistered)
    }

    func testUnmodifiedAndShiftOnlyKeysAreRejectedWithoutLosingTheShortcut() {
        let manager = makeManager()
        manager.register()
        XCTAssertEqual(manager.apply(keyCode: 9, modifiers: []), .modifierRequired)
        XCTAssertEqual(manager.apply(keyCode: 9, modifiers: .shift), .modifierRequired)
        XCTAssertEqual(manager.shortcut.keyCode, 40)
        XCTAssertTrue(manager.isRegistered)
    }

    private func makeManager(
        observeChanges: Bool = false,
        permissionCheck: @escaping () -> Bool = { true }
    ) -> PlainTextPasteHotkey {
        let manager = PlainTextPasteHotkey(
            defaults: defaults, permissionCheck: permissionCheck, observeChanges: observeChanges
        )
        manager.onTrigger = {}
        return manager
    }
}
