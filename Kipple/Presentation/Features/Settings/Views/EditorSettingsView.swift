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
        VStack(spacing: 14) {
            // Font Settings for Editor
            SimpleFontSettingsView()
            
            Divider()
            
            // Editor Copy Hotkey Settings - Matching Editor Insert UI style
            VStack(alignment: .leading, spacing: 10) {
                Label("Editor Copy Hotkey", systemImage: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Toggle("Enable editor copy hotkey", isOn: $appSettings.enableEditorCopyHotkey)
                    .toggleStyle(SwitchToggleStyle())
                    .onChange(of: appSettings.enableEditorCopyHotkey) { newValue in
                        NotificationCenter.default.post(
                            name: NSNotification.Name("EditorCopyHotkeySettingsChanged"),
                            object: nil,
                            userInfo: ["enabled": newValue]
                        )
                    }
                
                HStack {
                    Text("Copy editor content:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    HotkeyRecorderField(
                        keyCode: $tempCopyKeyCode,
                        modifierFlags: $tempCopyModifierFlags
                    )
                    .disabled(!appSettings.enableEditorCopyHotkey)
                    .opacity(appSettings.enableEditorCopyHotkey ? 1.0 : 0.5)
                    .onChange(of: tempCopyKeyCode) { _ in updateCopyHotkey() }
                    .onChange(of: tempCopyModifierFlags) { _ in updateCopyHotkey() }
                }
                .padding(.leading, 20)
                
                Text("Quickly copy editor content to clipboard")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
            
            Divider()
            
            // Editor Clear Hotkey Settings - Matching Editor Insert UI style
            VStack(alignment: .leading, spacing: 10) {
                Label("Editor Clear Hotkey", systemImage: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Toggle("Enable editor clear hotkey", isOn: $appSettings.enableEditorClearHotkey)
                    .toggleStyle(SwitchToggleStyle())
                    .onChange(of: appSettings.enableEditorClearHotkey) { newValue in
                        NotificationCenter.default.post(
                            name: NSNotification.Name("EditorClearHotkeySettingsChanged"),
                            object: nil,
                            userInfo: ["enabled": newValue]
                        )
                    }
                
                HStack {
                    Text("Clear editor content:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    HotkeyRecorderField(
                        keyCode: $tempClearKeyCode,
                        modifierFlags: $tempClearModifierFlags
                    )
                    .disabled(!appSettings.enableEditorClearHotkey)
                    .opacity(appSettings.enableEditorClearHotkey ? 1.0 : 0.5)
                    .onChange(of: tempClearKeyCode) { _ in updateClearHotkey() }
                    .onChange(of: tempClearModifierFlags) { _ in updateClearHotkey() }
                }
                .padding(.leading, 20)
                
                Text("Quickly clear editor content")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
            
            Spacer()
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
