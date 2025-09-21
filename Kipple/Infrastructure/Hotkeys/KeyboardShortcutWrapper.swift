import Foundation
import AppKit
import Combine

/// Modern wrapper for keyboard shortcuts using native Swift APIs
@available(macOS 13.0, *)
@MainActor
final class KeyboardShortcutWrapper {
    // MARK: - Types

    struct Shortcut: Codable, Equatable {
        let identifier: String
        let keyCode: UInt16
        let modifierFlags: UInt
        var isEnabled: Bool = true

        var modifiers: NSEvent.ModifierFlags {
            NSEvent.ModifierFlags(rawValue: modifierFlags)
        }

        init(
            identifier: String,
            keyCode: UInt16,
            modifiers: NSEvent.ModifierFlags,
            isEnabled: Bool = true
        ) {
            self.identifier = identifier
            self.keyCode = keyCode
            self.modifierFlags = modifiers.rawValue
            self.isEnabled = isEnabled
        }
    }

    typealias Handler = () -> Void

    // MARK: - Properties

    private var shortcuts: [String: Shortcut] = [:]
    private var handlers: [String: Handler] = [:]
    private var eventMonitor: Any?
    private let userDefaultsKey = "KippleKeyboardShortcuts"

    // Publisher for shortcut changes
    let shortcutChangedPublisher = PassthroughSubject<String, Never>()

    // MARK: - Initialization

    init() {
        loadShortcuts()
        startMonitoring()
    }

    deinit {
        // stopMonitoring called directly as this class is MainActor isolated
        stopMonitoring()
    }

    // MARK: - Public Methods

    func register(
        _ identifier: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        handler: @escaping Handler
    ) {
        let shortcut = Shortcut(
            identifier: identifier,
            keyCode: keyCode,
            modifiers: modifiers
        )

        shortcuts[identifier] = shortcut
        handlers[identifier] = handler

        saveShortcuts()
        shortcutChangedPublisher.send(identifier)

        Logger.shared.debug("Registered shortcut: \(identifier) with keyCode: \(keyCode)")
    }

    func unregister(_ identifier: String) {
        shortcuts.removeValue(forKey: identifier)
        handlers.removeValue(forKey: identifier)

        saveShortcuts()
        shortcutChangedPublisher.send(identifier)

        Logger.shared.debug("Unregistered shortcut: \(identifier)")
    }

    func update(
        _ identifier: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        guard shortcuts[identifier] != nil else {
            Logger.shared.warning("Cannot update non-existent shortcut: \(identifier)")
            return false
        }

        shortcuts[identifier] = Shortcut(
            identifier: identifier,
            keyCode: keyCode,
            modifiers: modifiers,
            isEnabled: shortcuts[identifier]?.isEnabled ?? true
        )

        saveShortcuts()
        shortcutChangedPublisher.send(identifier)

        return true
    }

    func setEnabled(_ enabled: Bool, for identifier: String) {
        guard var shortcut = shortcuts[identifier] else { return }
        shortcut.isEnabled = enabled
        shortcuts[identifier] = shortcut

        saveShortcuts()
        shortcutChangedPublisher.send(identifier)
    }

    func isEnabled(_ identifier: String) -> Bool {
        shortcuts[identifier]?.isEnabled ?? false
    }

    func isRegistered(_ identifier: String) -> Bool {
        shortcuts[identifier] != nil
    }

    func getShortcut(for identifier: String) -> Shortcut? {
        shortcuts[identifier]
    }

    func getAllShortcuts() -> [Shortcut] {
        Array(shortcuts.values)
    }

    func reset() {
        shortcuts.removeAll()
        handlers.removeAll()
        saveShortcuts()
    }

    // MARK: - Event Monitoring

    private func startMonitoring() {
        stopMonitoring()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        Logger.shared.debug("Started keyboard shortcut monitoring")
    }

    nonisolated private func stopMonitoring() {
        // This needs to be accessible from deinit, which is nonisolated
        // The actual cleanup happens on MainActor
        Task { @MainActor in
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
                Logger.shared.debug("Stopped keyboard shortcut monitoring")
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        for (identifier, shortcut) in shortcuts {
            guard shortcut.isEnabled else { continue }

            if shortcut.keyCode == keyCode && shortcut.modifiers == modifiers {
                Logger.shared.debug("Triggered shortcut: \(identifier)")

                DispatchQueue.main.async { [weak self] in
                    self?.handlers[identifier]?()
                }

                return
            }
        }
    }

    // MARK: - Persistence

    private func saveShortcuts() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(Array(shortcuts.values)) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadShortcuts() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let savedShortcuts = try? JSONDecoder().decode([Shortcut].self, from: data) else {
            return
        }

        for shortcut in savedShortcuts {
            shortcuts[shortcut.identifier] = shortcut
        }

        Logger.shared.debug("Loaded \(shortcuts.count) shortcuts from UserDefaults")
    }

    // MARK: - Testing Support

    func simulateKeyPress(_ identifier: String) {
        guard shortcuts[identifier]?.isEnabled == true else { return }
        handlers[identifier]?()
    }
}
