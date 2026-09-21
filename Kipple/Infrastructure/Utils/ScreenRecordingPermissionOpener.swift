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
        var showManualInstructions: () -> Void

        static let live = Dependencies(
            openURL: { NSWorkspace.shared.open($0) },
            showManualInstructions: {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("Open System Settings", comment: "")
                alert.informativeText = NSLocalizedString(
                    "In System Settings → Privacy & Security → Screen & System Audio Recording, enable “Kipple”.",
                    comment: ""
                )
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.runModal()
            }
        )
    }

    @MainActor
    static func openSystemSettings(
        dependencies: Dependencies = .live
    ) {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenRecording",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]

        for candidate in candidates {
            if let url = URL(string: candidate), dependencies.openURL(url) {
                return
            }
        }

        dependencies.showManualInstructions()
    }
}
