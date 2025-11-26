//
//  HistoryActionKeyMonitor.swift
//  Kipple
//
//  Created by Codex on 2025/11/19.
//

import AppKit
import Combine

@MainActor
final class HistoryActionKeyMonitor: ObservableObject {
    @Published private(set) var isActionKeyActive = false

    private let allowedModifiers: NSEvent.ModifierFlags = [.command, .option]
    private var flagsMonitor: EventMonitorToken?
    private var settingsCancellable: AnyCancellable?
    private var activationObserver: EventMonitorToken?
    private var resignationObserver: EventMonitorToken?
    private let appSettings = AppSettings.shared
    private var requiredModifiers: NSEvent.ModifierFlags = []

    init() {
        updateRequiredModifiers()
        updateActionState(with: NSEvent.modifierFlags)
        if let token = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: { [weak self] event in
                Task { @MainActor in
                    self?.updateActionState(with: event.modifierFlags)
                }
                return event
            }
        ) {
            flagsMonitor = EventMonitorToken(token)
        }
        settingsCancellable = appSettings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateRequiredModifiers()
                self?.updateActionState(with: NSEvent.modifierFlags)
            }
        }

        activationObserver = EventMonitorToken(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.updateActionState(with: NSEvent.modifierFlags)
                }
            }
        )

        resignationObserver = EventMonitorToken(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.isActionKeyActive = false
                }
            }
        )
    }

    private func updateRequiredModifiers() {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(appSettings.actionClickModifiers))
        let normalized = modifiers
            .intersection(.deviceIndependentFlagsMask)
            .intersection(allowedModifiers)
        requiredModifiers = normalized
        if requiredModifiers.isEmpty {
            isActionKeyActive = false
        }
    }

    private func updateActionState(with flags: NSEvent.ModifierFlags) {
        guard !requiredModifiers.isEmpty else {
            if isActionKeyActive {
                isActionKeyActive = false
            }
            return
        }
        let current = flags.intersection(.deviceIndependentFlagsMask)
        let nextActive = (current == requiredModifiers)
        if isActionKeyActive != nextActive {
            isActionKeyActive = nextActive
        }
    }

    deinit {
        if let monitor = flagsMonitor?.rawValue {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = activationObserver?.rawValue as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = resignationObserver?.rawValue as? NSObjectProtocol {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

private final class EventMonitorToken: @unchecked Sendable {
    let rawValue: Any

    init(_ rawValue: Any) {
        self.rawValue = rawValue
    }
}
