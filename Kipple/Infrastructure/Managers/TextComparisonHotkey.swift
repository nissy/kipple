import AppKit
import Carbon
import Combine

@MainActor
final class TextComparisonHotkey: ObservableObject {
    struct Shortcut: Equatable {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags

        static let disabled = Shortcut(keyCode: 0, modifiers: [])
    }

    enum ConfigurationError {
        case modifierRequired, unavailable
    }

    static let shared = TextComparisonHotkey()

    @Published private(set) var shortcut: Shortcut
    @Published private(set) var registrationFailed = false
    var onTrigger: (() -> Void)?

    private static let keyCodeKey = "textComparisonHotkeyKeyCode"
    private static let modifiersKey = "textComparisonHotkeyModifierFlags"
    private static let signature: OSType = 0x4B504446 // KPDF
    private let defaults = UserDefaults.standard
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var identifier: UInt32 = 0
    private var suspended = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        let keyCode = UInt16(exactly: defaults.integer(forKey: Self.keyCodeKey)) ?? 0
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(clamping: defaults.integer(forKey: Self.modifiersKey)))
        shortcut = modifiers.isEmpty ? .disabled : Shortcut(keyCode: keyCode, modifiers: modifiers)
        observe("SuspendGlobalHotkeyCapture") {
            $0.suspended = true
            $0.unregister()
        }
        observe("ResumeGlobalHotkeyCapture") {
            $0.suspended = false
            $0.register()
        }
    }

    func register() {
        guard onTrigger != nil, !suspended, hotKey == nil, shortcut != .disabled else { return }
        registrationFailed = conflicts(with: shortcut) || !register(shortcut)
    }

    func apply(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> ConfigurationError? {
        let candidate = Shortcut(keyCode: keyCode, modifiers: modifiers)
        if candidate == .disabled {
            unregister()
        } else {
            guard !modifiers.isDisjoint(with: [.command, .control, .option]) else { return .modifierRequired }
            guard !conflicts(with: candidate) else { return .unavailable }
            guard candidate == shortcut && hotKey != nil || register(candidate) else { return .unavailable }
        }
        shortcut = candidate
        defaults.set(Int(candidate.keyCode), forKey: Self.keyCodeKey)
        defaults.set(Int(candidate.modifiers.rawValue), forKey: Self.modifiersKey)
        registrationFailed = false
        if suspended { unregister() }
        return nil
    }

    func uses(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        shortcut != .disabled && shortcut == Shortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private func conflicts(with candidate: Shortcut) -> Bool {
        if candidate.modifiers == .command, [kVK_ANSI_C, kVK_ANSI_X, kVK_ANSI_V].contains(Int(candidate.keyCode)) {
            return true
        }
        // The settings recorder temporarily releases the other global shortcuts.
        let main = SimplifiedHotkeyManager.shared
        let open = main.getHotkey()
        let capture = TextCaptureHotkeyManager.shared.currentHotkey
        let paste = PlainTextPasteHotkey.shared.shortcut
        let used = [
            main.getEnabled() ? Shortcut(keyCode: open.keyCode, modifiers: open.modifiers) : nil,
            capture.map { Shortcut(keyCode: $0.keyCode, modifiers: $0.modifiers) },
            Shortcut(keyCode: paste.keyCode, modifiers: paste.modifiers)
        ]
        return used.contains(candidate)
    }

    private func register(_ shortcut: Shortcut) -> Bool {
        guard installHandler() else { return false }
        var carbonModifiers: UInt32 = 0
        if shortcut.modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if shortcut.modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if shortcut.modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if shortcut.modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        let nextID = identifier &+ 1
        var registration: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), carbonModifiers, EventHotKeyID(signature: Self.signature, id: nextID),
            GetEventDispatcherTarget(), UInt32(kEventHotKeyExclusive), &registration
        )
        guard status == noErr, let registration else { return false }
        unregister()
        hotKey = registration
        identifier = nextID
        return true
    }

    private func installHandler() -> Bool {
        guard handler == nil else { return true }
        // As with plain-text paste, wait for the shortcut key to be released before sending a copy command.
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let callback: EventHandlerUPP = { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(
                event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard status == noErr else { return status }
            return MainActor.assumeIsolated {
                let hotkey = Unmanaged<TextComparisonHotkey>.fromOpaque(context).takeUnretainedValue()
                guard id.signature == TextComparisonHotkey.signature, id.id == hotkey.identifier,
                      hotkey.hotKey != nil, !hotkey.suspended else { return OSStatus(eventNotHandledErr) }
                hotkey.onTrigger?()
                return noErr
            }
        }
        return InstallEventHandler(
            GetEventDispatcherTarget(), callback, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler
        ) == noErr
    }

    private func observe(_ name: String, action: @escaping @MainActor (TextComparisonHotkey) -> Void) {
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name(name), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        })
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    isolated deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
}
