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
    @AppStorage("windowAnimation") var windowAnimation: String = "none"
    @AppStorage("editorSectionHeight") var editorSectionHeight: Double = 250
    @AppStorage("historySectionHeight") var historySectionHeight: Double = 300
    
    // Editor Settings
    @AppStorage("lastEditorText") var lastEditorText: String = ""
    @AppStorage("editorInsertMode") var editorInsertMode: Bool = false
    
    // History Settings
    @AppStorage("maxHistoryItems") var maxHistoryItems = 300
    @AppStorage("maxPinnedItems") var maxPinnedItems = 20
    
    // Hotkey Settings
    @AppStorage("enableHotkey") var enableHotkey: Bool = false  // デフォルトで無効
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 9  // V key
    @AppStorage("hotkeyModifierFlags") var hotkeyModifierFlags = 
        Int(NSEvent.ModifierFlags.control.rawValue)  // CTRL
    
    // Editor Copy Hotkey Settings
    @AppStorage("enableEditorCopyHotkey") var enableEditorCopyHotkey: Bool = false
    @AppStorage("editorCopyHotkeyKeyCode") var editorCopyHotkeyKeyCode: Int = 1  // S key
    @AppStorage("editorCopyHotkeyModifierFlags") var editorCopyHotkeyModifierFlags = 
        Int(NSEvent.ModifierFlags.command.rawValue)  // CMD
    
    // Editor Clear Hotkey Settings
    @AppStorage("enableEditorClearHotkey") var enableEditorClearHotkey: Bool = false
    @AppStorage("editorClearHotkeyKeyCode") var editorClearHotkeyKeyCode: Int = 12  // Q key
    @AppStorage("editorClearHotkeyModifierFlags") var editorClearHotkeyModifierFlags = 
        Int(NSEvent.ModifierFlags.command.rawValue)  // CMD
    
    // Launch Settings
    @AppStorage("autoLaunchAtLogin") var autoLaunchAtLogin: Bool = false
    
    // Category Filter Settings
    @AppStorage("filterCategoryURL") var filterCategoryURL: Bool = true
    @AppStorage("filterCategoryEmail") var filterCategoryEmail: Bool = false
    @AppStorage("filterCategoryCode") var filterCategoryCode: Bool = true
    @AppStorage("filterCategoryFilePath") var filterCategoryFilePath: Bool = true
    @AppStorage("filterCategoryShortText") var filterCategoryShortText: Bool = false
    @AppStorage("filterCategoryLongText") var filterCategoryLongText: Bool = false
    @AppStorage("filterCategoryGeneral") var filterCategoryGeneral: Bool = false
    
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
        static let filterCategoryURL = "filterCategoryURL"
        static let filterCategoryEmail = "filterCategoryEmail"
        static let filterCategoryCode = "filterCategoryCode"
        static let filterCategoryFilePath = "filterCategoryFilePath"
        static let filterCategoryShortText = "filterCategoryShortText"
        static let filterCategoryLongText = "filterCategoryLongText"
        static let filterCategoryGeneral = "filterCategoryGeneral"
    }
}
