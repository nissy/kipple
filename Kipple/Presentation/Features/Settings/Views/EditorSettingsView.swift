//
//  EditorSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI
import AppKit

struct EditorSettingsView: View {
    @ObservedObject private var appSettings = AppSettings.shared
    @AppStorage("editorInsertModifiers") private var editorInsertModifiers = Int(NSEvent.ModifierFlags.control.rawValue)
    @State private var tempCopyKeyCode: UInt16 = 6  // Z key
    @State private var tempCopyModifierFlags: NSEvent.ModifierFlags = [.command, .shift]
    @State private var tempClearKeyCode: UInt16 = 7  // X key
    @State private var tempClearModifierFlags: NSEvent.ModifierFlags = [.command, .shift]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsLayoutMetrics.sectionSpacing) {
                // Font Settings
                SimpleFontSettingsView()
                // Editor Position
                SettingsGroup("Editor Position") {
                    SettingsRow(label: "Position") {
                        Picker("", selection: $appSettings.editorPosition) {
                            Text("Top").tag("top")
                            Text("Bottom").tag("bottom")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 150)
                    }
                }
                // Editor Copy Hotkey
                SettingsGroup("Editor Copy") {
                    SettingsRow(label: "Hotkey") {
                        HotkeyRecorderField(
                            keyCode: $tempCopyKeyCode,
                            modifierFlags: $tempCopyModifierFlags
                        )
                        .onChange(of: tempCopyKeyCode) { _ in updateCopyHotkey() }
                        .onChange(of: tempCopyModifierFlags) { _ in updateCopyHotkey() }
                    }
                }
                // Editor Clear Hotkey
                SettingsGroup("Editor Clear") {
                    SettingsRow(label: "Hotkey") {
                        HotkeyRecorderField(
                            keyCode: $tempClearKeyCode,
                            modifierFlags: $tempClearModifierFlags
                        )
                        .onChange(of: tempClearKeyCode) { _ in updateClearHotkey() }
                        .onChange(of: tempClearModifierFlags) { _ in updateClearHotkey() }
                    }
                }

                // Editor Insert
                SettingsGroup("Editor History Insert") {
                    SettingsRow(
                        label: "Modified click",
                        description: "Use modifier + click"
                    ) {
                        ModifierKeyPicker(selection: $editorInsertModifiers)
                            .frame(width: 120)
                    }
                }
            }
            .padding(.horizontal, SettingsLayoutMetrics.scrollHorizontalPadding)
            .padding(.vertical, SettingsLayoutMetrics.scrollVerticalPadding)
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
