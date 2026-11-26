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

    @AppStorage(Keys.desktopNoteDefaultDisplayMode)
    private var storedDesktopNoteDisplayMode = DesktopNoteDisplayMode.plainText

    @AppStorage(Keys.desktopNoteDisplayID) var desktopNoteDisplayID = ""

    @AppStorage(Keys.desktopNoteOnRepeatedCopy) var desktopNoteOnRepeatedCopy = true {
        didSet {
            if oldValue != desktopNoteOnRepeatedCopy { desktopNoteRepeatedCopySettingRevision &+= 1 }
        }
    }
    private(set) var desktopNoteRepeatedCopySettingRevision: UInt64 = 0

    var desktopNoteDefaultDisplayMode: DesktopNoteDisplayMode {
        get { storedDesktopNoteDisplayMode }
        set {
            guard newValue != storedDesktopNoteDisplayMode else { return }
            objectWillChange.send()
            storedDesktopNoteDisplayMode = newValue
        }
    }

    enum DesktopNoteDisplayMode: String {
        case plainText
        case markdown
    }

    // Editor Settings
    @AppStorage("editorPosition") private var storedEditorPosition: String = "disabled"
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
    @AppStorage("historySelectPaste") var historySelectPaste = false

    // Hotkey Settings
    @AppStorage("enableHotkey") var enableHotkey: Bool = false  // デフォルトで無効
    @AppStorage("hotkeyKeyCode") var hotkeyKeyCode: Int = 0  // None by default
    @AppStorage("hotkeyModifierFlags") var hotkeyModifierFlags: Int = 0  // None by default
    
    // Editor Save Hotkey Settings (always enabled)
    @AppStorage("editorCopyHotkeyKeyCode") var editorCopyHotkeyKeyCode: Int = 1  // S key
    @AppStorage("editorCopyHotkeyModifierFlags") var editorCopyHotkeyModifierFlags = 
        Int(NSEvent.ModifierFlags.command.rawValue)  // CMD
    
    // Editor Clear Hotkey Settings (always enabled)
    @AppStorage("editorClearHotkeyKeyCode") var editorClearHotkeyKeyCode: Int = 37  // L key
    @AppStorage("editorClearHotkeyModifierFlags") var editorClearHotkeyModifierFlags = 
        Int(NSEvent.ModifierFlags.command.rawValue)  // CMD

    enum EditorHotkey {
        case save
        case clear
    }

    func editorHotkey(for event: NSEvent) -> EditorHotkey? {
        let mask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
        let modifiers = event.modifierFlags.intersection(mask)

        func matches(keyCode: Int, modifierFlags: Int) -> Bool {
            guard keyCode == Int(event.keyCode), let rawModifiers = UInt(exactly: modifierFlags) else { return false }
            let configuredModifiers = NSEvent.ModifierFlags(rawValue: rawModifiers).intersection(mask)
            return (keyCode != 0 || !configuredModifiers.isEmpty) && modifiers == configuredModifiers
        }

        if matches(keyCode: editorCopyHotkeyKeyCode, modifierFlags: editorCopyHotkeyModifierFlags) {
            return .save
        }
        if matches(keyCode: editorClearHotkeyKeyCode, modifierFlags: editorClearHotkeyModifierFlags) {
            return .clear
        }
        return nil
    }
    
    // Launch Settings
    
    // Category Filter Settings
    @AppStorage("filterCategoryURL") private var storedFilterCategoryURL: Bool = true
    @AppStorage("filterCategoryNone") private var storedFilterCategoryNone: Bool = false
    @AppStorage("filterCategoryOCR") private var storedFilterCategoryOCR: Bool = true
    @AppStorage("filterCategoryAI") private var storedFilterCategoryAI: Bool = true

    var filterCategoryOCR: Bool {
        get { storedFilterCategoryOCR }
        set { objectWillChange.send(); storedFilterCategoryOCR = newValue }
    }

    var filterCategoryAI: Bool {
        get { storedFilterCategoryAI }
        set { objectWillChange.send(); storedFilterCategoryAI = newValue }
    }
    
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

    // Action Click Settings (modifier required to trigger item action by click)
    @AppStorage("actionClickModifiers") var actionClickModifiers = Int(NSEvent.ModifierFlags.option.rawValue)
    
    // Localization
    @AppStorage("appLanguage") private var storedAppLanguage = LanguageOption.system.rawValue

    var appLanguage: LanguageOption {
        get { LanguageOption(rawValue: storedAppLanguage) ?? .system }
        set {
            guard storedAppLanguage != newValue.rawValue else { return }
            objectWillChange.send()
            storedAppLanguage = newValue.rawValue
        }
    }
    
    var appLocale: Locale {
        switch appLanguage {
        case .system:
            return Locale.autoupdatingCurrent
        case .english:
            return Locale(identifier: "en")
        case .japanese:
            return Locale(identifier: "ja")
        }
    }
    
    var appLanguageIdentifier: String? {
        appLanguage.localeIdentifier
    }

    func localizedString(_ key: String, comment: String = "") -> String {
        if let identifier = appLanguageIdentifier,
           let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    }

    func localizedFormat(_ key: String, comment: String = "", _ args: CVarArg...) -> String {
        let format = localizedString(key, comment: comment)
        return String(format: format, locale: appLocale, arguments: args)
    }

    private init() {
        if storedFilterCategoryNone {
            storedFilterCategoryNone = false
        }
        if UserDefaults.standard.object(forKey: "historySelectPaste") == nil {
            historySelectPaste = false
        }
    }

    // Settings Keys for consistency
    struct Keys {
        static let windowHeight = "windowHeight"
        static let windowWidth = "windowWidth" 
        static let windowAnimation = "windowAnimation"
        static let editorSectionHeight = "editorSectionHeight"
        static let historySectionHeight = "historySectionHeight"
        static let desktopNoteDefaultDisplayMode = "desktopNoteDefaultDisplayMode"
        static let desktopNoteDisplayID = "desktopNoteDisplayID"
        static let desktopNoteOnRepeatedCopy = "desktopNoteOnRepeatedCopy"
        static let editorPosition = "editorPosition"
        static let maxHistoryItems = "maxHistoryItems"
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
        static let appLanguage = "appLanguage"
        static let historySelectPaste = "historySelectPaste"
    }
    
    enum LanguageOption: String, CaseIterable, Identifiable {
        case system
        case english
        case japanese
        
        var id: String { rawValue }
        
        var displayName: LocalizedStringKey {
            switch self {
            case .system:
                return LocalizedStringKey("System Default")
            case .english:
                return LocalizedStringKey("English")
            case .japanese:
                return LocalizedStringKey("Japanese")
            }
        }
        
        var localeIdentifier: String? {
            switch self {
            case .system:
                return nil
            case .english:
                return "en"
            case .japanese:
                return "ja"
            }
        }
    }
}
