//
//  MainViewControlSection.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI

struct MainViewControlSection: View {
    let onCopy: () -> Void
    let onSplitCopy: () -> Void
    let onTrim: () -> Void
    @ObservedObject private var appSettings = AppSettings.shared

    private let buttonHeight: CGFloat = 30
    private let horizontalPadding: CGFloat = 10

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                copySplitButton
                trimButton
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private var trimButton: some View {
        Button(action: onTrim) {
            buttonLabel(
                systemImage: "scissors",
                shortcut: "",
                accessibilityLabel: "Trim"
            )
            .padding(.horizontal, horizontalPadding)
            .frame(height: buttonHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(.white)
        .background(trimButtonColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
    }

    private var copySplitButton: some View {
        HStack(spacing: 0) {
            Button(action: onCopy) {
                buttonLabel(
                    systemImage: "doc.on.doc",
                    shortcut: getShortcutKeyDisplay(),
                    accessibilityLabel: "Copy"
                )
                .padding(.horizontal, horizontalPadding)
                .frame(height: buttonHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            Rectangle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 1, height: buttonHeight - 12)
                .padding(.vertical, 6)
                .allowsHitTesting(false)

            Menu {
                Button(action: onSplitCopy) {
                    Label {
                        Text("editor.splitCopy.menu")
                    } icon: {
                        Image(systemName: "text.badge.plus")
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 32, height: buttonHeight)
                    .contentShape(Rectangle())
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .menuIndicator(.hidden)
            .buttonStyle(PlainButtonStyle())
        }
        .foregroundColor(.white)
        .background(splitButtonBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
        .contentShape(Rectangle())
    }

    private func buttonLabel(systemImage: String, shortcut: String, accessibilityLabel: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .regular))

            if !shortcut.isEmpty {
                shortcutBadge(shortcut)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func shortcutBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.25))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var splitButtonBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color.accentColor,
                Color.accentColor.opacity(0.85)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var trimButtonColor: Color {
        Color.green
    }

    private func getShortcutKeyDisplay() -> String {
        if appSettings.editorCopyHotkeyKeyCode == 0 || appSettings.editorCopyHotkeyModifierFlags == 0 {
            return ""
        }

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(appSettings.editorCopyHotkeyModifierFlags))
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        if let keyChar = keyCodeToString(UInt16(appSettings.editorCopyHotkeyKeyCode)) {
            parts.append(keyChar)
        }

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        let keyMap: [UInt16: String] = [
            1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 50: "`"
        ]
        if keyCode == 0 { return nil }
        return keyMap[keyCode]
    }
}
