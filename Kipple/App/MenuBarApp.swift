//
//  MenuBarApp.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

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
    
    // 非同期終了処理用のプロパティ
    private var isTerminating = false
    private var terminationWorkItem: DispatchWorkItem?
    
    // テスト環境かどうかを検出
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

        // テスト環境では初期化をスキップ
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

        // アプリケーションデリゲートを同期的に設定（重要）
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
        let menu = NSMenu()
        menu.delegate = self
        
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(openKippleMenuEntry())
        menu.addItem(screenTextCaptureMenuEntry())
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

        // HotkeyManagerは既に初期化時に登録を行うため、追加の登録は不要
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
        // NSApplication.terminate を呼ぶことで、applicationShouldTerminate を通る
        NSApplication.shared.terminate(nil)
    }
    
    private func performAsyncTermination() {
        Logger.shared.log("=== ASYNC APP QUIT SEQUENCE STARTED ===")
        Logger.shared.log("Current history count: \(clipboardService.history.count)")
        
        // タイムアウト処理（最大2秒）
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            Logger.shared.error("⚠️ Save operation timed out, forcing quit")
            self?.forceTerminate()
        }
        self.terminationWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeoutWorkItem)
        
        // 非同期で保存処理を実行
        Task {
            // デバウンスされた保存を即座に実行
            Logger.shared.log("Flushing pending saves...")
            await clipboardService.flushPendingSaves()

            Logger.shared.log("✅ Successfully saved data before quit")
            
            // タイムアウトをキャンセル
            self.terminationWorkItem?.cancel()
            Logger.shared.log("Save operation completed, cancelling timeout")
            
            // メインスレッドで終了処理を実行
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
        
        // アプリケーションに終了を許可
        Logger.shared.log("Calling reply(toApplicationShouldTerminate: true)")
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
        Logger.shared.log("reply(toApplicationShouldTerminate: true) called successfully")
    }
    
    private func forceTerminate() {
        Logger.shared.log("forceTerminate called - timeout occurred")
        
        // タイムアウト時の強制終了
        DispatchQueue.main.async { [weak self] in
            Logger.shared.log("forceTerminate on main thread")
            self?.clipboardService.stopMonitoring()
            // cleanup method was removed in Swift 6.2 migration
            
            // アプリケーションに終了を許可
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
        if let observer = textCaptureHotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
            textCaptureHotkeyObserver = nil
        }

        let manager = TextCaptureHotkeyManager.shared
        textCaptureHotkeyManager = manager
        manager.onHotkeyTriggered = { [weak self] in
            guard let self else { return }
            self.captureTextFromScreen()
        }

        textCaptureHotkeyObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TextCaptureHotkeySettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let manager = self.textCaptureHotkeyManager else { return }
            guard
                let userInfo = notification.userInfo,
                let keyCode = userInfo["keyCode"] as? Int,
                let modifierFlags = userInfo["modifierFlags"] as? Int
            else { return }

            let enabled = userInfo["enabled"] as? Bool ?? true
            let resolvedModifiers = NSEvent.ModifierFlags(rawValue: UInt(modifierFlags)).intersection([.command, .control, .option, .shift])
            let resolvedKeyCode = UInt16(keyCode)

            if enabled, resolvedKeyCode != 0, !resolvedModifiers.isEmpty {
                if manager.applyHotKey(keyCode: resolvedKeyCode, modifiers: resolvedModifiers) {
                    self.updateScreenTextCaptureMenuItemShortcut(with: resolvedKeyCode, modifiers: resolvedModifiers)
                }
            } else {
                if manager.applyHotKey(keyCode: 0, modifiers: []) {
                    self.updateScreenTextCaptureMenuItemShortcut()
                }
            }
        }

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
        guard let (keyCode, modifiers) = combination else {
            menuItem.title = title
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
            menuItem.toolTip = nil
            return
        }

        let mapping = shortcutMapping(for: keyCode)
        let displayString = shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)

        if let keyEquivalent = mapping?.keyEquivalent {
            menuItem.title = title
            menuItem.keyEquivalent = keyEquivalent
            menuItem.keyEquivalentModifierMask = modifiers
            menuItem.toolTip = displayString.isEmpty ? nil : displayString
        } else if !displayString.isEmpty {
            menuItem.title = "\(title) (\(displayString))"
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
            menuItem.toolTip = displayString
        } else {
            menuItem.title = title
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
            menuItem.toolTip = nil
        }
    }

    private func shortcutMapping(for keyCode: UInt16) -> (display: String, keyEquivalent: String?)? {
        let map: [UInt16: (String, String?)] = [
            1: ("S", "s"),
            2: ("D", "d"),
            3: ("F", "f"),
            4: ("H", "h"),
            5: ("G", "g"),
            6: ("Z", "z"),
            7: ("X", "x"),
            8: ("C", "c"),
            9: ("V", "v"),
            11: ("B", "b"),
            12: ("Q", "q"),
            13: ("W", "w"),
            14: ("E", "e"),
            15: ("R", "r"),
            16: ("Y", "y"),
            17: ("T", "t"),
            18: ("1", "1"),
            19: ("2", "2"),
            20: ("3", "3"),
            21: ("4", "4"),
            22: ("6", "6"),
            23: ("5", "5"),
            24: ("=", "="),
            25: ("9", "9"),
            26: ("7", "7"),
            27: ("-", "-"),
            28: ("8", "8"),
            29: ("0", "0"),
            30: ("]", "]"),
            31: ("O", "o"),
            32: ("U", "u"),
            33: ("[", "["),
            34: ("I", "i"),
            35: ("P", "p"),
            36: ("↩︎", "\r"),
            37: ("L", "l"),
            38: ("J", "j"),
            39: ("'", "'"),
            40: ("K", "k"),
            41: (";", ";"),
            42: ("\\", "\\"),
            43: (",", ","),
            44: ("/", "/"),
            45: ("N", "n"),
            46: ("M", "m"),
            47: (".", "."),
            48: ("⇥", "\t"),
            49: ("Space", " "),
            50: ("`", "`"),
            51: ("⌫", "\u{8}"),
            53: ("⎋", "\u{1b}"),
            117: ("⌦", "\u{7f}"),
            123: ("←", nil),
            124: ("→", nil),
            125: ("↓", nil),
            126: ("↑", nil)
        ]

        return map[keyCode]
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

// MARK: - NSApplicationDelegate
extension MenuBarApp: NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Logger.shared.log("=== applicationShouldTerminate called ===")
        Logger.shared.log("isTerminating flag: \(isTerminating)")
        Logger.shared.log("Sender: \(sender)")
        Logger.shared.log("Current thread: \(Thread.current)")
        
        // テスト環境では即座に終了を許可
        if Self.isTestEnvironment {
            return .terminateNow
        }
        
        // 既に終了処理中の場合
        if isTerminating {
            Logger.shared.log("WARNING: Already terminating, this should not happen!")
            // 即座に終了を許可（前回の非同期処理が何らかの理由で完了していない）
            return .terminateNow
        }
        
        // 非同期終了処理を開始
        isTerminating = true
        performAsyncTermination()
        
        // 一旦終了をキャンセル（後で reply(toApplicationShouldTerminate:) を呼ぶ）
        return .terminateCancel
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.shared.log("=== applicationWillTerminate called ===")
        // この時点ではすでに保存処理は完了しているはず
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
        // デバウンスされた保存を即座に実行
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
