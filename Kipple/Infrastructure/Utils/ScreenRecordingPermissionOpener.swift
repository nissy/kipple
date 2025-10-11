//
//  ScreenRecordingPermissionOpener.swift
//  Kipple
//
//  Created by Kipple on 2025/10/09.
//

import AppKit

enum ScreenRecordingPermissionOpener {
    @MainActor
    struct Dependencies {
        var openURL: (URL) -> Bool
        var launchProcess: (_ launchPath: String, _ arguments: [String]) -> Void
        var runAppleScript: (_ source: String) -> Void

        static let live = Dependencies(
            openURL: { NSWorkspace.shared.open($0) },
            launchProcess: { path, args in
                let process = Process()
                process.launchPath = path
                process.arguments = args
                try? process.run()
            },
            runAppleScript: { source in
                NSAppleScript(source: source)?.executeAndReturnError(nil)
            }
        )
    }

    @MainActor
    static func openSystemSettings(
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        dependencies: Dependencies = .live
    ) {
        let majorVersion = osVersion.majorVersion
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
            if let url = URL(string: candidate), dependencies.openURL(url) {
                return
            }
        }

        dependencies.launchProcess(
            "/usr/bin/open",
            ["-b", "com.apple.systempreferences", "/System/Library/PreferencePanes/Security.prefPane"]
        )

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
        dependencies.runAppleScript(appleScriptSource)
    }
}
