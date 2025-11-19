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

    private var flagsMonitor: EventMonitorToken?
    private var settingsCancellable: AnyCancellable?
    private let appSettings = AppSettings.shared
    private var requiredModifiers: NSEvent.ModifierFlags = []

    init() {
        updateRequiredModifiers()
        updateActionState(with: NSEvent.modifierFlags)
        if let token = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.updateActionState(with: event.modifierFlags)
            }
            return event
        } {
            flagsMonitor = EventMonitorToken(token)
        }
        settingsCancellable = appSettings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                self?.updateRequiredModifiers()
                self?.updateActionState(with: NSEvent.modifierFlags)
            }
        }
    }

    private func updateRequiredModifiers() {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(appSettings.actionClickModifiers))
        requiredModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
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
    }
}

private final class EventMonitorToken: @unchecked Sendable {
    let rawValue: Any

    init(_ rawValue: Any) {
        self.rawValue = rawValue
    }
}
