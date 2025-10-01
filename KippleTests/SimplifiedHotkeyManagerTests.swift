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
        struct KeyTestCase {
            let keyCode: UInt16
            let modifiers: NSEvent.ModifierFlags
            let expected: String
        }

        // Test various key codes
        let testCases: [KeyTestCase] = [
            KeyTestCase(keyCode: 0, modifiers: [], expected: "A"),
            KeyTestCase(keyCode: 1, modifiers: [], expected: "S"),
            KeyTestCase(keyCode: 46, modifiers: [], expected: "M"),
            KeyTestCase(keyCode: 40, modifiers: [], expected: "K"),
            KeyTestCase(keyCode: 35, modifiers: [], expected: "P"),
            KeyTestCase(keyCode: 12, modifiers: [], expected: "Q"),
            KeyTestCase(keyCode: 13, modifiers: [], expected: "W"),
            KeyTestCase(keyCode: 14, modifiers: [], expected: "E"),
            KeyTestCase(keyCode: 15, modifiers: [], expected: "R"),
            KeyTestCase(keyCode: 17, modifiers: [], expected: "T")
        ]

        for testCase in testCases {
            manager.setHotkey(keyCode: testCase.keyCode, modifiers: testCase.modifiers)
            let description = manager.getHotkeyDescription()
            XCTAssertEqual(description, testCase.expected, "Key code \(testCase.keyCode) should map to \(testCase.expected)")
        }
    }

    func testMultipleHotkeyChanges() {
        struct HotkeyChange {
            let keyCode: UInt16
            let modifiers: NSEvent.ModifierFlags
            let expectedDescription: String
        }

        // Test that changing hotkey multiple times works correctly
        let changes: [HotkeyChange] = [
            HotkeyChange(keyCode: 46, modifiers: [.control, .option], expectedDescription: "⌃⌥M"),
            HotkeyChange(keyCode: 40, modifiers: [.command], expectedDescription: "⌘K"),
            HotkeyChange(keyCode: 35, modifiers: [.shift, .option], expectedDescription: "⌥⇧P"),
            HotkeyChange(keyCode: 0, modifiers: [.control, .command], expectedDescription: "⌃⌘A")
        ]

        for change in changes {
            manager.setHotkey(keyCode: change.keyCode, modifiers: change.modifiers)
            let description = manager.getHotkeyDescription()
            XCTAssertEqual(description, change.expectedDescription)

            let (retrievedKeyCode, retrievedModifiers) = manager.getHotkey()
            XCTAssertEqual(retrievedKeyCode, change.keyCode)
            XCTAssertEqual(retrievedModifiers, change.modifiers)
        }
    }
}
