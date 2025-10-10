//
//  MenuBarApp.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
import SwiftUI
import Cocoa

@MainActor
final class MenuBarApp: NSObject, ObservableObject {
    private var statusBarItem: NSStatusItem?
    internal let clipboardService: any ClipboardServiceProtocol
    internal let windowManager = WindowManager()
    internal var hotkeyManager: Any
    private let openKippleMenuTitle = "Open Kipple"
    private let openKippleMenuItem = NSMenuItem(
        title: "Open Kipple",
        action: #selector(openMainWindow),
        keyEquivalent: ""
    )
    private let screenTextCaptureMenuTitle = "Screen Text Capture"
    private let screenTextCaptureMenuItem = NSMenuItem(
        title: "Screen Text Capture",
        action: #selector(captureTextFromScreen),
        keyEquivalent: ""
    )
    private let screenCaptureStatusItem = NSMenuItem()
    private lazy var textRecognitionService: any TextRecognitionServiceProtocol =
        TextRecognitionServiceProvider.resolve()
    private lazy var textCaptureCoordinator: TextCaptureCoordinator = {
        TextCaptureCoordinator(
            clipboardService: clipboardService,
            textRecognitionService: textRecognitionService,
            windowManager: windowManager
        )
    }()
    private var textCaptureHotkeyManager: TextCaptureHotkeyManager?
    private var textCaptureHotkeyObserver: NSObjectProtocol?
    private var openKippleHotkeyObserver: NSObjectProtocol?
    
    // Properties for asynchronous termination handling
    private var isTerminating = false
    private var terminationWorkItem: DispatchWorkItem?
    
