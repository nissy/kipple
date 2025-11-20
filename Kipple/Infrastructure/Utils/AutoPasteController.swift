//
//  AutoPasteController.swift
//  Kipple
//
//  Created by Codex on 2025/11/17.
//

import Foundation
import ApplicationServices
import AppKit

@MainActor
final class AutoPasteController {
    static let shared = AutoPasteController()

    private var pendingWorkItem: DispatchWorkItem?
    // 知覚遅延を抑えるためディレイを短縮
    private let defaultDelay: TimeInterval = 0.05

    private init() {}

    func canAutoPaste() -> Bool {
        AXIsProcessTrusted()
    }

    func schedulePaste(after delay: TimeInterval? = nil) {
        pendingWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.pendingWorkItem = nil
            self?.sendPasteCommand()
        }

        pendingWorkItem = work
        let fireDelay = delay ?? defaultDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + fireDelay, execute: work)
    }

    private func sendPasteCommand() {
        guard AXIsProcessTrusted() else { return }
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        let keyCode = CGKeyCode(9) // Virtual key for "v"
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }

        keyDown.flags = [.maskCommand]
        keyUp.flags = [.maskCommand]
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
