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

    func testDefaultIsCommandShiftVWithoutWritingSettings() {
        defaults.removePersistentDomain(forName: suiteName)
        let manager = makeManager { false }
        XCTAssertEqual(manager.shortcut, .init(keyCode: 9, modifiers: [.command, .shift]))
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

    func testSwappingRequiresPermissionAndSuccessfulCommandVReservation() {
        var trusted = false
        let manager = makeManager { trusted }
        XCTAssertEqual(manager.setSwapsPasteFormatting(true), .permissionRequired)
        XCTAssertFalse(manager.swapsPasteFormatting)
        trusted = true
        manager.onConfigurationChanged = { swapped, _ in !swapped }
        XCTAssertEqual(manager.setSwapsPasteFormatting(true), .shortcutUnavailable)
        XCTAssertFalse(manager.swapsPasteFormatting)
        XCTAssertFalse(defaults.bool(forKey: PlainTextPasteHotkey.swapsFormattingDefaultsKey))
    }

    func testSwappingPersistsAndClearingTheAlternateShortcutTurnsItOff() {
        let manager = makeManager()
        XCTAssertNil(manager.setSwapsPasteFormatting(true))
        XCTAssertTrue(manager.swapsPasteFormatting)
        XCTAssertTrue(makeManager().swapsPasteFormatting)
        XCTAssertNil(manager.apply(keyCode: 0, modifiers: []))
        XCTAssertFalse(manager.swapsPasteFormatting)
        XCTAssertFalse(makeManager().swapsPasteFormatting)
        XCTAssertEqual(manager.setSwapsPasteFormatting(true), .shortcutUnavailable)
    }

    func testRecordingAndPermissionChangesSuspendSwappedCommandV() {
        var trusted = true
        let manager = makeManager(observeChanges: true) { trusted }
        var lastConfiguration = (false, false)
        manager.onConfigurationChanged = { swapped, enabled in lastConfiguration = (swapped, enabled); return true }
        XCTAssertNil(manager.setSwapsPasteFormatting(true))
        XCTAssertTrue(lastConfiguration.0 && lastConfiguration.1)
        NotificationCenter.default.post(name: Notification.Name("SuspendGlobalHotkeyCapture"), object: nil)
        XCTAssertTrue(lastConfiguration.0)
        XCTAssertFalse(lastConfiguration.1)
        NotificationCenter.default.post(name: Notification.Name("ResumeGlobalHotkeyCapture"), object: nil)
        XCTAssertTrue(lastConfiguration.0 && lastConfiguration.1)
        trusted = false
        manager.refreshPermission()
        XCTAssertTrue(manager.swapsPasteFormatting)
        XCTAssertFalse(lastConfiguration.1)
        trusted = true
        manager.refreshPermission()
        XCTAssertTrue(lastConfiguration.0 && lastConfiguration.1)
    }

    func testResolvedCommandVConflictAllowsShortcutToTriggerAgain() {
        defaults.set(true, forKey: PlainTextPasteHotkey.swapsFormattingDefaultsKey)
        let manager = makeManager()
        var available = false
        var triggers = 0
        manager.onConfigurationChanged = { _, _ in available }
        manager.onTrigger = { triggers += 1 }
        manager.triggerIfPermitted()
        XCTAssertTrue(manager.registrationFailed)
        XCTAssertEqual(triggers, 0)
        available = true
        manager.triggerIfPermitted()
        XCTAssertFalse(manager.registrationFailed)
        XCTAssertEqual(triggers, 1)
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
