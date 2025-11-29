#if DEBUG

extension MenuBarApp {
    func startServicesAsync() async {
        startServices()
    }

    func isClipboardMonitoring() async -> Bool {
        if let modernService = clipboardService as? ModernClipboardServiceAdapter {
            return await modernService.isMonitoring()
        }
        return true
    }

    func performTermination() async {
        // Extract the async work from performAsyncTermination so tests can await completion.
        await clipboardService.flushPendingSaves()
    }

    func registerHotkeys() async {
        if let simplifiedManager = hotkeyManager as? SimplifiedHotkeyManager {
            simplifiedManager.setEnabled(true)
        }
    }

    @MainActor
    func isHotkeyRegistered() -> Bool {
        if let simplifiedManager = hotkeyManager as? SimplifiedHotkeyManager {
            return simplifiedManager.getEnabled()
        }
        return false
    }

    // Remove duplicate - already defined as @objc private method
}

#endif
