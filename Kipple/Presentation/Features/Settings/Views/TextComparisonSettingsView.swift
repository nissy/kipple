import AppKit
import SwiftUI

struct TextComparisonSettingsView: View {
    @ObservedObject private var hotkey = TextComparisonHotkey.shared
    @State private var keyCode: UInt16 = 0
    @State private var modifiers: NSEvent.ModifierFlags = []
    @State private var error: TextComparisonHotkey.ConfigurationError?

    var body: some View {
        SettingsGroup("Compare Text") {
            SettingsRow(
                label: "Global Hotkey",
                description: "Compare the clipboard text with text selected in the frontmost app."
            ) {
                HotkeyRecorderField(keyCode: $keyCode, modifierFlags: $modifiers) { keyCode, modifiers in
                    error = hotkey.apply(keyCode: keyCode, modifiers: modifiers)
                    loadShortcut()
                }
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear(perform: loadShortcut)
    }

    private var message: LocalizedStringKey? {
        switch error {
        case .modifierRequired:
            "Include Command, Control, or Option in the shortcut."
        case .unavailable:
            "This shortcut is already in use. Your previous shortcut has been kept."
        case nil:
            hotkey.registrationFailed ? "The comparison shortcut is unavailable. Choose a different shortcut." : nil
        }
    }

    private func loadShortcut() {
        keyCode = hotkey.shortcut.keyCode
        modifiers = hotkey.shortcut.modifiers
    }
}
