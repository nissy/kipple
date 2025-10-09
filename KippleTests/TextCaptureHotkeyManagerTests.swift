//
//  TextCaptureHotkeyManagerTests.swift
//  KippleTests
//
//  Created by Kipple on 2025/10/09.
//

import XCTest
@testable import Kipple
import AppKit

@MainActor
final class TextCaptureHotkeyManagerTests: XCTestCase {
    private var manager: TextCaptureHotkeyManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = TextCaptureHotkeyManager.shared
        manager.onHotkeyTriggered = nil
        _ = manager.applyHotKey(keyCode: 0, modifiers: [])
        UserDefaults.standard.removeObject(forKey: TextCaptureHotkeyManager.keyCodeDefaultsKey)
        UserDefaults.standard.removeObject(forKey: TextCaptureHotkeyManager.modifierDefaultsKey)
    }

    override func tearDown() async throws {
        manager.onHotkeyTriggered = nil
        _ = manager.applyHotKey(keyCode: 0, modifiers: [])
        manager = nil
        try await super.tearDown()
    }

    func testTextCaptureHotkeyTriggersHandler() throws {
        let expectation = expectation(description: "Hotkey triggered")

        manager.onHotkeyTriggered = {
            expectation.fulfill()
        }

        XCTAssertTrue(manager.applyHotKey(keyCode: 17, modifiers: [.command, .shift]))
        manager.handleTestEvent(keyCode: 17, modifiers: [.command, .shift])

        wait(for: [expectation], timeout: 1.0)
    }

    func testDisabledHotkeyDoesNotTrigger() throws {
        manager.onHotkeyTriggered = {
            XCTFail("Hotkey should be disabled")
        }

        XCTAssertTrue(manager.applyHotKey(keyCode: 0, modifiers: []))
        manager.handleTestEvent(keyCode: 17, modifiers: [.command, .shift])
    }

    func testHotkeyDoesNotPostMainWindowToggle() throws {
        let inverted = expectation(description: "Main window toggle should not fire")
        inverted.isInverted = true

        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("toggleMainWindow"),
            object: nil,
            queue: .main
        ) { _ in
            inverted.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        manager.onHotkeyTriggered = {}
        XCTAssertTrue(manager.applyHotKey(keyCode: 17, modifiers: [.command, .shift]))
        manager.handleTestEvent(keyCode: 17, modifiers: [.command, .shift])

        wait(for: [inverted], timeout: 0.5)
    }

    func testHotkeyPersistsToUserDefaults() throws {
        XCTAssertTrue(manager.applyHotKey(keyCode: 18, modifiers: [.command]))
        XCTAssertEqual(UserDefaults.standard.integer(forKey: TextCaptureHotkeyManager.keyCodeDefaultsKey), 18)
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: TextCaptureHotkeyManager.modifierDefaultsKey),
            Int(NSEvent.ModifierFlags.command.rawValue)
        )
    }
}
