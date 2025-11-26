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

    private let allowedModifiers: NSEvent.ModifierFlags = [.command, .option]

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
        .onAppear(perform: normalizeSelection)
        .onChange(of: selection) { _ in
            normalizeSelection()
        }
    }

    private var modifierKeyDisplayName: String {
        let flags = currentSelection
        var parts: [String] = []
        if flags.contains(.command) { parts.append(commandLabel) }
        if flags.contains(.option) { parts.append(optionLabel) }
        return parts.isEmpty ? noneLabel : parts.joined(separator: " + ")
    }

    private var currentSelection: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(selection)).intersection(allowedModifiers)
    }

    private func normalizeSelection() {
        let normalized = currentSelection
        if normalized.rawValue != UInt(selection) {
            selection = Int(normalized.rawValue)
        }
    }

    private var noneLabel: String { String(localized: "None") }
    private var commandLabel: String { String(localized: "⌘ Command") }
    private var optionLabel: String { String(localized: "⌥ Option") }
}
