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
            Button(noneLabel) {
                selection = 0
            }
            Button(commandLabel) {
                selection = Int(NSEvent.ModifierFlags.command.rawValue)
            }
            Button(optionLabel) {
                selection = Int(NSEvent.ModifierFlags.option.rawValue)
            }
            Button(shiftLabel) {
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
        if modifierFlags.contains(.command) { parts.append(commandLabel) }
        if modifierFlags.contains(.option) { parts.append(optionLabel) }
        if modifierFlags.contains(.shift) { parts.append(shiftLabel) }
        if parts.isEmpty { return noneLabel }
        return parts.joined(separator: " + ")
    }

    private var noneLabel: String { String(localized: "None") }
    private var commandLabel: String { String(localized: "⌘ Command") }
    private var optionLabel: String { String(localized: "⌥ Option") }
    private var shiftLabel: String { String(localized: "⇧ Shift") }
}
