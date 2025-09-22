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
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var isEnabled: Bool = true
    private var hasInputMonitoringPermission = false

    // MARK: - Initialization

    private init() {
        loadSettings()
        setupNotificationObservers()
        startMonitoring()
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

    /// Refresh hotkey from settings
    func refreshHotkeys() {
        loadSettings()
        stopMonitoring()
        if isEnabled {
            startMonitoring()
        }
    }

    /// Get current hotkey configuration
    func getHotkey() -> (keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        return (keyCode, modifiers)
    }

    /// Enable or disable the hotkey
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "enableHotkey")

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

    /// Check if we have Input Monitoring permission
    private func checkInputMonitoringPermission() {
        // Test if global monitoring is working by checking if we can create a test monitor
        let testMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in }
        if let monitor = testMonitor {
            NSEvent.removeMonitor(monitor)
            hasInputMonitoringPermission = true
            Logger.shared.info("Input Monitoring permission: GRANTED")
        } else {
            hasInputMonitoringPermission = false
            Logger.shared.warning("Input Monitoring permission: NOT GRANTED - Global hotkey will only work when Kipple is active")
            showInputMonitoringAlert()
        }
    }

    /// Show alert for Input Monitoring permission
    private func showInputMonitoringAlert() {
        // Only show alert once per session
        guard !UserDefaults.standard.bool(forKey: "InputMonitoringAlertShown") else { return }
        UserDefaults.standard.set(true, forKey: "InputMonitoringAlertShown")

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Input Monitoring Permission Required"
            alert.informativeText = """
                Kipple needs Input Monitoring permission for the global hotkey (⌃⌥M) to work when other apps are in focus.

                Without this permission:
                • The hotkey will only work when Kipple's window is active
                • You can still use the menu bar icon to open Kipple

                To enable:
                1. Open System Settings → Privacy & Security → Input Monitoring
                2. Enable the toggle for Kipple
                3. Restart Kipple
                """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "Later")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                // Open Input Monitoring settings
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - Private Methods

    private func startMonitoring() {
        guard isEnabled else { return }

        // Ensure previous monitors are removed before creating new ones
        stopMonitoring()

        // Add small delay to ensure cleanup is complete
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Try to add global monitor (requires Input Monitoring permission)
            self.globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleKeyEvent(event)
            }

            // Also add local monitor as fallback (works when app is active)
            self.localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else { return event }
                self.handleKeyEvent(event)
                // Return nil to consume the event if it matches our hotkey
                let eventKeyCode = event.keyCode
                let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if eventKeyCode == self.keyCode && eventModifiers == self.modifiers {
                    return nil
                }
                return event
            }

            // Check if we have Input Monitoring permission
            self.checkInputMonitoringPermission()
        }
    }

    private func stopMonitoring() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
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
        // Use the same keys as HotkeyManager for compatibility
        if let savedKeyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int {
            keyCode = UInt16(savedKeyCode)
        }

        if let savedModifiers = UserDefaults.standard.object(forKey: "hotkeyModifierFlags") as? UInt {
            modifiers = NSEvent.ModifierFlags(rawValue: savedModifiers)
        }

        if let savedEnabled = UserDefaults.standard.object(forKey: "enableHotkey") as? Bool {
            isEnabled = savedEnabled
        }
    }

    private func saveSettings() {
        // Use the same keys as HotkeyManager for compatibility
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(modifiers.rawValue, forKey: "hotkeyModifierFlags")
        UserDefaults.standard.set(isEnabled, forKey: "enableHotkey")
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        // Listen for hotkey settings changes from UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeySettingsChanged),
            name: NSNotification.Name("HotkeySettingsChanged"),
            object: nil
        )

        // Listen for editor hotkey settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHotkeySettingsChanged),
            name: NSNotification.Name("EditorHotkeySettingsChanged"),
            object: nil
        )
    }

    @objc private func handleHotkeySettingsChanged() {
        // Reload settings from UserDefaults and re-register
        refreshHotkeys()
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
