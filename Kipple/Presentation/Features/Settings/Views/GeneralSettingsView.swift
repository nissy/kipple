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
        VStack(spacing: 14) {
            // Startup
            VStack(alignment: .leading, spacing: 10) {
                Label("Startup", systemImage: "power")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Toggle("Launch at login", isOn: $autoLaunchAtLogin)
                    .toggleStyle(SwitchToggleStyle())
                    .onChange(of: autoLaunchAtLogin) { newValue in
                        LaunchAtLogin.shared.isEnabled = newValue
                    }
                
                Text("Automatically start Kipple when you log in")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
            
            Divider()
            
            // Global Hotkey
            VStack(alignment: .leading, spacing: 10) {
                Label("Global Hotkey", systemImage: "keyboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Toggle("Enable global hotkey", isOn: $enableHotkey)
                    .toggleStyle(SwitchToggleStyle())
                    .onChange(of: enableHotkey) { newValue in
                        NotificationCenter.default.post(
                            name: NSNotification.Name("HotkeySettingsChanged"),
                            object: nil,
                            userInfo: ["enabled": newValue]
                        )
                    }
                
                HStack {
                    Text("Show/hide window:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    HotkeyRecorderField(
                        keyCode: $tempKeyCode,
                        modifierFlags: $tempModifierFlags
                    )
                    .disabled(!enableHotkey)
                    .opacity(enableHotkey ? 1.0 : 0.5)
                    .onChange(of: tempKeyCode) { _ in updateHotkey() }
                    .onChange(of: tempModifierFlags) { _ in updateHotkey() }
                }
                .padding(.leading, 20)
            }
            
            Divider()
            
            // Editor Insert
            VStack(alignment: .leading, spacing: 10) {
                Label("Editor Insert", systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Toggle("Enable quick insert with modifier key", isOn: $enableEditorInsert)
                    .toggleStyle(SwitchToggleStyle())
                
                HStack {
                    Text("Hold")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    ModifierKeyPicker(selection: $editorInsertModifiers)
                        .frame(width: 100)
                        .disabled(!enableEditorInsert)
                        .opacity(enableEditorInsert ? 1.0 : 0.5)
                    
                    Text("while clicking to insert")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 20)
                
                Text("Quickly insert selected text into the editor")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }
            
            Divider()
            
            // Window Animation
            VStack(alignment: .leading, spacing: 10) {
                Label("Window Animation", systemImage: "wand.and.rays")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Picker("Animation style:", selection: $windowAnimation) {
                    Text("None").tag("none")
                    Text("Fade").tag("fade")
                    Text("Slide").tag("slide")
                    Text("Pop").tag("pop")
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 250)
                
                Text("Choose how the window appears and disappears")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
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
