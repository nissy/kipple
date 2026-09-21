import AppKit
import ApplicationServices
import Carbon

@MainActor
protocol PasteCommandMonitoring: AnyObject {
    /// Reserves Command+V for queue paste, formatting recovery, or plain text as the default paste.
    func start(handler: @escaping () -> Void) -> Bool
    func stop()
    var hasPermission: Bool { get }
}

@MainActor
final class PasteCommandMonitor: PasteCommandMonitoring {
    private static let signature: OSType = 0x4B505151 // KPQQ
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?
    private let permissionCheck: () -> Bool

    init(permissionCheck: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.permissionCheck = permissionCheck
    }

    var hasPermission: Bool { permissionCheck() }

    func start(handler: @escaping () -> Void) -> Bool {
        stop()
        guard hasPermission, installHandler() else { return false }
        let status = RegisterEventHotKey(
            9, UInt32(cmdKey), EventHotKeyID(signature: Self.signature, id: 1),
            GetEventDispatcherTarget(), 0, &hotKey
        )
        guard status == noErr, hotKey != nil else {
            Logger.shared.warning("Paste shortcut registration failed: \(status)")
            stop()
            return false
        }
        self.handler = handler
        return true
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        handler = nil
    }

    private func installHandler() -> Bool {
        // A listen-only tap cannot hold the physical key while asynchronous clipboard work finishes.
        // Carbon shortcuts work in the sandbox; synthetic paste events go directly to the target PID.
        // Command+V has no extra modifiers to release, so prepare and paste as soon as the key is pressed.
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(
                event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil,
                MemoryLayout<EventHotKeyID>.size, nil, &identifier
            )
            guard status == noErr else { return status }
            return MainActor.assumeIsolated {
                let monitor = Unmanaged<PasteCommandMonitor>.fromOpaque(context).takeUnretainedValue()
                return monitor.handleHotKey(signature: identifier.signature, id: identifier.id)
                    ? noErr : OSStatus(eventNotHandledErr)
            }
        }
        return InstallEventHandler(
            GetEventDispatcherTarget(), callback, 1, &type,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        ) == noErr
    }

    func handleHotKey(signature: OSType, id: UInt32) -> Bool {
        guard signature == Self.signature, id == 1, hotKey != nil else { return false }
        handler?()
        return true
    }

    isolated deinit { stop() }
}