    // Detect whether we are running in a test environment
    private static var isTestEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        NSClassFromString("XCTest") != nil
    }
    
    override init() {
        // Initialize services using providers
        self.clipboardService = ClipboardServiceProvider.resolve()

        // Initialize with SimplifiedHotkeyManager
        self.hotkeyManager = HotkeyManagerProvider.resolveSync()

        super.init()

        // Skip heavy initialization when running unit tests
        guard !Self.isTestEnvironment else { return }

        // Set up notification for SimplifiedHotkeyManager
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // SimplifiedHotkeyManager uses notifications
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleHotkeyNotification),
                name: NSNotification.Name("toggleMainWindow"),
                object: nil
            )
        }

        // Set the application delegate synchronously (required)
        NSApplication.shared.delegate = self

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setupMenuBar()
            self.setupTextCaptureHotkey()
            self.startServices()
        }
    }
    
    private func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem?.button {
            button.title = "📋"
            
            if let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Kipple") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            }
            
            button.toolTip = "Kipple - Clipboard Manager"
        }
        
        let menu = createMenu()
        statusBarItem?.menu = menu
        statusBarItem?.isVisible = true

        observeOpenKippleHotkeyChanges()
    }

    private func observeOpenKippleHotkeyChanges() {
        if let observer = openKippleHotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
            openKippleHotkeyObserver = nil
        }

        openKippleHotkeyObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HotkeySettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateOpenKippleMenuItemShortcut()
        }
    }
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self
        
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(openKippleMenuEntry())
        menu.addItem(screenTextCaptureMenuEntry())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(screenCaptureMenuItem())
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Kipple", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }

        updateScreenCaptureMenuItem()
        updateOpenKippleMenuItemShortcut()
        updateScreenTextCaptureMenuItemShortcut()
        return menu
    }

    private func startServices() {
        // Perform data migration if needed
        Task {
            await performDataMigrationIfNeeded()

            // Start clipboard monitoring
            clipboardService.startMonitoring()
        }

        // HotkeyManager already registers during initialization
    }

    private func performDataMigrationIfNeeded() async {
        // Migration is no longer needed
    }
    
    @objc private func openMainWindow() {
        Task { @MainActor in
            windowManager.openMainWindow()
        }
    }
    
    @objc private func openPreferences() {
        windowManager.openSettings()
    }
    
    @objc private func showAbout() {
        windowManager.showAbout()
    }

    @objc private func quit() {
        Logger.shared.log("=== QUIT MENU CLICKED ===")
        // Calling terminate triggers applicationShouldTerminate
        NSApplication.shared.terminate(nil)
    }
    
    private func performAsyncTermination() {
        Logger.shared.log("=== ASYNC APP QUIT SEQUENCE STARTED ===")
        Logger.shared.log("Current history count: \(clipboardService.history.count)")
        
        // Timeout handler (maximum 2 seconds)
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            Logger.shared.error("⚠️ Save operation timed out, forcing quit")
            self?.forceTerminate()
        }
        self.terminationWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeoutWorkItem)
        
        // Execute the save work asynchronously
        Task {
            // Flush any debounced saves immediately
            Logger.shared.log("Flushing pending saves...")
            await clipboardService.flushPendingSaves()

            Logger.shared.log("✅ Successfully saved data before quit")
            
            // Cancel the watchdog timeout
            self.terminationWorkItem?.cancel()
            Logger.shared.log("Save operation completed, cancelling timeout")
            
            // Finish termination on the main thread
            await MainActor.run { [weak self] in
                Logger.shared.log("Calling completeTermination on main thread")
                self?.completeTermination()
            }
        }
    }
    
    private func completeTermination() {
        Logger.shared.log("completeTermination called on thread: \(Thread.current)")
        
        Logger.shared.log("Stopping clipboard monitoring...")
        clipboardService.stopMonitoring()
        
        Logger.shared.log("Cleaning up windows...")
        // cleanup method was removed in Swift 6.2 migration
        
        Logger.shared.log("=== APP QUIT SEQUENCE COMPLETED ===")
        
        // Allow the application to terminate
        Logger.shared.log("Calling reply(toApplicationShouldTerminate: true)")
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
        Logger.shared.log("reply(toApplicationShouldTerminate: true) called successfully")
    }
    
    private func forceTerminate() {
        Logger.shared.log("forceTerminate called - timeout occurred")
        
        // Force termination when the timeout fires
        DispatchQueue.main.async { [weak self] in
            Logger.shared.log("forceTerminate on main thread")
            self?.clipboardService.stopMonitoring()
            // cleanup method was removed in Swift 6.2 migration
            
            // Allow the application to terminate immediately
            Logger.shared.log("Calling reply(toApplicationShouldTerminate: true) from forceTerminate")
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
            Logger.shared.log("forceTerminate completed")
        }
    }
}

// MARK: - HotkeyManagerDelegate
// HotkeyManagerDelegate removed - using SimplifiedHotkeyManager notifications instead

// MARK: - Hotkey Handling

extension MenuBarApp {
    @objc func handleHotkeyNotification() {
        Task { @MainActor in
            windowManager.openMainWindow()
        }
    }

    private func setupTextCaptureHotkey() {
        removeTextCaptureHotkeyObserver()

        let manager = TextCaptureHotkeyManager.shared
        textCaptureHotkeyManager = manager
        manager.onHotkeyTriggered = { [weak self] in
            guard let self else { return }
            self.captureTextFromScreen()
        }

        textCaptureHotkeyObserver = registerTextCaptureSettingsObserver(for: manager)

        updateScreenTextCaptureMenuItemShortcut()
    }

