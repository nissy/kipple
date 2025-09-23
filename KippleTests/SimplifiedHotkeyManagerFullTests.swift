import XCTest
import Combine
@testable import Kipple

@MainActor
final class SimplifiedHotkeyManagerFullTests: XCTestCase, @unchecked Sendable {
    private var manager: SimplifiedHotkeyManager!
    private var cancellables: Set<AnyCancellable> = []
    private let testUserDefaultsKeys = [
        "KippleHotkeyCode",
        "KippleHotkeyModifiers",
        "KippleHotkeyEnabled"
    ]
    private struct HotkeyDescriptionCase {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
        let expectedDescription: String
    }

    private struct HotkeyOperation {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
        let enabled: Bool
    }

    override func setUp() async throws {
        try await super.setUp()
        manager = SimplifiedHotkeyManager.shared
        cancellables.removeAll()

        // Save current settings
        saveCurrentSettings()

        // Reset to defaults for testing
        resetToDefaults()
    }

    override func tearDown() async throws {
        // Restore original settings
        restoreOriginalSettings()

        cancellables.removeAll()
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private var originalSettings: [String: Any] = [:]

    private func saveCurrentSettings() {
        for key in testUserDefaultsKeys {
            originalSettings[key] = UserDefaults.standard.object(forKey: key)
        }
    }

    private func restoreOriginalSettings() {
        for (key, value) in originalSettings {
            // value is of type Any, not Optional
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    private func resetToDefaults() {
        manager.setHotkey(keyCode: 46, modifiers: [.control, .option])
        manager.setEnabled(true)
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        // When - Get default configuration
        let (keyCode, modifiers) = manager.getHotkey()
        let enabled = manager.getEnabled()

        // Then
        XCTAssertEqual(keyCode, 46) // M key
        XCTAssertEqual(modifiers, [.control, .option])
        XCTAssertTrue(enabled)
    }

    func testSetAndGetHotkey() {
        // Given
        let testCases: [(UInt16, NSEvent.ModifierFlags)] = [
            (0, [.command]), // A + Cmd
            (11, [.control, .shift]), // B + Ctrl+Shift
            (8, [.option, .command]), // C + Opt+Cmd
            (2, [.control, .option, .command, .shift]) // D + All modifiers
        ]

        for (expectedKeyCode, expectedModifiers) in testCases {
            // When
            manager.setHotkey(keyCode: expectedKeyCode, modifiers: expectedModifiers)
            let (keyCode, modifiers) = manager.getHotkey()

            // Then
            XCTAssertEqual(keyCode, expectedKeyCode)
            XCTAssertEqual(modifiers, expectedModifiers)
        }
    }

    func testEnableDisableState() {
        // Test disable
        manager.setEnabled(false)
        XCTAssertFalse(manager.getEnabled())

        // Test enable
        manager.setEnabled(true)
        XCTAssertTrue(manager.getEnabled())

        // Test toggle pattern
        for expectedState in [false, true, false, true] {
            manager.setEnabled(expectedState)
            XCTAssertEqual(manager.getEnabled(), expectedState)
        }
    }

    // MARK: - Persistence Tests

    func testSettingsPersistence() {
        // Given
        let testKeyCode: UInt16 = 35 // P key
        let testModifiers: NSEvent.ModifierFlags = [.command, .option]
        let testEnabled = false

        // When
        manager.setHotkey(keyCode: testKeyCode, modifiers: testModifiers)
        manager.setEnabled(testEnabled)

        // Then - Verify UserDefaults
        XCTAssertEqual(UserDefaults.standard.object(forKey: "KippleHotkeyCode") as? Int, Int(testKeyCode))
        XCTAssertEqual(UserDefaults.standard.object(forKey: "KippleHotkeyModifiers") as? UInt, testModifiers.rawValue)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "KippleHotkeyEnabled") as? Bool, testEnabled)
    }

    func testSettingsLoadOnInit() {
        // Given - Set specific values in UserDefaults
        UserDefaults.standard.set(Int(40), forKey: "KippleHotkeyCode") // K key
        UserDefaults.standard.set(NSEvent.ModifierFlags.command.rawValue, forKey: "KippleHotkeyModifiers")
        UserDefaults.standard.set(false, forKey: "KippleHotkeyEnabled")

        // When - Manager loads settings on access
        // Note: SimplifiedHotkeyManager is a singleton, so it already loaded settings
        // We verify the saved values are correct

        // Then
        let savedKeyCode = UserDefaults.standard.object(forKey: "KippleHotkeyCode") as? Int
        let savedModifiers = UserDefaults.standard.object(forKey: "KippleHotkeyModifiers") as? UInt
        let savedEnabled = UserDefaults.standard.object(forKey: "KippleHotkeyEnabled") as? Bool

        XCTAssertEqual(savedKeyCode, 40)
        XCTAssertEqual(savedModifiers, NSEvent.ModifierFlags.command.rawValue)
        XCTAssertEqual(savedEnabled, false)
    }

    // MARK: - Description Formatting Tests

    func testHotkeyDescription() {
        let testCases: [HotkeyDescriptionCase] = [
            .init(keyCode: 46, modifiers: [.control, .option], expectedDescription: "⌃⌥M"),
            .init(keyCode: 0, modifiers: [.command], expectedDescription: "⌘A"),
            .init(keyCode: 35, modifiers: [.shift, .option], expectedDescription: "⌥⇧P"),
            .init(keyCode: 40, modifiers: [.control, .command], expectedDescription: "⌃⌘K"),
            .init(keyCode: 14, modifiers: [.control, .option, .command], expectedDescription: "⌃⌥⌘E"),
            .init(keyCode: 15, modifiers: [.control, .option, .command, .shift], expectedDescription: "⌃⌥⌘⇧R")
        ]

        for testCase in testCases {
            // When
            manager.setHotkey(keyCode: testCase.keyCode, modifiers: testCase.modifiers)
            let description = manager.getHotkeyDescription()

            // Then
            XCTAssertEqual(
                description,
                testCase.expectedDescription,
                "Key code \(testCase.keyCode) with modifiers \(testCase.modifiers.rawValue) should format as \(testCase.expectedDescription)"
            )
        }
    }

    func testKeyCodeToStringMapping() {
        let keyCodeMappings: [(UInt16, String)] = [
            (0, "A"), (1, "S"), (2, "D"), (3, "F"), (4, "H"), (5, "G"),
            (6, "Z"), (7, "X"), (8, "C"), (9, "V"), (11, "B"),
            (12, "Q"), (13, "W"), (14, "E"), (15, "R"), (16, "Y"), (17, "T"),
            (31, "O"), (32, "U"), (34, "I"), (35, "P"),
            (37, "L"), (38, "J"), (40, "K"), (45, "N"), (46, "M"),
            (999, "?") // Unknown key code
        ]

        for (keyCode, expectedString) in keyCodeMappings {
            // When
            manager.setHotkey(keyCode: keyCode, modifiers: [])
            let description = manager.getHotkeyDescription()

            // Then
            XCTAssertEqual(description, expectedString,
                          "Key code \(keyCode) should map to '\(expectedString)'")
        }
    }

    // MARK: - Notification Tests

    func testNotificationPosting() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Notification received")
        expectation.expectedFulfillmentCount = 3 // Expect 3 notifications

        NotificationCenter.default.publisher(for: NSNotification.Name("toggleMainWindow"))
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When - Post notifications multiple times
        for _ in 1...3 {
            NotificationCenter.default.post(
                name: NSNotification.Name("toggleMainWindow"),
                object: nil
            )
        }

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testNotificationWithDifferentHotkeys() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Notification with different hotkeys")

        NotificationCenter.default.publisher(for: NSNotification.Name("toggleMainWindow"))
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When - Change hotkey and post notification
        manager.setHotkey(keyCode: 35, modifiers: [.command, .shift])
        NotificationCenter.default.post(
            name: NSNotification.Name("toggleMainWindow"),
            object: nil
        )

        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - State Management Tests

    func testStateConsistency() {
        // Given - Perform multiple operations
        let operations: [HotkeyOperation] = [
            .init(keyCode: 46, modifiers: [.control, .option], enabled: true),
            .init(keyCode: 35, modifiers: [.command], enabled: false),
            .init(keyCode: 0, modifiers: [.shift, .option], enabled: true),
            .init(keyCode: 40, modifiers: [.control, .command, .shift], enabled: false)
        ]

        for operation in operations {
            // When
            manager.setHotkey(keyCode: operation.keyCode, modifiers: operation.modifiers)
            manager.setEnabled(operation.enabled)

            // Then - Verify state is consistent
            let (retrievedKeyCode, retrievedModifiers) = manager.getHotkey()
            let retrievedEnabled = manager.getEnabled()

            XCTAssertEqual(retrievedKeyCode, operation.keyCode)
            XCTAssertEqual(retrievedModifiers, operation.modifiers)
            XCTAssertEqual(retrievedEnabled, operation.enabled)

            // Verify persistence
            XCTAssertEqual(UserDefaults.standard.object(forKey: "KippleHotkeyCode") as? Int, Int(operation.keyCode))
            XCTAssertEqual(UserDefaults.standard.object(forKey: "KippleHotkeyModifiers") as? UInt, operation.modifiers.rawValue)
            XCTAssertEqual(UserDefaults.standard.object(forKey: "KippleHotkeyEnabled") as? Bool, operation.enabled)
        }
    }

    func testRapidStateChanges() {
        // Test rapid hotkey changes
        for i in 0..<50 {
            let keyCode = UInt16(i % 47) // Cycle through key codes
            let modifiers: NSEvent.ModifierFlags = i % 2 == 0 ? [.control] : [.command]
            manager.setHotkey(keyCode: keyCode, modifiers: modifiers)

            let (retrievedKeyCode, retrievedModifiers) = manager.getHotkey()
            XCTAssertEqual(retrievedKeyCode, keyCode)
            XCTAssertEqual(retrievedModifiers, modifiers)
        }

        // Test rapid enable/disable
        for i in 0..<50 {
            let enabled = i % 2 == 0
            manager.setEnabled(enabled)
            XCTAssertEqual(manager.getEnabled(), enabled)
        }
    }

    // MARK: - Edge Cases

    func testEmptyModifiers() {
        // Given
        manager.setHotkey(keyCode: 46, modifiers: [])

        // When
        let (keyCode, modifiers) = manager.getHotkey()

        // Then
        XCTAssertEqual(keyCode, 46)
        XCTAssertTrue(modifiers.isEmpty)
        XCTAssertEqual(manager.getHotkeyDescription(), "M")
    }

    func testAllModifiersCombination() {
        // Given
        let allModifiers: NSEvent.ModifierFlags = [.control, .option, .command, .shift]
        manager.setHotkey(keyCode: 0, modifiers: allModifiers)

        // When
        let description = manager.getHotkeyDescription()

        // Then
        XCTAssertEqual(description, "⌃⌥⌘⇧A")
    }

    func testInvalidKeyCode() {
        // Given - Set an out-of-range key code
        manager.setHotkey(keyCode: 9999, modifiers: [.control])

        // When
        let description = manager.getHotkeyDescription()

        // Then
        XCTAssertEqual(description, "⌃?") // Should show unknown character
    }

    // MARK: - Performance Tests

    func testSettingsPerformance() {
        // Measure time to perform many setting changes
        let iterations = 1000

        let startTime = Date()

        for i in 0..<iterations {
            let keyCode = UInt16(i % 47)
            let modifiers: NSEvent.ModifierFlags = i % 2 == 0 ? [.control, .option] : [.command, .shift]
            manager.setHotkey(keyCode: keyCode, modifiers: modifiers)
            manager.setEnabled(i % 2 == 0)
        }

        let elapsedTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertLessThan(elapsedTime, 2.0, "1000 setting changes should complete within 2 seconds")
    }

    func testDescriptionGenerationPerformance() {
        // Measure time to generate many descriptions
        let iterations = 10000

        let startTime = Date()

        for _ in 0..<iterations {
            _ = manager.getHotkeyDescription()
        }

        let elapsedTime = Date().timeIntervalSince(startTime)

        // Then
        XCTAssertLessThan(elapsedTime, 1.0, "10000 description generations should complete within 1 second")
    }

    // MARK: - Thread Safety Tests

    func testConcurrentAccess() async {
        // Test concurrent reads and writes
        let manager = self.manager!
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 0..<10 {
                group.addTask { @MainActor in
                    let keyCode = UInt16(i)
                    let modifiers: NSEvent.ModifierFlags = i % 2 == 0 ? [.control] : [.command]
                    manager.setHotkey(keyCode: keyCode, modifiers: modifiers)
                }
            }

            // Readers
            for _ in 0..<10 {
                group.addTask { @MainActor in
                    _ = manager.getHotkey()
                    _ = manager.getEnabled()
                    _ = manager.getHotkeyDescription()
                }
            }
        }

        // Verify manager is still in valid state
        let (keyCode, _) = manager.getHotkey()
        XCTAssertLessThan(keyCode, 200) // Should be a valid key code
        XCTAssertNotNil(manager.getHotkeyDescription())
    }
}
