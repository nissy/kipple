//
//  TextCaptureHotkeyManager.swift
//  Kipple
//
//  Created by Kipple on 2025/10/09.
//

import AppKit

@MainActor
final class TextCaptureHotkeyManager {
    static let shared = TextCaptureHotkeyManager()

    static let keyCodeDefaultsKey = "textCaptureHotkeyKeyCode"
    static let modifierDefaultsKey = "textCaptureHotkeyModifierFlags"

    private let defaultKeyCode: UInt16 = 17 // T key
    private let defaultModifiers: NSEvent.ModifierFlags = [.command, .shift]

    private var currentKeyCode: UInt16 = 0
    private var currentModifiers: NSEvent.ModifierFlags = []
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    var onHotkeyTriggered: (() -> Void)?

    private init() {
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

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleLocalKeyEvent(event)
        }

        Logger.shared.info("Text capture hotkey registered (monitors). keyCode=\(currentKeyCode), modifiers=\(currentModifiers)")
        return true
    }

    private func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
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

    private func handleKeyEvent(_ event: NSEvent) {
        let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard event.keyCode == currentKeyCode,
              eventModifiers == currentModifiers else {
            return
        }
        triggerHotkey()
    }

    private func handleLocalKeyEvent(_ event: NSEvent) -> NSEvent? {
        let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == currentKeyCode,
           eventModifiers == currentModifiers {
            triggerHotkey()
            return nil
        }
        return event
    }

    private func triggerHotkey() {
        guard currentKeyCode != 0, !currentModifiers.isEmpty else { return }
        onHotkeyTriggered?()
    }

    #if DEBUG
    func handleTestEvent(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        guard isRunningTests else { return }
        if keyCode == currentKeyCode, modifiers == currentModifiers {
            triggerHotkey()
        }
    }
    #endif
}
