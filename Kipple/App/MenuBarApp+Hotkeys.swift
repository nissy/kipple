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

        updateScreenTextCaptureMenuItemShortcut()
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
            updateScreenTextCaptureMenuItemShortcut(with: keyCode, modifiers: resolvedModifiers)
            return
        }

        guard manager.applyHotKey(keyCode: 0, modifiers: []) else { return }
        updateScreenTextCaptureMenuItemShortcut()
    }
}

extension MenuBarApp {
    func openKippleMenuEntry() -> NSMenuItem {
        openKippleMenuItem.title = openKippleMenuTitle
        openKippleMenuItem.target = self
        openKippleMenuItem.action = #selector(openMainWindow)
        return openKippleMenuItem
    }

    func screenTextCaptureMenuEntry() -> NSMenuItem {
        screenTextCaptureMenuItem.title = screenTextCaptureMenuTitle
        screenTextCaptureMenuItem.target = self
        screenTextCaptureMenuItem.action = #selector(captureTextFromScreen)
        return screenTextCaptureMenuItem
    }

    func updateOpenKippleMenuItemShortcut() {
        guard let manager = hotkeyManager as? SimplifiedHotkeyManager else {
            applyShortcut(to: openKippleMenuItem, title: openKippleMenuTitle, combination: nil)
            return
        }

        guard manager.getEnabled() else {
            applyShortcut(to: openKippleMenuItem, title: openKippleMenuTitle, combination: nil)
            return
        }

        let hotkey = manager.getHotkey()
        let sanitizedModifiers = hotkey.modifiers.intersection([.command, .control, .option, .shift])

        if hotkey.keyCode == 0 || sanitizedModifiers.isEmpty {
            applyShortcut(to: openKippleMenuItem, title: openKippleMenuTitle, combination: nil)
            return
        }

        applyShortcut(
            to: openKippleMenuItem,
            title: openKippleMenuTitle,
            combination: (hotkey.keyCode, sanitizedModifiers)
        )
    }

    func updateScreenTextCaptureMenuItemShortcut(
        with keyCode: UInt16? = nil,
        modifiers: NSEvent.ModifierFlags? = nil
    ) {
        let baseTitle = screenTextCaptureMenuTitle
        let screenPermissionGranted = CGPreflightScreenCaptureAccess()
        screenTextCaptureMenuItem.isEnabled = screenPermissionGranted
        screenTextCaptureMenuItem.toolTip = screenPermissionGranted
            ? nil
            : "Grant Screen Recording permission in System Settings to enable Screen Text Capture."

        guard screenPermissionGranted else {
            applyShortcut(to: screenTextCaptureMenuItem, title: baseTitle, combination: nil)
            return
        }

        let combination: (UInt16, NSEvent.ModifierFlags)?

        if let keyCode, let modifiers {
            combination = (keyCode, modifiers)
        } else if let hotkey = textCaptureHotkeyManager?.currentHotkey ?? TextCaptureHotkeyManager.shared.currentHotkey {
            combination = hotkey
        } else {
            combination = nil
        }

        if let combination {
            let sanitizedModifiers = combination.1.intersection([.command, .control, .option, .shift])
            if combination.0 == 0 || sanitizedModifiers.isEmpty {
                applyShortcut(to: screenTextCaptureMenuItem, title: baseTitle, combination: nil)
            } else {
                applyShortcut(
                    to: screenTextCaptureMenuItem,
                    title: baseTitle,
                    combination: (combination.0, sanitizedModifiers)
                )
            }
        } else {
            applyShortcut(to: screenTextCaptureMenuItem, title: baseTitle, combination: nil)
        }
    }

    func shortcutDisplayString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []

        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }

        if let mapping = shortcutMapping(for: keyCode) {
            parts.append(mapping.display)
        }

        return parts.joined()
    }

    func applyShortcut(
        to menuItem: NSMenuItem,
        title: String,
        combination: (UInt16, NSEvent.ModifierFlags)?
    ) {
        menuItem.toolTip = nil

        guard let (keyCode, modifiers) = combination else {
            menuItem.title = title
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
            return
        }

        let mapping = shortcutMapping(for: keyCode)
        let displayString = shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)

        if let keyEquivalent = mapping?.keyEquivalent {
            menuItem.title = title
            menuItem.keyEquivalent = keyEquivalent
            menuItem.keyEquivalentModifierMask = modifiers
        } else if !displayString.isEmpty {
            menuItem.title = "\(title) (\(displayString))"
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
        } else {
            menuItem.title = title
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
        }
    }

    func shortcutMapping(for keyCode: UInt16) -> (display: String, keyEquivalent: String?)? {
        MenuBarShortcutMapping.map[keyCode]
    }

    func screenCaptureMenuItem() -> NSMenuItem {
        screenCaptureStatusItem.target = self
        screenCaptureStatusItem.action = #selector(openScreenRecordingSettingsFromMenu)
        screenCaptureStatusItem.keyEquivalent = ""
        return screenCaptureStatusItem
    }

    func updateScreenCaptureMenuItem() {
        let screenPermissionGranted = CGPreflightScreenCaptureAccess()
        screenCaptureStatusItem.title = screenPermissionGranted
            ? "Screen Recording Permission Ready"
            : "Grant Screen Recording Permission…"
        screenCaptureStatusItem.state = screenPermissionGranted ? .on : .off
        screenCaptureStatusItem.isEnabled = !screenPermissionGranted
        screenCaptureStatusItem.target = screenPermissionGranted ? nil : self
        screenCaptureStatusItem.action = screenPermissionGranted ? nil : #selector(openScreenRecordingSettingsFromMenu)
    }

    func accessibilityMenuItem() -> NSMenuItem {
        accessibilityStatusItem.target = self
        accessibilityStatusItem.action = #selector(openAccessibilitySettingsFromMenu)
        accessibilityStatusItem.keyEquivalent = ""
        return accessibilityStatusItem
    }

    func updateAccessibilityMenuItem() {
        let accessibilityPermissionGranted = AXIsProcessTrusted()
        accessibilityStatusItem.title = accessibilityPermissionGranted
            ? "Accessibility Permission Ready"
            : "Grant Accessibility Permission…"
        accessibilityStatusItem.state = accessibilityPermissionGranted ? .on : .off
        accessibilityStatusItem.isEnabled = !accessibilityPermissionGranted
        accessibilityStatusItem.target = accessibilityPermissionGranted ? nil : self
        accessibilityStatusItem.action = accessibilityPermissionGranted ? nil : #selector(openAccessibilitySettingsFromMenu)
    }

    @objc func openScreenRecordingSettingsFromMenu() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.windowManager.openSettings(tab: .permission)

            // Only open System Settings when the inline request action is unavailable (permission already granted)
            if CGPreflightScreenCaptureAccess() {
                ScreenRecordingPermissionOpener.openSystemSettings()
            }
        }
    }

    @objc func openAccessibilitySettingsFromMenu() {
        Task { @MainActor [weak self] in
            self?.windowManager.openSettings(tab: .permission)
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            ) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc func captureTextFromScreen() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let screenPermissionGranted = CGPreflightScreenCaptureAccess()

            guard screenPermissionGranted else {
                Logger.shared.warning("Screen Text Capture blocked: screen recording permission not granted.")
                updateScreenTextCaptureMenuItemShortcut()
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
