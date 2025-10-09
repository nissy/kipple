//
//  ScreenRecordingPermissionOpener.swift
//  Kipple
//
//  Created by Kipple on 2025/10/09.
//

import AppKit

enum ScreenRecordingPermissionOpener {
    @MainActor
    static func openSystemSettings() {
        let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let candidates: [String]

        switch majorVersion {
        case 15:
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording&pane=Privacy_ScreenRecording",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        case 26:
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording",
                "x-apple.systempreferences:com.apple.Preferences?privacy=ScreenCapture",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        default:
            candidates = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording",
                "x-apple.systempreferences:com.apple.preference.security?Privacy"
            ]
        }

        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }

        let process = Process()
        process.launchPath = "/usr/bin/open"
        process.arguments = ["-b", "com.apple.systempreferences", "/System/Library/PreferencePanes/Security.prefPane"]
        try? process.run()

        let screenRecordingAnchor = majorVersion >= 26 ? "Privacy_ScreenCapture" : "Privacy_ScreenRecording"

        let appleScriptSource = """
        tell application "System Settings"
            activate
            reveal pane id "com.apple.preference.security"
            delay 0.2
            try
                reveal anchor "\(screenRecordingAnchor)" of pane id "com.apple.preference.security"
            end try
        end tell
        """
        NSAppleScript(source: appleScriptSource)?.executeAndReturnError(nil)
    }
}
