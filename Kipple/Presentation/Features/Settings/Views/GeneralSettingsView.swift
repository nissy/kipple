//
//  GeneralSettingsView.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage("autoLaunchAtLogin") private var autoLaunchAtLogin = false
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: Int = 0
    @AppStorage("hotkeyModifierFlags") private var hotkeyModifierFlags: Int = 0
    @AppStorage("editorInsertModifiers") private var editorInsertModifiers = Int(NSEvent.ModifierFlags.control.rawValue)
    @AppStorage("windowAnimation") private var windowAnimation: String = "none"
    @AppStorage("actionClickModifiers") private var actionClickModifiers = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @State private var tempKeyCode: UInt16 = 0
    @State private var tempModifierFlags: NSEvent.ModifierFlags = []
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Startup
                SettingsGroup("Startup", includeTopDivider: false) {
                    SettingsRow(
                        label: "Launch at login",
                        isOn: $autoLaunchAtLogin
                    )
                    .onChange(of: autoLaunchAtLogin) { newValue in
                        LaunchAtLogin.shared.isEnabled = newValue
                    }
                }
                
                // Global Hotkey
                SettingsGroup("Global Hotkey") {
                    SettingsRow(label: "Show/hide window") {
                        HotkeyRecorderField(
                            keyCode: $tempKeyCode,
                            modifierFlags: $tempModifierFlags
                        )
                        .onChange(of: tempKeyCode) { _ in updateHotkey() }
                        .onChange(of: tempModifierFlags) { _ in updateHotkey() }
                    }
                }
                
                // Editor Insert
                SettingsGroup("Editor Insert") {
                    SettingsRow(label: "Modifier key") {
                        HStack {
                            ModifierKeyPicker(selection: $editorInsertModifiers)
                                .frame(width: 120)
                            Text("+ click to insert")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Action Click
                SettingsGroup("Action Click") {
                    SettingsRow(label: "Modifier key") {
                        HStack {
                            ModifierKeyPicker(selection: $actionClickModifiers)
                                .frame(width: 120)
                            Text("+ click to open URI")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Window Animation
                SettingsGroup("Window Animation") {
                    SettingsRow(
                        label: "Animation style"
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
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .onAppear {
            tempKeyCode = UInt16(hotkeyKeyCode)
            tempModifierFlags = NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifierFlags))
        }
    }
    
    private func updateHotkey() {
        hotkeyKeyCode = Int(tempKeyCode)
        hotkeyModifierFlags = Int(tempModifierFlags.rawValue)
        // Clear(= no key) の場合は無効と見なす
        let shouldEnable = (hotkeyKeyCode != 0) && (hotkeyModifierFlags != 0)
        UserDefaults.standard.set(shouldEnable, forKey: "enableHotkey")
        
        NotificationCenter.default.post(
            name: NSNotification.Name("HotkeySettingsChanged"),
            object: nil,
            userInfo: [
                "keyCode": hotkeyKeyCode,
                "modifierFlags": hotkeyModifierFlags,
                "enabled": shouldEnable
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
            Button("None") {
                selection = 0
            }
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
        if modifierFlags.isEmpty { return "None" }
        switch modifierFlags {
        case .command: return "⌘ Command"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .shift: return "⇧ Shift"
        default: return "⌘ Command"
        }
    }
}
