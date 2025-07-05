//
//  EditorSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI

struct EditorSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var tempCopyKeyCode: UInt16 = 6  // Z key
    @State private var tempCopyModifierFlags: NSEvent.ModifierFlags = [.command, .shift]
    @State private var tempClearKeyCode: UInt16 = 7  // X key
    @State private var tempClearModifierFlags: NSEvent.ModifierFlags = [.command, .shift]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Font Settings
                SimpleFontSettingsView()
                
                Divider()
                
                // Editor Copy Hotkey
                SettingsGroup("Editor Copy Hotkey") {
                    SettingsRow(
                        label: "Enable editor copy hotkey",
                        description: "Quickly copy editor content to clipboard",
                        isOn: $appSettings.enableEditorCopyHotkey
                    )
                    .onChange(of: appSettings.enableEditorCopyHotkey) { newValue in
                        NotificationCenter.default.post(
                            name: NSNotification.Name("EditorCopyHotkeySettingsChanged"),
                            object: nil,
                            userInfo: ["enabled": newValue]
                        )
                    }
                    
                    SettingsRow(label: "Copy editor content") {
                        HotkeyRecorderField(
                            keyCode: $tempCopyKeyCode,
                            modifierFlags: $tempCopyModifierFlags
                        )
                        .disabled(!appSettings.enableEditorCopyHotkey)
                        .opacity(appSettings.enableEditorCopyHotkey ? 1.0 : 0.5)
                        .onChange(of: tempCopyKeyCode) { _ in updateCopyHotkey() }
                        .onChange(of: tempCopyModifierFlags) { _ in updateCopyHotkey() }
                    }
                }
                
                Divider()
                
                // Editor Clear Hotkey
                SettingsGroup("Editor Clear Hotkey") {
                    SettingsRow(
                        label: "Enable editor clear hotkey",
                        description: "Quickly clear editor content",
                        isOn: $appSettings.enableEditorClearHotkey
                    )
                    .onChange(of: appSettings.enableEditorClearHotkey) { newValue in
                        NotificationCenter.default.post(
                            name: NSNotification.Name("EditorClearHotkeySettingsChanged"),
                            object: nil,
                            userInfo: ["enabled": newValue]
                        )
                    }
                    
                    SettingsRow(label: "Clear editor content") {
                        HotkeyRecorderField(
                            keyCode: $tempClearKeyCode,
                            modifierFlags: $tempClearModifierFlags
                        )
                        .disabled(!appSettings.enableEditorClearHotkey)
                        .opacity(appSettings.enableEditorClearHotkey ? 1.0 : 0.5)
                        .onChange(of: tempClearKeyCode) { _ in updateClearHotkey() }
                        .onChange(of: tempClearModifierFlags) { _ in updateClearHotkey() }
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .onAppear {
            tempCopyKeyCode = UInt16(appSettings.editorCopyHotkeyKeyCode)
            tempCopyModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(appSettings.editorCopyHotkeyModifierFlags))
            tempClearKeyCode = UInt16(appSettings.editorClearHotkeyKeyCode)
            tempClearModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(appSettings.editorClearHotkeyModifierFlags))
        }
    }
    
    private func updateCopyHotkey() {
        appSettings.editorCopyHotkeyKeyCode = Int(tempCopyKeyCode)
        appSettings.editorCopyHotkeyModifierFlags = Int(tempCopyModifierFlags.rawValue)
        
        NotificationCenter.default.post(
            name: NSNotification.Name("EditorCopyHotkeySettingsChanged"),
            object: nil,
            userInfo: [
                "keyCode": appSettings.editorCopyHotkeyKeyCode,
                "modifierFlags": appSettings.editorCopyHotkeyModifierFlags
            ]
        )
    }
    
    private func updateClearHotkey() {
        appSettings.editorClearHotkeyKeyCode = Int(tempClearKeyCode)
        appSettings.editorClearHotkeyModifierFlags = Int(tempClearModifierFlags.rawValue)
        
        NotificationCenter.default.post(
            name: NSNotification.Name("EditorClearHotkeySettingsChanged"),
            object: nil,
            userInfo: [
                "keyCode": appSettings.editorClearHotkeyKeyCode,
                "modifierFlags": appSettings.editorClearHotkeyModifierFlags
            ]
        )
    }
}
