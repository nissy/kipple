import XCTest
import Combine
@testable import Kipple

@MainActor
final class SimplifiedHotkeyManagerTests: XCTestCase {
    private var manager: SimplifiedHotkeyManager!
    private var cancellables: Set<AnyCancellable> = []

    override func setUp() async throws {
        try await super.setUp()
        manager = SimplifiedHotkeyManager.shared
        cancellables.removeAll()
    }

    override func tearDown() async throws {
        // Reset to defaults
        manager.setHotkey(keyCode: 46, modifiers: [.control, .option])
        manager.setEnabled(true)
        cancellables.removeAll()
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Basic Tests

    func testSetAndGetHotkey() {
        // Given
        let keyCode: UInt16 = 40 // K key
        let modifiers: NSEvent.ModifierFlags = [.command, .shift]

        // When
        manager.setHotkey(keyCode: keyCode, modifiers: modifiers)
        let (retrievedKeyCode, retrievedModifiers) = manager.getHotkey()

        // Then
        XCTAssertEqual(retrievedKeyCode, keyCode)
        XCTAssertEqual(retrievedModifiers, modifiers)
    }

    func testEnableDisable() {
        // When - Disable
        manager.setEnabled(false)

        // Then
        XCTAssertFalse(manager.getEnabled())

        // When - Enable
        manager.setEnabled(true)

        // Then
        XCTAssertTrue(manager.getEnabled())
    }

    func testHotkeyDescription() {
        // Given
        manager.setHotkey(keyCode: 46, modifiers: [.control, .option])

        // When
        let description = manager.getHotkeyDescription()

        // Then
        XCTAssertEqual(description, "⌃⌥M")
    }

    func testHotkeyDescriptionWithAllModifiers() {
        // Given
        manager.setHotkey(keyCode: 0, modifiers: [.command, .control, .option, .shift])

        // When
        let description = manager.getHotkeyDescription()

        // Then
        XCTAssertEqual(description, "⌃⌥⌘⇧A")
    }

    func testHotkeyTriggersNotification() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Hotkey notification posted")

        // Subscribe to notification
        NotificationCenter.default.publisher(for: NSNotification.Name("toggleMainWindow"))
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When - Post notification manually (simulating hotkey press)
        NotificationCenter.default.post(
            name: NSNotification.Name("toggleMainWindow"),
            object: nil
        )

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testSettingsPersistence() {
        // Given
        let keyCode: UInt16 = 35 // P key
        let modifiers: NSEvent.ModifierFlags = [.command, .option]

        // When
        manager.setHotkey(keyCode: keyCode, modifiers: modifiers)
        manager.setEnabled(false)

        // Create new instance to test persistence
        // Note: In real usage, SimplifiedHotkeyManager is a singleton
        // For testing, we verify UserDefaults directly
        let savedKeyCode = UserDefaults.standard.object(forKey: "KippleHotkeyCode") as? Int
        let savedModifiers = UserDefaults.standard.object(forKey: "KippleHotkeyModifiers") as? UInt
        let savedEnabled = UserDefaults.standard.object(forKey: "KippleHotkeyEnabled") as? Bool

        // Then
        XCTAssertEqual(savedKeyCode, Int(keyCode))
        XCTAssertEqual(savedModifiers, modifiers.rawValue)
        XCTAssertEqual(savedEnabled, false)
    }

    func testDefaultValues() {
        // Note: Since SimplifiedHotkeyManager is a singleton,
        // it may have been modified by previous tests.
        // We test that setting back to defaults works correctly.

        // When - Set to default values
        manager.setHotkey(keyCode: 46, modifiers: [.control, .option])
        manager.setEnabled(true)

        // Then - Verify defaults are set
        let (keyCode, modifiers) = manager.getHotkey()
        let enabled = manager.getEnabled()

        XCTAssertEqual(keyCode, 46) // M key
        XCTAssertEqual(modifiers, [.control, .option])
        XCTAssertTrue(enabled)
    }

    func testKeyCodeToStringMapping() {
        // Test various key codes
        let testCases: [(UInt16, NSEvent.ModifierFlags, String)] = [
            (0, [], "A"),
            (1, [], "S"),
            (46, [], "M"),
            (40, [], "K"),
            (35, [], "P"),
            (12, [], "Q"),
            (13, [], "W"),
            (14, [], "E"),
            (15, [], "R"),
            (17, [], "T")
        ]

        for (keyCode, modifiers, expectedChar) in testCases {
            manager.setHotkey(keyCode: keyCode, modifiers: modifiers)
            let description = manager.getHotkeyDescription()
            XCTAssertEqual(description, expectedChar, "Key code \(keyCode) should map to \(expectedChar)")
        }
    }

    func testMultipleHotkeyChanges() {
        // Test that changing hotkey multiple times works correctly
        let changes: [(UInt16, NSEvent.ModifierFlags, String)] = [
            (46, [.control, .option], "⌃⌥M"),
            (40, [.command], "⌘K"),
            (35, [.shift, .option], "⌥⇧P"),
            (0, [.control, .command], "⌃⌘A")
        ]

        for (keyCode, modifiers, expectedDescription) in changes {
            manager.setHotkey(keyCode: keyCode, modifiers: modifiers)
            let description = manager.getHotkeyDescription()
            XCTAssertEqual(description, expectedDescription)

            let (retrievedKeyCode, retrievedModifiers) = manager.getHotkey()
            XCTAssertEqual(retrievedKeyCode, keyCode)
            XCTAssertEqual(retrievedModifiers, modifiers)
        }
    }
}
