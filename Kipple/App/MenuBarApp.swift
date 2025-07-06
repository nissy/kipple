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
    
    override init() {
        super.init()
        // delegateをすぐに設定
        hotkeyManager.delegate = self
        
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
            title: "Grant Accessibility Permission...",
            action: #selector(checkAccessibilityPermission),
            keyEquivalent: ""
        )
        permissionItem.tag = 100
        menu.addItem(permissionItem)
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        #if DEBUG
        menu.addItem(NSMenuItem(
            title: "Developer Settings...",
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
        clipboardService.stopMonitoring()
        windowManager.cleanup()
        // hotkeyManager は deinit で自動的にクリーンアップされる
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - NSMenuDelegate
extension MenuBarApp: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Update permission menu item
        for item in menu.items where item.tag == 100 {
            let hasPermission = AccessibilityManager.shared.hasPermission
            item.title = hasPermission ? "Accessibility Permission Granted ✓" : "Grant Accessibility Permission..."
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
                // ピン（常に最前面）が有効でない場合のみウィンドウを閉じる
                if !windowManager.isWindowAlwaysOnTop() {
                    windowManager.closeMainWindow()
                }
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
