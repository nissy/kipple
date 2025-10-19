//
//  MainViewControlSection.swift
//  Kipple
//
//  Created by Kipple on 2025/06/30.
//

import SwiftUI

struct MainViewControlSection: View {
    let onCopy: () -> Void
    let onClear: () -> Void
    let onTogglePasteMode: () -> Void
    let pasteMode: MainViewModel.PasteMode
    let queueEnabled: Bool
    @ObservedObject private var appSettings = AppSettings.shared
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTogglePasteMode) {
                Label(modeButtonTitle(), systemImage: modeButtonIcon())
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    )
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(!queueEnabled)
            
            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Label("Copy", systemImage: "doc.on.doc")
                    
                    // ショートカットキー表示（設定なし=非表示）
                    let shortcut = getShortcutKeyDisplay()
                    if !shortcut.isEmpty {
                        Text(shortcut)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .buttonStyle(ProminentButtonStyle())
            .fixedSize()
            
            Spacer()
            
            Button(action: onClear) {
                HStack(spacing: 4) {
                    Label("Clear", systemImage: "trash")
                    
                    // ショートカットキー表示（設定なし=非表示）
                    let shortcut = getClearShortcutKeyDisplay()
                    if !shortcut.isEmpty {
                        Text(shortcut)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .buttonStyle(DestructiveButtonStyle())
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func getShortcutKeyDisplay() -> String {
        // 設定なし（keyまたは修飾が0）の場合は非表示
        if appSettings.editorCopyHotkeyKeyCode == 0 || appSettings.editorCopyHotkeyModifierFlags == 0 {
            return ""
        }

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(appSettings.editorCopyHotkeyModifierFlags))
        var parts: [String] = []
        
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        
        // キーコードをキー文字に変換
        if let keyChar = keyCodeToString(UInt16(appSettings.editorCopyHotkeyKeyCode)) {
            parts.append(keyChar)
        }
        
        return parts.joined()
    }

    private func modeButtonTitle() -> String {
        switch pasteMode {
        case .clipboard:
            return "Clipboard"
        case .queueOnce:
            return "Paste Queue"
        case .queueToggle:
            return "Queue Toggle"
        }
    }

    private func modeButtonIcon() -> String {
        switch pasteMode {
        case .clipboard:
            return "doc.on.clipboard"
        case .queueOnce:
            return "list.number"
        case .queueToggle:
            return "repeat"
        }
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        // 一般的なキーコードのマッピング
        let keyMap: [UInt16: String] = [
            // 0 は未設定を意味するため文字を返さない
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
    
    private func getClearShortcutKeyDisplay() -> String {
        // 設定なし（keyまたは修飾が0）の場合は非表示
        if appSettings.editorClearHotkeyKeyCode == 0 || appSettings.editorClearHotkeyModifierFlags == 0 {
            return ""
        }

        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(appSettings.editorClearHotkeyModifierFlags))
        var parts: [String] = []
        
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        
        // キーコードをキー文字に変換
        if let keyChar = keyCodeToString(UInt16(appSettings.editorClearHotkeyKeyCode)) {
            parts.append(keyChar)
        }
        
        return parts.joined()
    }
}
