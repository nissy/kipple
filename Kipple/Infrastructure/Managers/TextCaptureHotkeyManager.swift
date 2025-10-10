//
//  TextCaptureHotkeyManager.swift
//  Kipple
//
//  Created by Kipple on 2025/10/09.
//

import AppKit
import Carbon

@MainActor
final class TextCaptureHotkeyManager {
    static let shared = TextCaptureHotkeyManager()

    static let keyCodeDefaultsKey = "textCaptureHotkeyKeyCode"
    static let modifierDefaultsKey = "textCaptureHotkeyModifierFlags"

    private let defaultKeyCode: UInt16 = 17 // T key
    private let defaultModifiers: NSEvent.ModifierFlags = [.command, .shift]

    private static let hotKeySignature: OSType = 0x4B505443 // 'KPTC'
    private static var hotKeyEventHandler: EventHandlerRef?

    private let isRunningTests: Bool

    private var currentKeyCode: UInt16 = 0
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var hotKeyRef: EventHotKeyRef?

    var onHotkeyTriggered: (() -> Void)?

    var currentHotkey: (keyCode: UInt16, modifiers: NSEvent.ModifierFlags)? {
        guard currentKeyCode != 0, !currentModifiers.isEmpty else { return nil }
        return (currentKeyCode, currentModifiers)
    }

    private init(isRunningTests: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil) {
        self.isRunningTests = isRunningTests
        loadInitialHotkey()
    }

    @discardableResult
    func applyHotKey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        let defaults = UserDefaults.standard
        let previousKeyCode = currentKeyCode
        let previousModifiers = currentModifiers

        stopMonitoring()

        currentKeyCode = keyCode
        currentModifiers = modifiers

        if keyCode == 0 || modifiers.isEmpty {
            defaults.set(0, forKey: Self.keyCodeDefaultsKey)
            defaults.set(0, forKey: Self.modifierDefaultsKey)
            Logger.shared.info("Text capture hotkey disabled.")
            return true
        }

        let success = startMonitoring()
        if success {
            defaults.set(Int(keyCode), forKey: Self.keyCodeDefaultsKey)
            defaults.set(Int(modifiers.rawValue), forKey: Self.modifierDefaultsKey)
            return true
        } else {
            // Revert to previous registration/state
            currentKeyCode = previousKeyCode
            currentModifiers = previousModifiers
            defaults.set(Int(previousKeyCode), forKey: Self.keyCodeDefaultsKey)
            defaults.set(Int(previousModifiers.rawValue), forKey: Self.modifierDefaultsKey)

            if previousKeyCode != 0, !previousModifiers.isEmpty {
                currentKeyCode = previousKeyCode
                currentModifiers = previousModifiers
                _ = startMonitoring()
            }
            return false
        }
    }

    private func startMonitoring() -> Bool {
        guard currentKeyCode != 0, !currentModifiers.isEmpty else {
            return true
        }

        if isRunningTests {
            return true
        }

        guard installHotKeyHandlerIfNeeded() else {
            Logger.shared.error("Text capture hotkey handler could not be installed.")
            return false
        }

        let identifier = EventHotKeyID(signature: Self.hotKeySignature, id: 1)
        var newHotKeyRef: EventHotKeyRef?
        let carbonFlags = carbonFlags(from: currentModifiers)
        let status = RegisterEventHotKey(
            UInt32(currentKeyCode),
            carbonFlags,
            identifier,
            GetEventDispatcherTarget(),
            0,
            &newHotKeyRef
        )

        guard status == noErr, let registeredRef = newHotKeyRef else {
            if status != noErr {
                Logger.shared.error("Text capture hotkey registration failed with status \(status).")
            } else {
                Logger.shared.error("Text capture hotkey registration returned no reference.")
            }
            return false
        }

        hotKeyRef = registeredRef
        Logger.shared.info("Text capture hotkey registered (Carbon). keyCode=\(currentKeyCode), modifiers=\(currentModifiers)")
        return true
    }

    private func stopMonitoring() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func loadInitialHotkey() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Self.keyCodeDefaultsKey) == nil {
            defaults.set(Int(defaultKeyCode), forKey: Self.keyCodeDefaultsKey)
        }
        if defaults.object(forKey: Self.modifierDefaultsKey) == nil {
            defaults.set(Int(defaultModifiers.rawValue), forKey: Self.modifierDefaultsKey)
        }

        let storedKeyCode = UInt16(defaults.integer(forKey: Self.keyCodeDefaultsKey))
        let storedModifiers = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: Self.modifierDefaultsKey)))

        currentKeyCode = storedKeyCode
        currentModifiers = storedModifiers

        if storedKeyCode == 0 || storedModifiers.isEmpty {
            Logger.shared.info("Text capture hotkey not registered (disabled in settings).")
            return
        }

        _ = startMonitoring()
    }

    private func installHotKeyHandlerIfNeeded() -> Bool {
        if TextCaptureHotkeyManager.hotKeyEventHandler != nil {
            return true
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            TextCaptureHotkeyManager.hotKeyEventCallback,
            1,
            &eventType,
            nil,
            &TextCaptureHotkeyManager.hotKeyEventHandler
        )

        if status != noErr {
            TextCaptureHotkeyManager.hotKeyEventHandler = nil
            return false
        }

        return true
    }

    private func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    private func handleCarbonHotKey(with identifier: UInt32) {
        guard identifier == 1 else { return }
        triggerHotkey()
    }

    private static func processCarbonHotKeyEvent(signature: OSType, identifier: UInt32) -> OSStatus {
        guard signature == TextCaptureHotkeyManager.hotKeySignature else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor in
            TextCaptureHotkeyManager.shared.handleCarbonHotKey(with: identifier)
        }

        return noErr
    }

    private static let hotKeyEventCallback: EventHandlerUPP = { _, event, _ in
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            return OSStatus(eventNotHandledErr)
        }

        return TextCaptureHotkeyManager.processCarbonHotKeyEvent(
            signature: hotKeyID.signature,
            identifier: hotKeyID.id
        )
    }

    private func triggerHotkey() {
        guard currentKeyCode != 0, !currentModifiers.isEmpty else { return }
        onHotkeyTriggered?()
    }

    #if DEBUG
    func debug_processCarbonHotKeyEvent(signature: OSType, identifier: UInt32) -> OSStatus {
        TextCaptureHotkeyManager.processCarbonHotKeyEvent(signature: signature, identifier: identifier)
    }
    #endif

    #if DEBUG
    func handleTestEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard isRunningTests else { return }
        if keyCode == currentKeyCode, modifiers == currentModifiers {
            triggerHotkey()
        }
    }
    #endif
}
