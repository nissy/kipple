import AppKit
import ApplicationServices

// MARK: - Hotkey Handling

extension MenuBarApp {
    func setupPlainTextPasteHotkey() {
        guard let adapter = clipboardService as? ModernClipboardServiceAdapter else { return }
        let controller = PlainTextPasteController(clipboardService: adapter)
        controller.onPermissionRequired = { [weak self] in
            self?.windowManager.openSettings(tab: .permission)
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        controller.onFailure = { [weak self] failure in
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Paste", comment: "Paste failure")
            let message: String
            switch failure {
            case .historyUnavailable:
                message = "Clipboard history could not be loaded. Pasting was cancelled without changing the clipboard."
            case .clipboardUnavailable:
                message = "Clipboard contents could not be read. Check Clipboard Access in Settings → Permission."
                self?.windowManager.openSettings(tab: .permission)
            case .deliveryFailed:
                message = "Could not paste. Select an editable text field in the destination app, then try again."
            case .normalPasteUnavailable:
                message = "Could not reserve ⌘V to switch paste formatting. "
                    + "Check for a conflicting shortcut in another app."
            }
            alert.informativeText = NSLocalizedString(message, comment: "Paste failure")
            alert.runModal()
        }
        plainTextPasteController = controller
        windowManager.pasteController = controller
        let hotkey = PlainTextPasteHotkey.shared
        hotkey.onTrigger = { [weak controller] in controller?.paste(using: .alternate) }
        hotkey.onConfigurationChanged = { [weak controller] swapped, enabled in
            controller?.configureShortcuts(swapsFormatting: swapped, enabled: enabled) ?? false
        }
        hotkey.register()
    }

    @objc func handleHotkeyNotification() {
        Task { @MainActor [weak self] in
            self?.openMainWindow()
        }
    }

    func setupTextCaptureHotkey() {
        removeTextCaptureHotkeyObserver()

        let manager = TextCaptureHotkeyManager.shared
        textCaptureHotkeyManager = manager
        manager.onHotkeyTriggered = { [weak self] in
            guard let self else { return }
            self.captureTextFromScreen()
        }

        textCaptureHotkeyObserver = registerTextCaptureSettingsObserver(for: manager)
    }

    func removeTextCaptureHotkeyObserver() {
        if let observer = textCaptureHotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
            textCaptureHotkeyObserver = nil
        }
    }

    func registerTextCaptureSettingsObserver(
        for manager: TextCaptureHotkeyManager
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TextCaptureHotkeySettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let userInfo = notification.userInfo,
                let keyCode = userInfo["keyCode"] as? Int,
                let modifierFlags = userInfo["modifierFlags"] as? Int
            else { return }

            let enabled = userInfo["enabled"] as? Bool ?? true
            Task { @MainActor [weak self] in
                self?.handleTextCaptureSettingsChange(
                    enabled: enabled,
                    keyCode: UInt16(keyCode),
                    modifierFlagsRawValue: UInt(modifierFlags),
                    manager: manager
                )
            }
        }
    }

    func handleTextCaptureSettingsChange(
        enabled: Bool,
        keyCode: UInt16,
        modifierFlagsRawValue: UInt,
        manager: TextCaptureHotkeyManager
    ) {
        let allModifiers = NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
        let resolvedModifiers = allModifiers.intersection([.command, .control, .option, .shift])

        if enabled, keyCode != 0, !resolvedModifiers.isEmpty {
            guard manager.applyHotKey(keyCode: keyCode, modifiers: resolvedModifiers) else { return }
            return
        }

        guard manager.applyHotKey(keyCode: 0, modifiers: []) else { return }
    }

    @objc func captureTextFromScreen() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let screenPermissionGranted = CGPreflightScreenCaptureAccess()
            SystemDiagnostics.permissions(
                screenCapture: screenPermissionGranted,
                accessibility: AXIsProcessTrusted(),
                clipboard: NSPasteboard.general.accessBehavior
            )

            guard screenPermissionGranted else {
                Logger.shared.warning("Screen Text Capture blocked: screen recording permission not granted.")
                windowManager.openSettings(tab: .permission)
                ScreenRecordingPermissionOpener.openSystemSettings()
                return
            }

            textCaptureCoordinator.startCaptureFlow()
        }
    }
}
