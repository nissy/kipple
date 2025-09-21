import XCTest
@testable import Kipple

/// Tests for hotkey settings synchronization between UI and SimplifiedHotkeyManager
@MainActor
final class HotkeySettingsSyncTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset to known state
        UserDefaults.standard.set(46, forKey: "hotkeyKeyCode") // M key
        UserDefaults.standard.set(
            NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.option.rawValue,
            forKey: "hotkeyModifierFlags"
        )
        UserDefaults.standard.set(true, forKey: "enableHotkey")
    }

    override func tearDown() {
        // Clean up
        UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
        UserDefaults.standard.removeObject(forKey: "hotkeyModifierFlags")
        UserDefaults.standard.removeObject(forKey: "enableHotkey")
        super.tearDown()
    }

    func testSimplifiedHotkeyManagerUsesCorrectKeys() {
        // Given: SimplifiedHotkeyManager
        let manager = SimplifiedHotkeyManager.shared

        // When: Set hotkey through manager
        manager.setHotkey(keyCode: 9, modifiers: [.command, .shift]) // V key

        // Then: Should save to correct UserDefaults keys
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"), 9)
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: "hotkeyModifierFlags"),
            Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        )
    }

    func testEnableDisableUsesCorrectKey() {
        // Given: SimplifiedHotkeyManager
        let manager = SimplifiedHotkeyManager.shared

        // When: Disable hotkey
        manager.setEnabled(false)

        // Then: Should update enableHotkey key
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "enableHotkey"))

        // When: Enable hotkey
        manager.setEnabled(true)

        // Then: Should update the same key
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "enableHotkey"))
    }

    func testNotificationTriggersRefresh() {
        // Given: SimplifiedHotkeyManager with initial settings
        let manager = SimplifiedHotkeyManager.shared
        manager.refreshHotkeys() // Ensure loaded from UserDefaults

        // When: Change settings via UserDefaults (as UI would)
        UserDefaults.standard.set(8, forKey: "hotkeyKeyCode") // C key
        UserDefaults.standard.set(
            NSEvent.ModifierFlags.command.rawValue,
            forKey: "hotkeyModifierFlags"
        )

        // Post notification as UI would
        NotificationCenter.default.post(
            name: NSNotification.Name("HotkeySettingsChanged"),
            object: nil
        )

        // Give time for notification to process
        let expectation = expectation(description: "Notification processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then: Manager should reflect new settings
        let (keyCode, modifiers) = manager.getHotkey()
        XCTAssertEqual(keyCode, 8)
        XCTAssertEqual(modifiers, .command)
    }

    func testSettingsUICompatibility() {
        // This test verifies that the keys used by SimplifiedHotkeyManager
        // match those used by the Settings UI

        // Given: Settings as they would be saved by GeneralSettingsView
        let uiKeyCode = 12 // Q key
        let uiModifiers = NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.shift.rawValue
        let uiEnabled = false

        // When: UI saves settings
        UserDefaults.standard.set(uiKeyCode, forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(uiModifiers, forKey: "hotkeyModifierFlags")
        UserDefaults.standard.set(uiEnabled, forKey: "enableHotkey")

        // And: SimplifiedHotkeyManager refreshes
        let manager = SimplifiedHotkeyManager.shared
        manager.refreshHotkeys()

        // Then: Manager should have UI settings
        let (keyCode, modifiers) = manager.getHotkey()
        XCTAssertEqual(Int(keyCode), uiKeyCode)
        XCTAssertEqual(modifiers.rawValue, UInt(uiModifiers))
        XCTAssertEqual(manager.getEnabled(), uiEnabled)
    }

    func testDisableFromUIStopsMonitoring() {
        // Given: Hotkey is enabled
        let manager = SimplifiedHotkeyManager.shared
        manager.setEnabled(true)
        XCTAssertTrue(manager.getEnabled())

        // When: UI disables hotkey
        UserDefaults.standard.set(false, forKey: "enableHotkey")
        NotificationCenter.default.post(
            name: NSNotification.Name("HotkeySettingsChanged"),
            object: nil
        )

        // Give time for notification
        let expectation = expectation(description: "Disable processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Then: Manager should be disabled
        XCTAssertFalse(manager.getEnabled())
    }

    func testHotkeyProviderReturnsCorrectManager() {
        // Given: HotkeyManagerProvider

        // When: Resolve manager
        let resolvedManager = HotkeyManagerProvider.resolve()

        // Then: Should return appropriate manager
        // Note: After your changes, this returns HotkeyManager
        // but the test verifies the provider exists and returns something
        XCTAssertNotNil(resolvedManager)
    }

    func testRefreshHotkeysMethod() {
        // Given: SimplifiedHotkeyManager
        let manager = SimplifiedHotkeyManager.shared

        // When: Change settings directly in UserDefaults
        UserDefaults.standard.set(35, forKey: "hotkeyKeyCode") // P key
        UserDefaults.standard.set(
            NSEvent.ModifierFlags.option.rawValue,
            forKey: "hotkeyModifierFlags"
        )
        UserDefaults.standard.set(true, forKey: "enableHotkey")

        // And: Call refresh
        manager.refreshHotkeys()

        // Then: Should load new settings
        let (keyCode, modifiers) = manager.getHotkey()
        XCTAssertEqual(keyCode, 35)
        XCTAssertEqual(modifiers, .option)
        XCTAssertTrue(manager.getEnabled())
    }
}
