import Foundation
import AppKit
import Carbon

/// Simplified modern hotkey manager - manages a single global hotkey
@MainActor
final class SimplifiedHotkeyManager {
    // MARK: - Singleton

    @MainActor static let shared = SimplifiedHotkeyManager()

    // MARK: - Properties

    private var keyCode: UInt16 = 46 // M key default
    private var modifiers: NSEvent.ModifierFlags = [.control, .option]
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var isEnabled: Bool = true
    private var startGeneration: UInt64 = 0
    private var hasInputMonitoringPermission = false
    private var hotKeyRef: EventHotKeyRef?
    @MainActor private static var hotKeyEventHandler: EventHandlerRef?
    private static let hotKeySignature: OSType = 0x4B50484B // 'KPHK'
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

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

    /// Check if we have Input Monitoring permission
    private func checkInputMonitoringPermission() {
        if isRunningTests {
            hasInputMonitoringPermission = true
            return
        }
        // Test if global monitoring is working by checking if we can create a test monitor
        let testMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { _ in }
        if let monitor = testMonitor {
            NSEvent.removeMonitor(monitor)
            hasInputMonitoringPermission = true
        } else {
            hasInputMonitoringPermission = false
            Logger.shared.warning("Input Monitoring permission: NOT GRANTED - Global hotkey will only work when Kipple is active")
        }
    }

    // MARK: - Private Methods

    private func startMonitoring() {
        guard isEnabled else { return }

        // Ensure previous monitors are removed before creating new ones
        stopMonitoring()

        // Bump generation to invalidate any pending tasks
        startGeneration &+= 1
        let currentGen = startGeneration

        // Add small delay to ensure cleanup is complete
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Abort if state changed while queued
            guard self.isEnabled, currentGen == self.startGeneration else { return }
            // Abort if cleared
            guard self.keyCode != 0, !self.modifiers.isEmpty else { return }

            if !self.isRunningTests && self.registerHotKey() {
                return
            }

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
                if self.keyCode != 0, !self.modifiers.isEmpty,
                   eventKeyCode == self.keyCode && eventModifiers == self.modifiers {
                    return nil
                }
                return event
            }

            // Check if we have Input Monitoring permission
            self.checkInputMonitoringPermission()
        }
    }

    private func stopMonitoring() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
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
        let eventKeyCode = event.keyCode
        let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if eventKeyCode == keyCode && eventModifiers == modifiers {
            SimplifiedHotkeyManager.scheduleToggleNotification()
        }
    }

    nonisolated private static func scheduleToggleNotification() {
        Task { @MainActor in
            let manager = SimplifiedHotkeyManager.shared
            guard manager.isEnabled else { return }
            NotificationCenter.default.post(
                name: NSNotification.Name("toggleMainWindow"),
                object: nil
            )
        }
    }

    @MainActor
    private func registerHotKey() -> Bool {
        // Do not register for empty/cleared values
        guard keyCode != 0, !modifiers.isEmpty else { return false }
        installHotKeyHandlerIfNeeded()

        var id = EventHotKeyID(signature: SimplifiedHotkeyManager.hotKeySignature, id: 1)
        let status = RegisterEventHotKey(UInt32(keyCode), carbonFlags(from: modifiers), id, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status != noErr {
            hotKeyRef = nil
            return false
        }
        return true
    }

    @MainActor
    private func installHotKeyHandlerIfNeeded() {
        guard SimplifiedHotkeyManager.hotKeyEventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), SimplifiedHotkeyManager.hotKeyEventCallback, 1, &eventType, nil, &SimplifiedHotkeyManager.hotKeyEventHandler)
    }

    private func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }

    private static let hotKeyEventCallback: EventHandlerUPP = { _, _, _ in
        SimplifiedHotkeyManager.scheduleToggleNotification()
        return noErr
    }

    private func loadSettings() {
        // Use the same keys as HotkeyManager for compatibility
        if let savedKeyCode = (UserDefaults.standard.object(forKey: "hotkeyKeyCode")
            ?? UserDefaults.standard.object(forKey: "KippleHotkeyCode")) as? Int {
            keyCode = UInt16(savedKeyCode)
        }

        if let savedModifiers = (UserDefaults.standard.object(forKey: "hotkeyModifierFlags")
            ?? UserDefaults.standard.object(forKey: "KippleHotkeyModifiers")) as? UInt {
            modifiers = NSEvent.ModifierFlags(rawValue: savedModifiers)
        }

        // If either keyCode or modifiers are cleared, treat as disabled regardless of saved flag
        let cleared = (keyCode == 0) || modifiers.isEmpty
        if let savedEnabled = (UserDefaults.standard.object(forKey: "enableHotkey")
            ?? UserDefaults.standard.object(forKey: "KippleHotkeyEnabled")) as? Bool {
            isEnabled = savedEnabled && !cleared
        } else {
            isEnabled = !cleared
        }
    }

    private func saveSettings() {
        // Use the same keys as HotkeyManager for compatibility
        UserDefaults.standard.set(Int(keyCode), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(keyCode), forKey: "KippleHotkeyCode")
        UserDefaults.standard.set(modifiers.rawValue, forKey: "hotkeyModifierFlags")
        UserDefaults.standard.set(modifiers.rawValue, forKey: "KippleHotkeyModifiers")
        UserDefaults.standard.set(isEnabled, forKey: "enableHotkey")
        UserDefaults.standard.set(isEnabled, forKey: "KippleHotkeyEnabled")
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

        // Suspend/resume during recording in UI to avoid event consumption
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSuspendRecording),
            name: NSNotification.Name("SuspendGlobalHotkeyCapture"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResumeRecording),
            name: NSNotification.Name("ResumeGlobalHotkeyCapture"),
            object: nil
        )
    }

    @objc private func handleHotkeySettingsChanged() {
        // Reload settings from UserDefaults and re-register
        refreshHotkeys()
    }

    @objc private func handleSuspendRecording() {
        stopMonitoring()
    }

    @objc private func handleResumeRecording() {
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
