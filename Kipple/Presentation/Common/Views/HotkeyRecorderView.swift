//
//  HotkeyRecorderView.swift
//  Kipple
//
//  Created by Kipple on 2025/06/29.
//

import SwiftUI
import Carbon

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifierFlags: Int
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = "Click to record hotkey"
        textField.alignment = .center
        textField.isEditable = false
        textField.isSelectable = false
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        
        updateTextField(textField)
        
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        updateTextField(nsView)
    }
    
    private func updateTextField(_ textField: NSTextField) {
        let modifierFlagsValue = NSEvent.ModifierFlags(rawValue: UInt(modifierFlags))
        
        if keyCode == 0 && modifierFlagsValue.isEmpty {
            textField.stringValue = ""
            textField.placeholderString = "Click to record hotkey"
            return
        }
        
        var keys: [String] = []
        
        if modifierFlagsValue.contains(.control) { keys.append("⌃") }
        if modifierFlagsValue.contains(.option) { keys.append("⌥") }
        if modifierFlagsValue.contains(.shift) { keys.append("⇧") }
        if modifierFlagsValue.contains(.command) { keys.append("⌘") }
        
        if let keyString = keyCodeToString(UInt16(keyCode)) {
            keys.append(keyString)
        }
        
        textField.stringValue = keys.joined()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: HotkeyRecorderView
        
        init(_ parent: HotkeyRecorderView) {
            self.parent = parent
            super.init()
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            return true // Prevent default behavior
        }
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String? {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`",
            51: "⌫", 53: "⎋", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keyMap[keyCode]
    }
}

struct HotkeyRecorderField: View {
    @Binding var keyCode: UInt16
    @Binding var modifierFlags: NSEvent.ModifierFlags
    @State private var isRecording = false
    
    var body: some View {
        HStack(spacing: 8) {
            HotkeyRecorderView(
                keyCode: Binding<Int>(
                    get: { Int(keyCode) },
                    set: { keyCode = UInt16($0) }
                ),
                modifierFlags: Binding<Int>(
                    get: { Int(modifierFlags.rawValue) },
                    set: { modifierFlags = NSEvent.ModifierFlags(rawValue: UInt($0)) }
                )
            )
                .frame(width: 100, height: 28)
                .background(isRecording ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isRecording ? Color.blue : Color(NSColor.separatorColor), lineWidth: 1)
                )
                .onTapGesture {
                    isRecording = true
                }
            
            Button("Clear") {
                keyCode = 0
                modifierFlags = .init()
                isRecording = false
            }
            .buttonStyle(.borderless)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
        }
        .background(KeyEventHandler(isRecording: $isRecording, keyCode: $keyCode, modifierFlags: $modifierFlags))
    }
}

struct KeyEventHandler: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: UInt16
    @Binding var modifierFlags: NSEvent.ModifierFlags
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureView()
        view.onKeyDown = { event in
            if isRecording {
                keyCode = event.keyCode
                modifierFlags = event.modifierFlags.intersection([.command, .control, .option, .shift])
                isRecording = false
                return true
            }
            return false
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? KeyCaptureView {
            view.isActive = isRecording
        }
    }
}

class KeyCaptureView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    var isActive = false {
        didSet {
            if isActive {
                window?.makeFirstResponder(self)
            }
        }
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) ?? false {
            return
        }
        super.keyDown(with: event)
    }
}
