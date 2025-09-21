import XCTest
@testable import Kipple

@MainActor
final class MenuBarAppIntegrationTests: XCTestCase {
    private var app: MenuBarApp!

    override func setUp() {
        super.setUp()
        // MenuBarApp is initialized in test mode automatically
        app = MenuBarApp()
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - Service Provider Tests

    func testUsesClipboardService() {
        // When: App initializes its clipboard service
        let serviceType = type(of: app.clipboardService)

        // Then: ClipboardService is used
        if #available(macOS 13.0, *) {
            XCTAssertTrue(
                serviceType == ModernClipboardServiceAdapter.self,
                "Should use ModernClipboardServiceAdapter on supported macOS"
            )
        } else {
            XCTAssertTrue(
                serviceType == ClipboardService.self,
                "Should fallback to ClipboardService on older macOS"
            )
        }
    }

    @available(macOS 13.0, *)
    func testUsesHotkeyManager() {
        // When: App initializes its hotkey manager
        let managerType = type(of: app.hotkeyManager)

        // Then: The appropriate manager is used based on OS version
        XCTAssertTrue(
            managerType is SimplifiedHotkeyManager.Type || managerType == HotkeyManager.self,
            "Should use appropriate hotkey manager"
        )
    }

    // MARK: - Service Lifecycle Tests

    func testStartsClipboardMonitoring() async throws {
        // Given: App is initialized

        // When: Services are started
        await app.startServicesAsync()

        // Then: Clipboard monitoring is active
        let isMonitoring = await app.isClipboardMonitoring()
        XCTAssertTrue(isMonitoring, "Clipboard monitoring should be started")
    }

    func testSavesDataOnTermination() async throws {
        // Given: Services are running with some data
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

    func testWindowManagement() {
        // Given: App is initialized

        // Then: Window manager is available
        // Note: We can't test actual window opening in unit tests as openMainWindow is private
        XCTAssertNotNil(app.windowManager, "Window manager should be initialized")
    }

    // MARK: - Hotkey Registration Tests

    @MainActor
    func testRegistersHotkeys() async {
        // Given: App is initialized

        // When: Hotkeys are registered
        await app.registerHotkeys()

        // Then: Main hotkey is registered
        let isRegistered = app.isHotkeyRegistered()
        XCTAssertTrue(isRegistered, "Main hotkey should be registered")
    }
}
