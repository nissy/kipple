//
//  PasteCommandMonitor.swift
//  Kipple
//
//  Created by Kipple on 2025/10/17.
//

import AppKit
import ApplicationServices

@MainActor
protocol PasteCommandMonitoring: AnyObject {
    /// Starts monitoring for Command+V key presses.
    /// - Parameter handler: Invoked on the main actor when a paste command is detected.
    /// - Returns: true if any monitor could be installed.
    func start(handler: @escaping () -> Void) -> Bool
    func stop()
    var hasAccessibilityPermission: Bool { get }
}

@MainActor
final class PasteCommandMonitor: PasteCommandMonitoring {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func start(handler: @escaping () -> Void) -> Bool {
        stop()

        guard hasAccessibilityPermission else {
            return false
        }

        let wrapped: (NSEvent) -> Void = { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.contains(.command), event.keyCode == 9 {
                handler()
            }
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: wrapped)

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            wrapped(event)
            return event
        }

        return globalMonitor != nil || localMonitor != nil
    }

    func stop() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }
}
