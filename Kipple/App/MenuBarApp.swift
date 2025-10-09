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
    }
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Kipple", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(screenCaptureMenuItem())
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Kipple", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }

        updateScreenCaptureMenuItem()
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
        ) { [weak manager] notification in
            guard let manager else { return }
            guard
                let userInfo = notification.userInfo,
                let keyCode = userInfo["keyCode"] as? Int,
                let modifierFlags = userInfo["modifierFlags"] as? Int
            else { return }

            let enabled = userInfo["enabled"] as? Bool ?? true
            let flags = NSEvent.ModifierFlags(rawValue: UInt(modifierFlags))

            if enabled, keyCode != 0, !flags.isEmpty {
                _ = manager.applyHotKey(keyCode: UInt16(keyCode), modifiers: flags)
            } else {
                _ = manager.applyHotKey(keyCode: 0, modifiers: [])
            }
        }
    }
}

extension MenuBarApp {
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
