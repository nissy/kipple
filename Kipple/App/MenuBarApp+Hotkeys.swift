import AppKit
import ApplicationServices

// MARK: - Hotkey Handling

extension MenuBarApp {
    @objc func handleHotkeyNotification() {
        Task { @MainActor in
            windowManager.openMainWindow()
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
                let self,
                let userInfo = notification.userInfo,
                let keyCode = userInfo["keyCode"] as? Int,
                let modifierFlags = userInfo["modifierFlags"] as? Int
            else { return }

            let enabled = userInfo["enabled"] as? Bool ?? true
            self.handleTextCaptureSettingsChange(
                enabled: enabled,
                keyCode: UInt16(keyCode),
                modifierFlagsRawValue: UInt(modifierFlags),
                manager: manager
            )
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

            guard screenPermissionGranted else {
                Logger.shared.warning("Screen Text Capture blocked: screen recording permission not granted.")
                windowManager.openSettings(tab: .permission)

                if CGPreflightScreenCaptureAccess() {
                    ScreenRecordingPermissionOpener.openSystemSettings()
                }
                return
            }

            textCaptureCoordinator.startCaptureFlow()
        }
    }
}
