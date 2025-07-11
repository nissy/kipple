//
//  GeneralSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("autoLaunchAtLogin") private var autoLaunchAtLogin = false
    @AppStorage("enableHotkey") private var enableHotkey = false
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: Int = 9 // V key
    @AppStorage("hotkeyModifierFlags") private var hotkeyModifierFlags = 
        Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.option.rawValue) // CMD + Option
    @AppStorage("enableEditorInsert") private var enableEditorInsert = true
    @AppStorage("editorInsertModifiers") private var editorInsertModifiers = Int(NSEvent.ModifierFlags.command.rawValue)
    @AppStorage("windowAnimation") private var windowAnimation: String = "fade"
    
    @State private var tempKeyCode: UInt16 = 9
    @State private var tempModifierFlags: NSEvent.ModifierFlags = [.command, .option]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Startup
                SettingsGroup("Startup") {
                    SettingsRow(
                        label: "Launch at login",
                        description: "Automatically start Kipple when you log in",
                        isOn: $autoLaunchAtLogin
                    )
                    .onChange(of: autoLaunchAtLogin) { newValue in
                        LaunchAtLogin.shared.isEnabled = newValue
                    }
                }
                
                Divider()
                
                // Global Hotkey
                SettingsGroup("Global Hotkey") {
                    SettingsRow(
                        label: "Enable global hotkey",
                        isOn: $enableHotkey
                    )
                    .onChange(of: enableHotkey) { newValue in
                        NotificationCenter.default.post(
                            name: NSNotification.Name("HotkeySettingsChanged"),
                            object: nil,
                            userInfo: ["enabled": newValue]
                        )
                    }
                    
                    SettingsRow(label: "Show/hide window") {
                        HotkeyRecorderField(
                            keyCode: $tempKeyCode,
                            modifierFlags: $tempModifierFlags
                        )
                        .disabled(!enableHotkey)
                        .opacity(enableHotkey ? 1.0 : 0.5)
                        .onChange(of: tempKeyCode) { _ in updateHotkey() }
                        .onChange(of: tempModifierFlags) { _ in updateHotkey() }
                    }
                }
                
                Divider()
                
                // Editor Insert
                SettingsGroup("Editor Insert") {
                    SettingsRow(
                        label: "Enable quick insert with modifier key",
                        description: "Quickly insert selected text into the editor",
                        isOn: $enableEditorInsert
                    )
                    
                    SettingsRow(label: "Modifier key") {
                        HStack {
                            ModifierKeyPicker(selection: $editorInsertModifiers)
                                .frame(width: 120)
                                .disabled(!enableEditorInsert)
                                .opacity(enableEditorInsert ? 1.0 : 0.5)
                            
                            Text("+ click to insert")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Divider()
                
                // Window Animation
                SettingsGroup("Window Animation") {
                    SettingsRow(
                        label: "Animation style",
                        description: "Choose how the window appears and disappears"
                    ) {
                        Picker("", selection: $windowAnimation) {
                            Text("None").tag("none")
                            Text("Fade").tag("fade")
                            Text("Slide").tag("slide")
                            Text("Scale").tag("scale")
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .frame(width: 200)
                        .labelsHidden()
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .onAppear {
            tempKeyCode = UInt16(hotkeyKeyCode)
            tempModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifierFlags))
        }
    }
    
    private func updateHotkey() {
        hotkeyKeyCode = Int(tempKeyCode)
        hotkeyModifierFlags = Int(tempModifierFlags.rawValue)
        
        NotificationCenter.default.post(
            name: NSNotification.Name("HotkeySettingsChanged"),
            object: nil,
            userInfo: [
                "keyCode": hotkeyKeyCode,
                "modifierFlags": hotkeyModifierFlags
            ]
        )
    }
}

// MARK: - ModifierKeyPicker
struct ModifierKeyPicker: View {
    @Binding var selection: Int
    
    private var modifierFlags: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: UInt(selection)) }
        set { selection = Int(newValue.rawValue) }
    }
    
    var body: some View {
        Menu {
            Button("⌘ Command") {
                selection = Int(NSEvent.ModifierFlags.command.rawValue)
            }
            Button("⌥ Option") {
                selection = Int(NSEvent.ModifierFlags.option.rawValue)
            }
            Button("⌃ Control") {
                selection = Int(NSEvent.ModifierFlags.control.rawValue)
            }
            Button("⇧ Shift") {
                selection = Int(NSEvent.ModifierFlags.shift.rawValue)
            }
        } label: {
            HStack {
                Text(modifierKeyDisplayName)
                    .font(.system(size: 12))
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
        }
    }
    
    private var modifierKeyDisplayName: String {
        switch modifierFlags {
        case .command: return "⌘ Command"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .shift: return "⇧ Shift"
        default: return "⌘ Command"
        }
    }
}
