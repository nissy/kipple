//
//  ModifierKeyPicker.swift
//  Kipple
//
//  Created by Kipple on 2025/10/13.
//

import SwiftUI
import AppKit

struct ModifierKeyPicker: View {
    @Binding var selection: Int

    private var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(selection))
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
        var parts: [String] = []
        if modifierFlags.contains(.command) { parts.append("⌘ Command") }
        if modifierFlags.contains(.option) { parts.append("⌥ Option") }
        if modifierFlags.contains(.control) { parts.append("⌃ Control") }
        if modifierFlags.contains(.shift) { parts.append("⇧ Shift") }
        if parts.isEmpty { return "None" }
        return parts.joined(separator: " + ")
    }
}
