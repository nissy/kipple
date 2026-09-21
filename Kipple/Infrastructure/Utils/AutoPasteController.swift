//
//  AutoPasteController.swift
//  Kipple
//
//  Created by Codex on 2025/11/17.
//

import Foundation
import ApplicationServices
import AppKit

/// Kipple 自身が合成するペーストイベントの識別子。
/// PasteCommandMonitor がキュー前進の対象から除外するために参照する
enum SyntheticPasteEvent {
    // "KPST" (Kipple Paste)
    static let sourceUserData: Int64 = 0x4B50_5354
}

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

    /// キューモード開始時に呼び、予約済みの auto paste がキューを誤って進めないようにする
    func cancelPendingPaste() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    private func sendPasteCommand() {
        guard AXIsProcessTrusted() else { return }
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
              frontApp.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        _ = Self.sendPasteCommand(to: frontApp.processIdentifier)
    }

    @discardableResult
    static func sendPasteCommand(to processID: pid_t) -> Bool {
        guard AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
              let source = CGEventSource(stateID: .hidSystemState) else { return false }

        let keyCode = CGKeyCode(9) // Virtual key for "v"
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = [.maskCommand]
        keyUp.flags = [.maskCommand]
        keyDown.setIntegerValueField(.eventSourceUserData, value: SyntheticPasteEvent.sourceUserData)
        keyUp.setIntegerValueField(.eventSourceUserData, value: SyntheticPasteEvent.sourceUserData)
        keyDown.postToPid(processID)
        keyUp.postToPid(processID)
        return true
    }
}