    private func removeTextCaptureHotkeyObserver() {
        if let observer = textCaptureHotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
            textCaptureHotkeyObserver = nil
        }
    }

    private func registerTextCaptureSettingsObserver(
        for manager: TextCaptureHotkeyManager
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TextCaptureHotkeySettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                let userInfo = notification.userInfo,
                let keyCode = userInfo["keyCode"] as? Int,
                let modifierFlags = userInfo["modifierFlags"] as? Int
            else { return }

            let enabled = userInfo["enabled"] as? Bool ?? true
            self.handleTextCaptureSettingsChange(
                enabled: enabled,
                keyCode: UInt16(keyCode),
                modifierFlagsRawValue: UInt(modifierFlags),
                manager: manager
            )
        }
    }

    private func handleTextCaptureSettingsChange(
        enabled: Bool,
        keyCode: UInt16,
        modifierFlagsRawValue: UInt,
        manager: TextCaptureHotkeyManager
    ) {
        let allModifiers = NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
        let resolvedModifiers = allModifiers.intersection([.command, .control, .option, .shift])

        if enabled, keyCode != 0, !resolvedModifiers.isEmpty {
            guard manager.applyHotKey(keyCode: keyCode, modifiers: resolvedModifiers) else { return }
            updateScreenTextCaptureMenuItemShortcut(with: keyCode, modifiers: resolvedModifiers)
            return
        }

        guard manager.applyHotKey(keyCode: 0, modifiers: []) else { return }
        updateScreenTextCaptureMenuItemShortcut()
    }
}

extension MenuBarApp {
    private func openKippleMenuEntry() -> NSMenuItem {
        openKippleMenuItem.title = openKippleMenuTitle
        openKippleMenuItem.target = self
        openKippleMenuItem.action = #selector(openMainWindow)
        return openKippleMenuItem
    }

    private func screenTextCaptureMenuEntry() -> NSMenuItem {
        screenTextCaptureMenuItem.title = screenTextCaptureMenuTitle
        screenTextCaptureMenuItem.target = self
        screenTextCaptureMenuItem.action = #selector(captureTextFromScreen)
        return screenTextCaptureMenuItem
    }

    private func updateOpenKippleMenuItemShortcut() {
        guard let manager = hotkeyManager as? SimplifiedHotkeyManager else {
            applyShortcut(to: openKippleMenuItem, title: openKippleMenuTitle, combination: nil)
            return
        }

        guard manager.getEnabled() else {
            applyShortcut(to: openKippleMenuItem, title: openKippleMenuTitle, combination: nil)
            return
        }

        let hotkey = manager.getHotkey()
        let sanitizedModifiers = hotkey.modifiers.intersection([.command, .control, .option, .shift])

        if hotkey.keyCode == 0 || sanitizedModifiers.isEmpty {
            applyShortcut(to: openKippleMenuItem, title: openKippleMenuTitle, combination: nil)
            return
        }

        applyShortcut(
            to: openKippleMenuItem,
            title: openKippleMenuTitle,
            combination: (hotkey.keyCode, sanitizedModifiers)
        )
    }

    private func updateScreenTextCaptureMenuItemShortcut(
        with keyCode: UInt16? = nil,
        modifiers: NSEvent.ModifierFlags? = nil
    ) {
        let baseTitle = screenTextCaptureMenuTitle
        let combination: (UInt16, NSEvent.ModifierFlags)?

        if let keyCode, let modifiers {
            combination = (keyCode, modifiers)
        } else if let hotkey = textCaptureHotkeyManager?.currentHotkey ?? TextCaptureHotkeyManager.shared.currentHotkey {
            combination = hotkey
        } else {
            combination = nil
        }

        if let combination {
            let sanitizedModifiers = combination.1.intersection([.command, .control, .option, .shift])
            if combination.0 == 0 || sanitizedModifiers.isEmpty {
                applyShortcut(to: screenTextCaptureMenuItem, title: baseTitle, combination: nil)
            } else {
                applyShortcut(
                    to: screenTextCaptureMenuItem,
                    title: baseTitle,
                    combination: (combination.0, sanitizedModifiers)
                )
            }
        } else {
            applyShortcut(to: screenTextCaptureMenuItem, title: baseTitle, combination: nil)
        }
    }

    private func shortcutDisplayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        if let mapping = shortcutMapping(for: keyCode) {
            parts.append(mapping.display)
        }

