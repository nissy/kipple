//
//  CategoryManagerWindowCoordinator.swift
//  Kipple
//
//  Presents the Manage Categories view in its own window so it is not dismissed by background clicks.
//

import SwiftUI
import AppKit

@MainActor
final class CategoryManagerWindowCoordinator: NSObject, NSWindowDelegate {
    static let shared = CategoryManagerWindowCoordinator()

    private var window: NSWindow?
    private var onCloseHandlers: [() -> Void] = []

    private override init() {
        super.init()
    }

    func open(relativeTo anchorWindow: NSWindow? = nil,
              onOpen: (() -> Void)? = nil,
              onClose: (() -> Void)? = nil) {
        if let onOpen { onOpen() }
        if let onClose { onCloseHandlers.append(onClose) }

        if let window {
            position(window: window, near: anchorWindow)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = NSHostingController(rootView: CategoryManagerView())
        controller.sizingOptions = []

        let window = NSWindow(contentViewController: controller)
        window.title = "Manage Categories"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 460, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false

        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.level = .floating
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        position(window: window, near: anchorWindow)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        for handler in onCloseHandlers {
            handler()
        }
        onCloseHandlers.removeAll()
        window = nil
    }

    private func position(window: NSWindow, near anchorWindow: NSWindow?) {
        guard let anchorWindow else { return }

        var targetOrigin = NSPoint(
            x: anchorWindow.frame.maxX + 16,
            y: anchorWindow.frame.maxY - window.frame.height
        )

        if let screen = anchorWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame

            if targetOrigin.x + window.frame.width > visible.maxX {
                targetOrigin.x = anchorWindow.frame.minX - window.frame.width - 16
            }

            targetOrigin.x = max(visible.minX, min(targetOrigin.x, visible.maxX - window.frame.width))
            targetOrigin.y = max(visible.minY, min(targetOrigin.y, visible.maxY - window.frame.height))
        }

        window.setFrameOrigin(targetOrigin)
    }
}
