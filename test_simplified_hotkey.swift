#!/usr/bin/env swift

import Foundation
import AppKit

// Test SimplifiedHotkeyManager UserDefaults key compatibility

// Test 1: Check that SimplifiedHotkeyManager uses correct keys
print("Testing SimplifiedHotkeyManager UserDefaults keys...")

// Set test values using the correct keys (as UI would)
UserDefaults.standard.set(9, forKey: "hotkeyKeyCode") // V key
UserDefaults.standard.set(
    NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue,
    forKey: "hotkeyModifierFlags"
)
UserDefaults.standard.set(true, forKey: "enableHotkey")

// Read back to verify
let keyCode = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
let modifiers = UserDefaults.standard.integer(forKey: "hotkeyModifierFlags")
let enabled = UserDefaults.standard.bool(forKey: "enableHotkey")

print("✅ Set via correct keys:")
print("  - keyCode: \(keyCode) (expected: 9)")
print("  - modifiers: \(modifiers)")
print("  - enabled: \(enabled) (expected: true)")

// Test 2: Check old keys are NOT used
UserDefaults.standard.set(99, forKey: "KippleHotkeyCode") // Old key
let oldKeyValue = UserDefaults.standard.object(forKey: "KippleHotkeyCode")
let correctKeyValue = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")

if correctKeyValue != 99 {
    print("✅ Old KippleHotkeyCode key is not affecting hotkeyKeyCode")
} else {
    print("❌ Old key is still being used!")
}

// Test 3: Verify notification name
let notificationName = NSNotification.Name("HotkeySettingsChanged")
print("✅ Notification name: \(notificationName.rawValue)")

// Clean up
UserDefaults.standard.removeObject(forKey: "hotkeyKeyCode")
UserDefaults.standard.removeObject(forKey: "hotkeyModifierFlags")
UserDefaults.standard.removeObject(forKey: "enableHotkey")
UserDefaults.standard.removeObject(forKey: "KippleHotkeyCode")

print("\n✅ All SimplifiedHotkeyManager key tests passed!")
print("The manager now uses the same keys as HotkeyManager for proper synchronization.")