        return parts.joined()
    }

    private func applyShortcut(
        to menuItem: NSMenuItem,
        title: String,
        combination: (UInt16, NSEvent.ModifierFlags)?
    ) {
        menuItem.toolTip = nil

        guard let (keyCode, modifiers) = combination else {
            menuItem.title = title
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
            return
        }

        let mapping = shortcutMapping(for: keyCode)
        let displayString = shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)

        if let keyEquivalent = mapping?.keyEquivalent {
            menuItem.title = title
            menuItem.keyEquivalent = keyEquivalent
            menuItem.keyEquivalentModifierMask = modifiers
        } else if !displayString.isEmpty {
            menuItem.title = "\(title) (\(displayString))"
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
        } else {
            menuItem.title = title
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
        }
    }

    private static let shortcutMap: [UInt16: (display: String, keyEquivalent: String?)] = [
        1: (display: "S", keyEquivalent: "s"),
        2: (display: "D", keyEquivalent: "d"),
        3: (display: "F", keyEquivalent: "f"),
        4: (display: "H", keyEquivalent: "h"),
        5: (display: "G", keyEquivalent: "g"),
        6: (display: "Z", keyEquivalent: "z"),
        7: (display: "X", keyEquivalent: "x"),
        8: (display: "C", keyEquivalent: "c"),
        9: (display: "V", keyEquivalent: "v"),
        11: (display: "B", keyEquivalent: "b"),
        12: (display: "Q", keyEquivalent: "q"),
        13: (display: "W", keyEquivalent: "w"),
        14: (display: "E", keyEquivalent: "e"),
        15: (display: "R", keyEquivalent: "r"),
        16: (display: "Y", keyEquivalent: "y"),
        17: (display: "T", keyEquivalent: "t"),
        18: (display: "1", keyEquivalent: "1"),
        19: (display: "2", keyEquivalent: "2"),
        20: (display: "3", keyEquivalent: "3"),
        21: (display: "4", keyEquivalent: "4"),
        22: (display: "6", keyEquivalent: "6"),
        23: (display: "5", keyEquivalent: "5"),
        24: (display: "=", keyEquivalent: "="),
        25: (display: "9", keyEquivalent: "9"),
        26: (display: "7", keyEquivalent: "7"),
        27: (display: "-", keyEquivalent: "-"),
        28: (display: "8", keyEquivalent: "8"),
        29: (display: "0", keyEquivalent: "0"),
        30: (display: "]", keyEquivalent: "]"),
        31: (display: "O", keyEquivalent: "o"),
        32: (display: "U", keyEquivalent: "u"),
        33: (display: "[", keyEquivalent: "["),
        34: (display: "I", keyEquivalent: "i"),
        35: (display: "P", keyEquivalent: "p"),
        36: (display: "↩︎", keyEquivalent: "\r"),
        37: (display: "L", keyEquivalent: "l"),
        38: (display: "J", keyEquivalent: "j"),
        39: (display: "'", keyEquivalent: "'"),
        40: (display: "K", keyEquivalent: "k"),
        41: (display: ";", keyEquivalent: ";"),
        42: (display: "\\", keyEquivalent: "\\"),
        43: (display: ",", keyEquivalent: ","),
        44: (display: "/", keyEquivalent: "/"),
        45: (display: "N", keyEquivalent: "n"),
        46: (display: "M", keyEquivalent: "m"),
        47: (display: ".", keyEquivalent: "."),
        48: (display: "⇥", keyEquivalent: "\t"),
        49: (display: "Space", keyEquivalent: " "),
        50: (display: "`", keyEquivalent: "`"),
        51: (display: "⌫", keyEquivalent: "\u{8}"),
        53: (display: "⎋", keyEquivalent: "\u{1b}"),
        117: (display: "⌦", keyEquivalent: "\u{7f}"),
        123: (display: "←", keyEquivalent: nil),
        124: (display: "→", keyEquivalent: nil),
        125: (display: "↓", keyEquivalent: nil),
        126: (display: "↑", keyEquivalent: nil)
    ]

    private func shortcutMapping(for keyCode: UInt16) -> (display: String, keyEquivalent: String?)? {
        Self.shortcutMap[keyCode]
    }

    private func screenCaptureMenuItem() -> NSMenuItem {
        screenCaptureStatusItem.target = self
        screenCaptureStatusItem.action = #selector(openScreenRecordingSettingsFromMenu)
        screenCaptureStatusItem.keyEquivalent = ""
        return screenCaptureStatusItem
    }

    private func updateScreenCaptureMenuItem() {
        let granted = CGPreflightScreenCaptureAccess()
        screenCaptureStatusItem.title = granted ? "System Permissions Ready" : "Grant Screen Recording Access…"
        screenCaptureStatusItem.state = granted ? .on : .off
        screenCaptureStatusItem.isEnabled = !granted
        screenCaptureStatusItem.target = granted ? nil : self
        screenCaptureStatusItem.action = granted ? nil : #selector(openScreenRecordingSettingsFromMenu)
    }

    @objc private func openScreenRecordingSettingsFromMenu() {
        Task { @MainActor in
            ScreenRecordingPermissionOpener.openSystemSettings()
        }
    }

    @objc private func captureTextFromScreen() {
        Task { @MainActor [weak self] in
            self?.textCaptureCoordinator.startCaptureFlow()
        }
    }
}

