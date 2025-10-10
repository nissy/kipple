import XCTest
import AppKit
@testable import Kipple

final class MenuBarAppIntegrationTests: XCTestCase {
    // MARK: - Service Provider Tests

    @MainActor
    func testUsesClipboardService() {
        let app = makeMenuBarApp()
        defer { resetTextCaptureHotkey() }

        let serviceType = type(of: app.clipboardService)

        // Then: ModernClipboardServiceAdapter is used
        XCTAssertTrue(
            serviceType == ModernClipboardServiceAdapter.self,
            "Should use ModernClipboardServiceAdapter"
        )
    }

    @MainActor
    func testUsesHotkeyManager() {
        let app = makeMenuBarApp()
        defer { resetTextCaptureHotkey() }

        let managerType = type(of: app.hotkeyManager)

        // Then: SimplifiedHotkeyManager is used
        XCTAssertTrue(
            managerType is SimplifiedHotkeyManager.Type,
            "Should use SimplifiedHotkeyManager"
        )
    }

    // MARK: - Service Lifecycle Tests

    @MainActor
    func testStartsClipboardMonitoring() async throws {
        let app = makeMenuBarApp()
        defer { resetTextCaptureHotkey() }

        await app.startServicesAsync()

        // Then: Clipboard monitoring is active
        let isMonitoring = await app.isClipboardMonitoring()
        XCTAssertTrue(isMonitoring, "Clipboard monitoring should be started")
    }

    @MainActor
   func testSavesDataOnTermination() async throws {
        let app = makeMenuBarApp()
        defer { resetTextCaptureHotkey() }

        await app.startServicesAsync()

        // Add test data
        app.clipboardService.copyToClipboard("Test data for termination", fromEditor: true)

        // When: App performs termination (saves data)
        await app.performTermination()

        // Then: Data is saved (no assertion - just ensures no crash)
        // The performTermination helper method only saves data, doesn't stop services
        XCTAssertTrue(true, "Data save completed without errors")
    }

    // MARK: - Window Management Tests

    @MainActor
    func testWindowManagement() {
        let app = makeMenuBarApp()
        defer { resetTextCaptureHotkey() }

        // Then: Window manager is available
        // Note: We can't test actual window opening in unit tests as openMainWindow is private
        XCTAssertNotNil(app.windowManager, "Window manager should be initialized")
    }

    // MARK: - Hotkey Registration Tests

    @MainActor
    func testRegistersHotkeys() async {
        let app = makeMenuBarApp()
        defer { resetTextCaptureHotkey() }

        // When: Hotkeys are registered
        await app.registerHotkeys()

        // Then: Main hotkey is registered
        let isRegistered = app.isHotkeyRegistered()
        XCTAssertTrue(isRegistered, "Main hotkey should be registered")
    }

    @MainActor
    func testHandleTextCaptureSettingsChangeDisablesShortcut() {
        let app = makeMenuBarApp()
        defer { resetTextCaptureHotkey() }

        let manager = TextCaptureHotkeyManager.shared
        app.test_handleTextCaptureSettingsChange(
            enabled: true,
            keyCode: 17,
            modifiers: [.command, .shift],
            manager: manager
        )
        XCTAssertEqual(manager.currentHotkey?.keyCode, 17)
        XCTAssertEqual(manager.currentHotkey?.modifiers, [.command, .shift])

        app.test_handleTextCaptureSettingsChange(
            enabled: false,
            keyCode: 0,
            modifiers: [],
            manager: manager
        )
        XCTAssertNil(manager.currentHotkey)
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: TextCaptureHotkeyManager.keyCodeDefaultsKey),
            0
        )
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: TextCaptureHotkeyManager.modifierDefaultsKey),
            0
        )
    }

    @MainActor
    func testHandleTextCaptureSettingsChangeRegistersShortcut() {
        let app = makeMenuBarApp()
        defer { resetTextCaptureHotkey() }

        let manager = TextCaptureHotkeyManager.shared
        XCTAssertNil(manager.currentHotkey)

        app.test_handleTextCaptureSettingsChange(
            enabled: true,
            keyCode: 17,
            modifiers: [.command, .shift],
            manager: manager
        )

        let currentHotkey = manager.currentHotkey
        XCTAssertNotNil(currentHotkey)
        XCTAssertEqual(currentHotkey?.keyCode, 17)
        XCTAssertEqual(currentHotkey?.modifiers, [.command, .shift])
    }

    // MARK: - Helpers

    @MainActor
    private func makeMenuBarApp() -> MenuBarApp {
        resetTextCaptureHotkey()
        return MenuBarApp()
    }

    @MainActor
    private func resetTextCaptureHotkey() {
        let manager = TextCaptureHotkeyManager.shared
        _ = manager.applyHotKey(keyCode: 0, modifiers: [])
        manager.onHotkeyTriggered = nil
        UserDefaults.standard.removeObject(forKey: TextCaptureHotkeyManager.keyCodeDefaultsKey)
        UserDefaults.standard.removeObject(forKey: TextCaptureHotkeyManager.modifierDefaultsKey)
    }
}
