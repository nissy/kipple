//
//  AppSettings.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    
    // Window Settings
    @AppStorage("windowHeight") var windowHeight: Double = 600
    @AppStorage("windowWidth") var windowWidth: Double = 420
    @AppStorage("windowAnimation") var windowAnimation: String = "fade"
    @AppStorage("editorSectionHeight") var editorSectionHeight: Double = 250
    @AppStorage("historySectionHeight") var historySectionHeight: Double = 300
    
    // Editor Settings
    @AppStorage("lastEditorText") var lastEditorText: String = ""
    @AppStorage("editorInsertMode") var editorInsertMode: Bool = false
    
    // History Settings
    @AppStorage("maxHistoryItems") var maxHistoryItems = 100
    @AppStorage("maxPinnedItems") var maxPinnedItems = 10
    
    // Hotkey Settings
    @AppStorage("enableHotkey") var enableHotkey: Bool = false  // デフォルトで無効
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 9  // V key
    @AppStorage("hotkeyModifierFlags") var hotkeyModifierFlags = 
        Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue)  // CMD+OPT
    
    // Editor Copy Hotkey Settings
    @AppStorage("enableEditorCopyHotkey") var enableEditorCopyHotkey: Bool = false
    @AppStorage("editorCopyHotkeyKeyCode") var editorCopyHotkeyKeyCode: Int = 6  // Z key
    @AppStorage("editorCopyHotkeyModifierFlags") var editorCopyHotkeyModifierFlags = 
        Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)  // CMD+SHIFT
    
    // Editor Clear Hotkey Settings
    @AppStorage("enableEditorClearHotkey") var enableEditorClearHotkey: Bool = false
    @AppStorage("editorClearHotkeyKeyCode") var editorClearHotkeyKeyCode: Int = 7  // X key
    @AppStorage("editorClearHotkeyModifierFlags") var editorClearHotkeyModifierFlags = 
        Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)  // CMD+SHIFT
    
    // Launch Settings
    @AppStorage("autoLaunchAtLogin") var autoLaunchAtLogin: Bool = false
    
    private init() {}
    
    // Settings Keys for consistency
    struct Keys {
        static let windowHeight = "windowHeight"
        static let windowWidth = "windowWidth" 
        static let windowAnimation = "windowAnimation"
        static let editorSectionHeight = "editorSectionHeight"
        static let historySectionHeight = "historySectionHeight"
        static let lastEditorText = "lastEditorText"
        static let editorInsertMode = "editorInsertMode"
        static let maxHistoryItems = "maxHistoryItems"
        static let maxPinnedItems = "maxPinnedItems"
        static let enableHotkey = "enableHotkey"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifierFlags = "hotkeyModifierFlags"
        static let enableEditorCopyHotkey = "enableEditorCopyHotkey"
        static let editorCopyHotkeyKeyCode = "editorCopyHotkeyKeyCode"
        static let editorCopyHotkeyModifierFlags = "editorCopyHotkeyModifierFlags"
        static let enableEditorClearHotkey = "enableEditorClearHotkey"
        static let editorClearHotkeyKeyCode = "editorClearHotkeyKeyCode"
        static let editorClearHotkeyModifierFlags = "editorClearHotkeyModifierFlags"
        static let launchAtLogin = "launchAtLogin"
    }
}
