//
//  PasteCommandMonitor.swift
//  Kipple
//
//  Created by Kipple on 2025/10/17.
//

import AppKit
import CoreGraphics

@MainActor
protocol PasteCommandMonitoring: AnyObject {
    /// Starts monitoring for Command+V key presses.
    /// - Parameter handler: Invoked on the main actor when a paste command is detected.
    /// - Returns: true if the event tap could be installed.
    func start(handler: @escaping () -> Void) -> Bool
    func stop()
    var hasInputMonitoringPermission: Bool { get }
    /// Shows the system Input Monitoring prompt when possible.
    /// - Returns: true if access is already granted.
    @discardableResult
    func requestInputMonitoringPermission() -> Bool
}

@MainActor
final class PasteCommandMonitor: PasteCommandMonitoring {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: (() -> Void)?

    private nonisolated static let keyCodeV: Int64 = 9

    // sandbox 化されたアプリでは NSEvent のグローバル keyDown モニタにイベントが配送されない
    // (Accessibility 前提・非サンドボックス向けの機構のため)。sandbox で公式にサポートされる
    // Input Monitoring 権限 + listen-only の CGEventTap で Cmd+V を検知する
    func start(handler: @escaping () -> Void) -> Bool {
        stop()

        guard hasInputMonitoringPermission else {
            return false
        }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            if let userInfo {
                let monitor = Unmanaged<PasteCommandMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                // tap source は main runloop に登録しているため callback は main thread で呼ばれる
                MainActor.assumeIsolated {
                    monitor.handleTapEvent(type: type, event: event)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.shared.warning("PasteCommandMonitor: failed to create event tap")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        self.handler = handler
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        handler = nil
    }

    var hasInputMonitoringPermission: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    func requestInputMonitoringPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 権限が生きている場合のみ再有効化 (失効時に無限再 enable しない)
            if let tap = eventTap, hasInputMonitoringPermission {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        case .keyDown:
            let shouldTrigger = Self.shouldTriggerPaste(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                flags: event.flags,
                targetPID: pid_t(event.getIntegerValueField(.eventTargetUnixProcessID)),
                sourceUserData: event.getIntegerValueField(.eventSourceUserData),
                currentPID: ProcessInfo.processInfo.processIdentifier
            )
            if shouldTrigger {
                handler?()
            }
        default:
            break
        }
    }

    nonisolated static func shouldTriggerPaste(
        keyCode: Int64,
        flags: CGEventFlags,
        targetPID: pid_t,
        sourceUserData: Int64,
        currentPID: pid_t
    ) -> Bool {
        guard keyCode == keyCodeV, flags.contains(.maskCommand) else { return false }
        // Kipple 自身が合成した Cmd+V (auto paste) ではキューを進めない
        guard sourceUserData != SyntheticPasteEvent.sourceUserData else { return false }
        // Kipple 自身の UI (検索フィールド等) へのペーストでもキューを進めない。
        // target PID は全イベントで設定される契約がないため best-effort (0 なら判定しない)
        guard targetPID == 0 || targetPID != currentPID else { return false }
        return true
    }
}
