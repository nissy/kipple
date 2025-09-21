import Foundation
import AppKit

/// Simplified modern hotkey manager - manages a single global hotkey
@MainActor
final class SimplifiedHotkeyManager {
    // MARK: - Singleton

    static let shared = SimplifiedHotkeyManager()

    // MARK: - Properties

    private var keyCode: UInt16 = 46 // M key default
    private var modifiers: NSEvent.ModifierFlags = [.control, .option]
    private var eventMonitor: Any?
    private var isEnabled: Bool = true

    // MARK: - Initialization

    private init() {
        loadSettings()
        startMonitoring()
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - Public Methods

    /// Set the hotkey configuration
    func setHotkey(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        saveSettings()

        // Restart monitoring with new hotkey
        stopMonitoring()
        startMonitoring()
    }

    /// Get current hotkey configuration
    func getHotkey() -> (keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        return (keyCode, modifiers)
    }

    /// Enable or disable the hotkey
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "KippleHotkeyEnabled")

        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    /// Check if hotkey is enabled
    func getEnabled() -> Bool {
        return isEnabled
    }

    /// Format hotkey as string (e.g., "⌃⌥M")
    func getHotkeyDescription() -> String {
        var description = ""

        if modifiers.contains(.control) {
            description += "⌃"
        }
        if modifiers.contains(.option) {
            description += "⌥"
        }
        if modifiers.contains(.command) {
            description += "⌘"
        }
        if modifiers.contains(.shift) {
            description += "⇧"
        }

        description += keyCodeToString(keyCode)
        return description
    }

    // MARK: - Private Methods

    private func startMonitoring() {
        guard isEnabled else { return }

        stopMonitoring()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    private func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard isEnabled else { return }

        let eventKeyCode = event.keyCode
        let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if eventKeyCode == keyCode && eventModifiers == modifiers {
            // Post notification for window toggle
            NotificationCenter.default.post(
                name: NSNotification.Name("toggleMainWindow"),
                object: nil
            )
        }
    }

    private func loadSettings() {
        if let savedKeyCode = UserDefaults.standard.object(forKey: "KippleHotkeyCode") as? Int {
            keyCode = UInt16(savedKeyCode)
        }

        if let savedModifiers = UserDefaults.standard.object(forKey: "KippleHotkeyModifiers") as? UInt {
            modifiers = NSEvent.ModifierFlags(rawValue: savedModifiers)
        }

        if let savedEnabled = UserDefaults.standard.object(forKey: "KippleHotkeyEnabled") as? Bool {
            isEnabled = savedEnabled
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(Int(keyCode), forKey: "KippleHotkeyCode")
        UserDefaults.standard.set(modifiers.rawValue, forKey: "KippleHotkeyModifiers")
        UserDefaults.standard.set(isEnabled, forKey: "KippleHotkeyEnabled")
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        default: return "?"
        }
    }
}
