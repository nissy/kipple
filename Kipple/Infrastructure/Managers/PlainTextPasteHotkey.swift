import AppKit
import ApplicationServices
import Carbon
import Combine

@MainActor
final class PlainTextPasteHotkey: ObservableObject {
    static let shared = PlainTextPasteHotkey()
    static let keyCodeDefaultsKey = "plainTextPasteHotkeyKeyCode"
    static let modifierDefaultsKey = "plainTextPasteHotkeyModifierFlags"

    struct Shortcut: Equatable {
        var keyCode: UInt16
        var modifiers: NSEvent.ModifierFlags

        static let defaultShortcut = Shortcut(keyCode: 9, modifiers: [.control, .shift])
        static let disabled = Shortcut(keyCode: 0, modifiers: [])
    }

    enum ConfigurationError: Error, Equatable {
        case permissionRequired
        case modifierRequired
        case shortcutUnavailable
    }

    @Published private(set) var isRegistered = false
    @Published private(set) var hasAccessibilityPermission: Bool
    @Published private(set) var registrationFailed = false
    @Published private(set) var shortcut: Shortcut
    var onTrigger: (() -> Void)?

    private static let signature: OSType = 0x4B505054 // KPPT
    private let defaults: UserDefaults
    private let permissionCheck: () -> Bool
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var isCaptureSuspended = false

    init(
        defaults: UserDefaults = .standard,
        permissionCheck: @escaping () -> Bool = AXIsProcessTrusted,
        observeChanges: Bool = true
    ) {
        self.defaults = defaults
        self.permissionCheck = permissionCheck
        hasAccessibilityPermission = permissionCheck()
        if defaults.object(forKey: Self.keyCodeDefaultsKey) != nil,
           let keyCode = UInt16(exactly: defaults.integer(forKey: Self.keyCodeDefaultsKey)),
           let rawModifiers = UInt(exactly: defaults.integer(forKey: Self.modifierDefaultsKey)) {
            let modifiers = NSEvent.ModifierFlags(rawValue: rawModifiers)
                .intersection([.command, .control, .option, .shift])
            shortcut = modifiers.isEmpty ? .disabled : Shortcut(keyCode: keyCode, modifiers: modifiers)
        } else {
            shortcut = .defaultShortcut
        }
        guard observeChanges else { return }
        observe(Notification.Name("SuspendGlobalHotkeyCapture")) {
            $0.isCaptureSuspended = true
            $0.unregister()
        }
        observe(Notification.Name("ResumeGlobalHotkeyCapture")) {
            $0.isCaptureSuspended = false
            $0.register()
        }
        observe(NSApplication.didBecomeActiveNotification) { $0.refreshPermission() }
        observe(NSWorkspace.didActivateApplicationNotification, center: NSWorkspace.shared.notificationCenter) {
            $0.refreshPermission()
        }
    }

    func refreshPermission() { register() }

    func register() {
        hasAccessibilityPermission = permissionCheck()
        guard hasAccessibilityPermission else {
            unregister()
            registrationFailed = false
            return
        }
        guard !isCaptureSuspended, hotKey == nil, onTrigger != nil, shortcut != .disabled else { return }
        registrationFailed = conflictsWithBuiltInShortcut(shortcut) || !registerShortcut(shortcut)
    }

    @discardableResult
    func apply(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ConfigurationError? {
        hasAccessibilityPermission = permissionCheck()
        guard hasAccessibilityPermission else {
            unregister()
            return .permissionRequired
        }
        let candidate = Shortcut(
            keyCode: keyCode, modifiers: modifiers.intersection([.command, .control, .option, .shift])
        )
        guard candidate == .disabled || !candidate.modifiers.isDisjoint(with: [.command, .control, .option]) else {
            return .modifierRequired
        }
        guard !conflictsWithBuiltInShortcut(candidate) else { return .shortcutUnavailable }
        unregister()
        guard candidate == .disabled || registerShortcut(candidate) else {
            register()
            return .shortcutUnavailable
        }
        shortcut = candidate
        defaults.set(Int(candidate.keyCode), forKey: Self.keyCodeDefaultsKey)
        defaults.set(Int(candidate.modifiers.rawValue), forKey: Self.modifierDefaultsKey)
        registrationFailed = false
        if isCaptureSuspended { unregister() }
        return nil
    }

    private func conflictsWithBuiltInShortcut(_ candidate: Shortcut) -> Bool {
        guard candidate != .disabled else { return false }
        // Never replace normal paste, including the queue's temporary Command+V shortcut.
        if candidate == Shortcut(keyCode: 9, modifiers: .command) { return true }
        // Other hotkeys are temporarily unregistered while recording. Check their saved settings too.
        let savedShortcuts = [
            ("hotkeyKeyCode", "hotkeyModifierFlags"),
            (TextCaptureHotkeyManager.keyCodeDefaultsKey, TextCaptureHotkeyManager.modifierDefaultsKey)
        ]
        return savedShortcuts.contains { key, flags in
            defaults.integer(forKey: key) == Int(candidate.keyCode)
                && defaults.integer(forKey: flags) == Int(candidate.modifiers.rawValue)
        }
    }

    private func registerShortcut(_ shortcut: Shortcut) -> Bool {
        guard installHandler() else { return false }
        var carbonModifiers: UInt32 = 0
        if shortcut.modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if shortcut.modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), carbonModifiers, EventHotKeyID(signature: Self.signature, id: 1),
            GetEventDispatcherTarget(), 0, &hotKey
        )
        isRegistered = status == noErr && hotKey != nil
        if !isRegistered { Logger.shared.error("Plain text paste shortcut registration failed: \(status)") }
        return isRegistered
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        isRegistered = false
    }

    private func installHandler() -> Bool {
        guard eventHandler == nil else { return true }
        // Trigger on release, so the held Control/Shift keys cannot affect the generated Cmd+V.
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let callback: EventHandlerUPP = { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &identifier
            )
            guard status == noErr else { return status }
            return MainActor.assumeIsolated {
                let manager = Unmanaged<PlainTextPasteHotkey>.fromOpaque(context).takeUnretainedValue()
                guard identifier.signature == PlainTextPasteHotkey.signature,
                      identifier.id == 1, manager.isRegistered else {
                    return OSStatus(eventNotHandledErr)
                }
                manager.triggerIfPermitted()
                return noErr
            }
        }
        let status = InstallEventHandler(
            GetEventDispatcherTarget(), callback, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
        if status != noErr { Logger.shared.error("Plain text paste event handler failed: \(status)") }
        return status == noErr
    }

    func triggerIfPermitted() {
        refreshPermission()
        guard isRegistered, !isCaptureSuspended, hasAccessibilityPermission else { return }
        onTrigger?()
    }

    private func observe(
        _ name: Notification.Name,
        center: NotificationCenter = .default,
        action: @escaping @MainActor (PlainTextPasteHotkey) -> Void
    ) {
        let observer = center.addObserver(
            forName: name, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        observers.append((center, observer))
    }

    isolated deinit {
        unregister()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        for (center, observer) in observers { center.removeObserver(observer) }
    }
}
