//
//  MenuBarApp.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
//

import SwiftUI
import Cocoa

final class MenuBarApp: NSObject, ObservableObject {
    private var statusBarItem: NSStatusItem?
    private let clipboardService = ClipboardService.shared
    private let windowManager = WindowManager()
    private let hotkeyManager = HotkeyManager()
    
    // 非同期終了処理用のプロパティ
    private var isTerminating = false
    private var terminationWorkItem: DispatchWorkItem?
    
    // テスト環境かどうかを検出
    private static var isTestEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        NSClassFromString("XCTest") != nil
    }
    
    override init() {
        super.init()
        
        // テスト環境では初期化をスキップ
        guard !Self.isTestEnvironment else { return }
        
        // delegateをすぐに設定
        hotkeyManager.delegate = self
        
        // アプリケーションデリゲートを同期的に設定（重要）
        NSApplication.shared.delegate = self
        
        DispatchQueue.main.async { [weak self] in
            self?.setupMenuBar()
            self?.startServices()
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
        
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open Kipple", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        // Accessibility permission menu item
        let permissionItem = NSMenuItem(
            title: "Grant Accessibility Permission…",
            action: #selector(checkAccessibilityPermission),
            keyEquivalent: ""
        )
        permissionItem.tag = 100
        menu.addItem(permissionItem)
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
        #if DEBUG
        menu.addItem(NSMenuItem(
            title: "Developer Settings…",
            action: #selector(openDeveloperSettings),
            keyEquivalent: ""
        ))
        #endif
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Kipple", action: #selector(quit), keyEquivalent: "q"))
        
        menu.items.forEach { $0.target = self }
        
        // Set menu delegate for dynamic updates
        menu.delegate = self
        
        return menu
    }
    
    private func startServices() {
        clipboardService.startMonitoring()
        
        // HotkeyManagerは既に初期化時に登録を行うため、追加の登録は不要
    }
    
    @objc private func openMainWindow() {
        windowManager.openMainWindow()
    }
    
    @objc private func openPreferences() {
        windowManager.openSettings()
    }
    
    @objc private func showAbout() {
        windowManager.showAbout()
    }
    
    #if DEBUG
    @objc private func openDeveloperSettings() {
        windowManager.openDeveloperSettings()
    }
    #endif
    
    @objc private func checkAccessibilityPermission() {
        AccessibilityManager.shared.refreshPermissionStatus()  // Force refresh
        
        if AccessibilityManager.shared.hasPermission {
            // Permission already granted
            showPermissionGrantedNotification()
        } else {
            // No permission - show alert and request
            AccessibilityManager.shared.showAccessibilityAlert()
        }
    }
    
    private func showPermissionGrantedNotification() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Permission Already Granted"
            alert.informativeText = """
                Kipple already has accessibility permission.
                App names and window titles are being captured.
                """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
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
            do {
                // Core Dataが初期化されていることを確認
                Logger.shared.log("Ensuring Core Data is initialized...")
                CoreDataStack.shared.initializeAndWait()
                
                // デバウンスされた保存を即座に実行
                Logger.shared.log("Flushing pending saves...")
                await clipboardService.flushPendingSaves()
                
                // Core Dataの保存を確実に実行（WALチェックポイント含む）
                Logger.shared.log("Saving Core Data context...")
                try await MainActor.run {
                    try CoreDataStack.shared.save()
                }
                Logger.shared.log("✅ Successfully saved data before quit")
                
                // 保存されたデータを確認（デバッグ用）
                let repository = CoreDataClipboardRepository()
                let savedItems = try await repository.load(limit: 10)
                Logger.shared.log("Verified saved items count: \(savedItems.count)")
            } catch {
                Logger.shared.error("❌ Failed to save on quit: \(error)")
            }
            
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
        windowManager.cleanup()
        
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
            self?.windowManager.cleanup()
            
            // アプリケーションに終了を許可
            Logger.shared.log("Calling reply(toApplicationShouldTerminate: true) from forceTerminate")
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
            Logger.shared.log("forceTerminate completed")
        }
    }
}

// MARK: - NSMenuDelegate
extension MenuBarApp: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Update permission menu item
        for item in menu.items where item.tag == 100 {
            let hasPermission = AccessibilityManager.shared.hasPermission
            item.title = hasPermission ? "Accessibility Permission Granted ✓" : "Grant Accessibility Permission…"
            // Always enable the menu item to allow checking status
            item.isEnabled = true
        }
    }
}

// MARK: - HotkeyManagerDelegate
extension MenuBarApp: HotkeyManagerDelegate {
    func hotkeyPressed() {
        openMainWindow()
    }
    
    func editorCopyHotkeyPressed() {
        // MainViewModelのインスタンスを取得してコピー処理を実行
        if let mainViewModel = windowManager.getMainViewModel() {
            Task { @MainActor in
                mainViewModel.copyEditor()
                // コピー通知を表示
                windowManager.showCopiedNotification()
                // Copyボタンのショートカットキーでもウィンドウを閉じない（ピンの状態に関わらず）
            }
        }
    }
    
    func editorClearHotkeyPressed() {
        // MainViewModelのインスタンスを取得してクリア処理を実行
        if let mainViewModel = windowManager.getMainViewModel() {
            Task { @MainActor in
                mainViewModel.clearEditor()
                // クリア後もウィンドウは開いたまま
            }
        }
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
