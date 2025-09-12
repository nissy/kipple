//
//  HotkeyManager.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import Foundation
import Carbon
import AppKit

protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyPressed()
    func editorCopyHotkeyPressed()
    func editorClearHotkeyPressed()
}

final class HotkeyManager {
    weak var delegate: HotkeyManagerDelegate?
    
    private var hotKeyEventHandler: EventHandlerRef?
    private var currentHotKey: EventHotKeyRef?
    private var editorCopyHotKey: EventHotKeyRef?
    private var editorClearHotKey: EventHotKeyRef?
    private var settingsObserver: NSObjectProtocol?
    private var editorCopySettingsObserver: NSObjectProtocol?
    private var editorClearSettingsObserver: NSObjectProtocol?
    private var windowBecameKeyObserver: NSObjectProtocol?
    private var windowResignedKeyObserver: NSObjectProtocol?
    private static var shared: HotkeyManager?
    private var editorHotkeysActive = false
    
    init() {
        HotkeyManager.shared = self
        setupSettingsObserver()
        // ホットキーの登録を遅延実行（短い遅延で十分）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.registerAllHotkeys()
        }
    }
    
    private func registerAllHotkeys() {
        Logger.shared.log("Registering required hotkeys…")
        registerCurrentHotkey()
        if editorHotkeysActive {
            registerEditorCopyHotkey()
            registerEditorClearHotkey()
        } else {
            unregisterEditorCopyHotkey()
            unregisterEditorClearHotkey()
        }
    }
    
    // アプリケーション起動完了後に呼び出すメソッド
    func refreshHotkeys() {
        Logger.shared.log("Refreshing hotkeys…")
        registerAllHotkeys()
    }
    
    deinit {
        cleanup()
    }
    
    private func setupSettingsObserver() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HotkeySettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerCurrentHotkey()
        }
        
        editorCopySettingsObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("EditorCopyHotkeySettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let enabled = UserDefaults.standard.bool(forKey: "enableEditorCopyHotkey")
            if !enabled {
                self.unregisterEditorCopyHotkey()
                return
            }
            if self.editorHotkeysActive {
                self.registerEditorCopyHotkey()
            }
        }
        
        editorClearSettingsObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("EditorClearHotkeySettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let enabled = UserDefaults.standard.bool(forKey: "enableEditorClearHotkey")
            if !enabled {
                self.unregisterEditorClearHotkey()
                return
            }
            if self.editorHotkeysActive {
                self.registerEditorClearHotkey()
            }
        }

        // Window focus based activation for editor hotkeys
        windowBecameKeyObserver = NotificationCenter.default.addObserver(
            forName: .mainWindowDidBecomeKey,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.activateEditorHotkeysIfNeeded()
        }

        windowResignedKeyObserver = NotificationCenter.default.addObserver(
            forName: .mainWindowDidResignKey,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.deactivateEditorHotkeys()
        }
    }
    
    func registerCurrentHotkey() {
        // 既存のホットキーを削除
        unregisterHotkey()
        
        // AppStorageから設定を読み込み
        let enableHotkey = UserDefaults.standard.bool(forKey: "enableHotkey")
        guard enableHotkey else { 
            Logger.shared.log("Main hotkey is disabled")
            return 
        }
        
        // キーコードとモディファイアフラグを読み込み
        let keyCode = UInt16(UserDefaults.standard.integer(forKey: "hotkeyKeyCode"))
        let modifierFlagsRaw = UserDefaults.standard.integer(forKey: "hotkeyModifierFlags")
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(modifierFlagsRaw))
        
        // デフォルト値の設定（初回起動時）
        if keyCode == 0 && modifierFlagsRaw == 0 {
            UserDefaults.standard.set(9, forKey: "hotkeyKeyCode") // V key
            UserDefaults.standard.set(
                NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue, 
                forKey: "hotkeyModifierFlags"
            ) // CMD+OPT
            Logger.shared.log("Set default hotkey values")
            registerCurrentHotkey() // 再帰的に呼び出し
            return
        }
        
        // Carbon modifierを計算
        var carbonModifiers: UInt32 = 0
        if modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        
        // ホットキーを登録
        Logger.shared.log("Registering main hotkey with keyCode: \(keyCode), modifiers: \(modifierFlags)")
        registerHotkey(keyCode: UInt32(keyCode), modifiers: carbonModifiers)
    }
    
    private func registerHotkey(keyCode: UInt32, modifiers: UInt32) {
        // イベントハンドラがなければ作成
        if hotKeyEventHandler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            
            let handler: EventHandlerUPP = { _, inEvent, _ -> OSStatus in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    inEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                
                // staticな参照を使用
                HotkeyManager.shared?.handleHotkeyEvent(hotKeyID: hotKeyID)
                return noErr
            }
            
            InstallEventHandler(
                GetApplicationEventTarget(),
                handler,
                1,
                &eventType,
                nil, // userDataは使用しない
                &hotKeyEventHandler
            )
        }
        
        // ホットキーIDを作成
        let hotKeyID = EventHotKeyID(signature: OSType(0x514B5350), id: 1) // "QKSP" in hex
        
        // ホットキーを登録
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &currentHotKey)
    }
    
    private func unregisterHotkey() {
        if let hotKey = currentHotKey {
            UnregisterEventHotKey(hotKey)
            currentHotKey = nil
        }
    }
    
    private func handleHotkeyEvent(hotKeyID: EventHotKeyID) {
        DispatchQueue.main.async { [weak self] in
            if hotKeyID.id == 1 {
                self?.delegate?.hotkeyPressed()
            } else if hotKeyID.id == 2 {
                self?.delegate?.editorCopyHotkeyPressed()
            } else if hotKeyID.id == 3 {
                self?.delegate?.editorClearHotkeyPressed()
            }
        }
    }
    
    private func cleanup() {
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
            settingsObserver = nil
        }
        
        if let observer = editorCopySettingsObserver {
            NotificationCenter.default.removeObserver(observer)
            editorCopySettingsObserver = nil
        }
        
        if let observer = editorClearSettingsObserver {
            NotificationCenter.default.removeObserver(observer)
            editorClearSettingsObserver = nil
        }
        if let observer = windowBecameKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            windowBecameKeyObserver = nil
        }
        if let observer = windowResignedKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            windowResignedKeyObserver = nil
        }
        
        unregisterHotkey()
        unregisterEditorCopyHotkey()
        unregisterEditorClearHotkey()
        if let handler = hotKeyEventHandler {
            RemoveEventHandler(handler)
            hotKeyEventHandler = nil
        }
    }

    // MARK: - Editor hotkeys lifecycle
    private func activateEditorHotkeysIfNeeded() {
        guard !editorHotkeysActive else { return }
        editorHotkeysActive = true
        if UserDefaults.standard.bool(forKey: "enableEditorCopyHotkey") {
            registerEditorCopyHotkey()
        }
        if UserDefaults.standard.bool(forKey: "enableEditorClearHotkey") {
            registerEditorClearHotkey()
        }
    }

    private func deactivateEditorHotkeys() {
        guard editorHotkeysActive else { return }
        unregisterEditorCopyHotkey()
        unregisterEditorClearHotkey()
        editorHotkeysActive = false
    }
    
    // MARK: - Editor Copy Hotkey
    
    func registerEditorCopyHotkey() {
        // 既存のエディターコピーホットキーを削除
        unregisterEditorCopyHotkey()
        
        // AppStorageから設定を読み込み
        let enableEditorCopyHotkey = UserDefaults.standard.bool(forKey: "enableEditorCopyHotkey")
        guard enableEditorCopyHotkey else { 
            Logger.shared.log("Editor copy hotkey is disabled")
            return 
        }
        
        // キーコードとモディファイアフラグを読み込み
        let keyCode = UInt16(UserDefaults.standard.integer(forKey: "editorCopyHotkeyKeyCode"))
        let modifierFlagsRaw = UserDefaults.standard.integer(forKey: "editorCopyHotkeyModifierFlags")
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(modifierFlagsRaw))
        
        // デフォルト値の設定（初回起動時）
        if keyCode == 0 && modifierFlagsRaw == 0 {
            UserDefaults.standard.set(6, forKey: "editorCopyHotkeyKeyCode") // Z key
            UserDefaults.standard.set(
                NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue, 
                forKey: "editorCopyHotkeyModifierFlags"
            ) // CMD+SHIFT
            Logger.shared.log("Set default editor copy hotkey values")
            registerEditorCopyHotkey() // 再帰的に呼び出し
            return
        }
        
        // Carbon modifierを計算
        var carbonModifiers: UInt32 = 0
        if modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        
        // ホットキーIDを作成（id: 2 はエディターコピー用）
        let hotKeyID = EventHotKeyID(signature: OSType(0x514B5350), id: 2) // "QKSP" in hex
        
        // ホットキーを登録
        Logger.shared.log("Registering editor copy hotkey with keyCode: \(keyCode), modifiers: \(modifierFlags)")
        RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &editorCopyHotKey
        )
    }
    
    private func unregisterEditorCopyHotkey() {
        if let hotKey = editorCopyHotKey {
            UnregisterEventHotKey(hotKey)
            editorCopyHotKey = nil
        }
    }
    
    // MARK: - Editor Clear Hotkey
    
    func registerEditorClearHotkey() {
        // 既存のエディタークリアホットキーを削除
        unregisterEditorClearHotkey()
        
        // AppStorageから設定を読み込み
        let enableEditorClearHotkey = UserDefaults.standard.bool(forKey: "enableEditorClearHotkey")
        guard enableEditorClearHotkey else { 
            Logger.shared.log("Editor clear hotkey is disabled")
            return 
        }
        
        // キーコードとモディファイアフラグを読み込み
        let keyCode = UInt16(UserDefaults.standard.integer(forKey: "editorClearHotkeyKeyCode"))
        let modifierFlagsRaw = UserDefaults.standard.integer(forKey: "editorClearHotkeyModifierFlags")
        let modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(modifierFlagsRaw))
        
        // デフォルト値の設定（初回起動時）
        if keyCode == 0 && modifierFlagsRaw == 0 {
            UserDefaults.standard.set(7, forKey: "editorClearHotkeyKeyCode") // X key
            UserDefaults.standard.set(
                NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue, 
                forKey: "editorClearHotkeyModifierFlags"
            ) // CMD+SHIFT
            Logger.shared.log("Set default editor clear hotkey values")
            registerEditorClearHotkey() // 再帰的に呼び出し
            return
        }
        
        // Carbon modifierを計算
        var carbonModifiers: UInt32 = 0
        if modifierFlags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifierFlags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifierFlags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        
        // ホットキーIDを作成（id: 3 はエディタークリア用）
        let hotKeyID = EventHotKeyID(signature: OSType(0x514B5350), id: 3) // "QKSP" in hex
        
        // ホットキーを登録
        Logger.shared.log("Registering editor clear hotkey with keyCode: \(keyCode), modifiers: \(modifierFlags)")
        RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &editorClearHotKey
        )
    }
    
    private func unregisterEditorClearHotkey() {
        if let hotKey = editorClearHotKey {
            UnregisterEventHotKey(hotKey)
            editorClearHotKey = nil
        }
    }
}
