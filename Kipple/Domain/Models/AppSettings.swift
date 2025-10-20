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
    @AppStorage("editorInsertModifiers") var editorInsertModifiers = Int(NSEvent.ModifierFlags.control.rawValue)
    @AppStorage("editorPosition") private var storedEditorPosition: String = "bottom"
    @AppStorage("editorPositionLastEnabled") private var storedEditorPositionLastEnabled: String = "bottom"

    var editorPosition: String {
        get { storedEditorPosition }
        set {
            guard newValue != storedEditorPosition else { return }
            objectWillChange.send()
            if newValue != "disabled" {
                storedEditorPositionLastEnabled = newValue
            } else if storedEditorPosition != "disabled" {
                storedEditorPositionLastEnabled = storedEditorPosition
            }
            storedEditorPosition = newValue
        }
    }

    var editorPositionLastEnabled: String {
        if storedEditorPositionLastEnabled == "disabled" {
            return "bottom"
        }
        return storedEditorPositionLastEnabled
    }
    
    // History Settings
    @AppStorage("maxHistoryItems") var maxHistoryItems = 300
    @AppStorage("maxPinnedItems") var maxPinnedItems = 50
    
    // Hotkey Settings
    @AppStorage("enableHotkey") var enableHotkey: Bool = false  // デフォルトで無効
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 0  // None by default
    @AppStorage("hotkeyModifierFlags") var hotkeyModifierFlags: Int = 0  // None by default
    
    // Editor Copy Hotkey Settings (always enabled)
    @AppStorage("editorCopyHotkeyKeyCode") var editorCopyHotkeyKeyCode: Int = 1  // S key
    @AppStorage("editorCopyHotkeyModifierFlags") var editorCopyHotkeyModifierFlags = 
        Int(NSEvent.ModifierFlags.command.rawValue)  // CMD
    
    // Editor Clear Hotkey Settings (always enabled)
    @AppStorage("editorClearHotkeyKeyCode") var editorClearHotkeyKeyCode: Int = 37  // L key
    @AppStorage("editorClearHotkeyModifierFlags") var editorClearHotkeyModifierFlags = 
        Int(NSEvent.ModifierFlags.command.rawValue)  // CMD
    
    // Launch Settings
    @AppStorage("autoLaunchAtLogin") var autoLaunchAtLogin: Bool = false
    
    // Category Filter Settings
    @AppStorage("filterCategoryURL") private var storedFilterCategoryURL: Bool = true
    @AppStorage("filterCategoryNone") private var storedFilterCategoryNone: Bool = false
    
    var filterCategoryURL: Bool {
        get { storedFilterCategoryURL }
        set {
            guard storedFilterCategoryURL != newValue else { return }
            objectWillChange.send()
            storedFilterCategoryURL = newValue
        }
    }
    
    var filterCategoryNone: Bool {
        get { storedFilterCategoryNone }
        set {
            guard storedFilterCategoryNone != newValue else { return }
            objectWillChange.send()
            storedFilterCategoryNone = newValue
        }
    }
    
    // Auto-Clear Settings
    @AppStorage("enableAutoClear") var enableAutoClear: Bool = true
    @AppStorage("autoClearInterval") var autoClearInterval: Int = 10 // in minutes

    // Action Click Settings (modifier required to trigger item action by click)
    @AppStorage("actionClickModifiers") var actionClickModifiers = Int(NSEvent.ModifierFlags.command.rawValue)
    
    private init() {
        if storedFilterCategoryNone {
            storedFilterCategoryNone = false
        }
    }
    
    // Settings Keys for consistency
    struct Keys {
        static let windowHeight = "windowHeight"
        static let windowWidth = "windowWidth" 
        static let windowAnimation = "windowAnimation"
        static let editorSectionHeight = "editorSectionHeight"
        static let historySectionHeight = "historySectionHeight"
        static let lastEditorText = "lastEditorText"
        static let editorInsertMode = "editorInsertMode"
        static let editorPosition = "editorPosition"
        static let editorInsertModifiers = "editorInsertModifiers"
        static let maxHistoryItems = "maxHistoryItems"
        static let maxPinnedItems = "maxPinnedItems"
        static let enableHotkey = "enableHotkey"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifierFlags = "hotkeyModifierFlags"
        // enableEditorCopyHotkey removed: always enabled
        static let editorCopyHotkeyKeyCode = "editorCopyHotkeyKeyCode"
        static let editorCopyHotkeyModifierFlags = "editorCopyHotkeyModifierFlags"
        // enableEditorClearHotkey removed: always enabled
        static let editorClearHotkeyKeyCode = "editorClearHotkeyKeyCode"
        static let editorClearHotkeyModifierFlags = "editorClearHotkeyModifierFlags"
        static let launchAtLogin = "launchAtLogin"
        static let filterCategoryURL = "filterCategoryURL"
        static let filterCategoryNone = "filterCategoryNone"
    }
}
