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
    private var contentController: GlassWindowContentController<CategoryManagerView>?
    private var onCloseHandlers: [() -> Void] = []

    private override init() {
        super.init()
    }

    func open(
        relativeTo anchorWindow: NSWindow? = nil,
        onOpen: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        if let onOpen { onOpen() }
        if let onClose { onCloseHandlers.append(onClose) }

        if let window {
            window.title = String(localized: "Manage Categories")
            position(window: window, near: anchorWindow)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let controller = GlassWindowContentController(
            rootView: CategoryManagerView { [weak self] in
                self?.close()
            },
            cornerRadius: KippleGlassMetrics.windowCornerRadius
        )

        let window = NSWindow(contentViewController: controller)
        window.title = String(localized: "Manage Categories")
        window.styleMask = [.titled, .closable, .fullSizeContentView]

        applyContentSize(controller, to: window)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.window = window
        self.contentController = controller

        NSApp.activate(ignoringOtherApps: true)
        window.level = .floating
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        position(window: window, near: anchorWindow)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            guard
                let self,
                let window,
                let controller = self.contentController
            else { return }
            self.applyContentSize(controller, to: window)
        }
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
        contentController = nil
    }

    private func applyContentSize(_ controller: GlassWindowContentController<CategoryManagerView>, to window: NSWindow) {
        let fallbackSize = NSSize(width: CategoryManagerView.minimumWidth, height: CategoryManagerView.minimumHeight)

        let fitting = controller.hostedFittingSize(fallback: fallbackSize)

        let targetSize = NSSize(
            width: max(fitting.width, fallbackSize.width),
            height: max(fitting.height, fallbackSize.height)
        )

        window.setContentSize(targetSize)
        window.contentMinSize = fallbackSize
    }

    private func position(window: NSWindow, near anchorWindow: NSWindow?) {
        guard let anchorWindow else { return }

        var targetOrigin = NSPoint(
            x: anchorWindow.frame.maxX + KippleGlassMetrics.adjacentWindowSpacing,
            y: anchorWindow.frame.maxY - window.frame.height
        )

        if let screen = anchorWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame

            if targetOrigin.x + window.frame.width > visible.maxX {
                targetOrigin.x = anchorWindow.frame.minX - window.frame.width - KippleGlassMetrics.adjacentWindowSpacing
            }

            targetOrigin.x = max(visible.minX, min(targetOrigin.x, visible.maxX - window.frame.width))
            targetOrigin.y = max(visible.minY, min(targetOrigin.y, visible.maxY - window.frame.height))
        }

        window.setFrameOrigin(targetOrigin)
    }
}

#if DEBUG
extension CategoryManagerWindowCoordinator {
    func test_position(window: NSWindow, near anchorWindow: NSWindow?) {
        position(window: window, near: anchorWindow)
    }
}
#endif