extension MenuBarApp: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateScreenCaptureMenuItem()
        updateOpenKippleMenuItemShortcut()
        updateScreenTextCaptureMenuItemShortcut()
    }
}

#if DEBUG
extension MenuBarApp {
    @MainActor
    func test_handleTextCaptureSettingsChange(
        enabled: Bool,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        manager: TextCaptureHotkeyManager = TextCaptureHotkeyManager.shared
    ) {
        handleTextCaptureSettingsChange(
            enabled: enabled,
            keyCode: keyCode,
            modifierFlagsRawValue: UInt(modifiers.rawValue),
            manager: manager
        )
    }
}
#endif

// MARK: - NSApplicationDelegate
extension MenuBarApp: NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Logger.shared.log("=== applicationShouldTerminate called ===")
        Logger.shared.log("isTerminating flag: \(isTerminating)")
        Logger.shared.log("Sender: \(sender)")
        Logger.shared.log("Current thread: \(Thread.current)")
        
        // Allow immediate termination during tests
        if Self.isTestEnvironment {
            return .terminateNow
        }
        
        // If termination is already in progress
        if isTerminating {
            Logger.shared.log("WARNING: Already terminating, this should not happen!")
            // Permit immediate termination if previous async work is stuck
            return .terminateNow
        }
        
        // Begin the asynchronous termination flow
        isTerminating = true
        performAsyncTermination()
        
        // Cancel termination for now (will reply later)
        return .terminateCancel
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.log("=== applicationWillTerminate called ===")
        // The save work should be finished by this point
    }
}

// MARK: - Test Helpers

#if DEBUG
extension MenuBarApp {
    func startServicesAsync() async {
        startServices()
    }

    func isClipboardMonitoring() async -> Bool {
        if #available(macOS 13.0, *), let modernService = clipboardService as? ModernClipboardServiceAdapter {
            return await modernService.isMonitoring()
        }
        return true
    }

    func performTermination() async {
        // Extract the async work from performAsyncTermination
        // Flush any debounced saves immediately
        Logger.shared.log("Flushing pending saves...")
        await clipboardService.flushPendingSaves()

        Logger.shared.log("✅ Successfully saved data before quit")
    }

    func registerHotkeys() async {
        if let simplifiedManager = hotkeyManager as? SimplifiedHotkeyManager {
            simplifiedManager.setEnabled(true)
        }
    }

    @MainActor
    func isHotkeyRegistered() -> Bool {
        if let simplifiedManager = hotkeyManager as? SimplifiedHotkeyManager {
            return simplifiedManager.getEnabled()
        }
        return false
    }

    // Remove duplicate - already defined as @objc private method
}
#endif
