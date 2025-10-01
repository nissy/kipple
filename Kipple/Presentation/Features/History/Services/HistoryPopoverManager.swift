//
//  HistoryPopoverManager.swift
//  Kipple
//
//  Created by Codex on 2025/09/26.
//

import SwiftUI
import AppKit

@MainActor
final class HistoryPopoverManager {
    static let shared = HistoryPopoverManager()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<ClipboardItemPopover>?
    private weak var anchorView: NSView?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    func show(item: ClipItem, from anchorView: NSView, trailingEdge: Bool) {
        hideWorkItem?.cancel()
        self.anchorView = anchorView

        let controller: NSHostingController<ClipboardItemPopover>
        if let existing = hostingController {
            controller = existing
            controller.rootView = ClipboardItemPopover(item: item)
        } else {
            let newController = NSHostingController(rootView: ClipboardItemPopover(item: item))
            hostingController = newController
            controller = newController
        }

        let panel = panel ?? makePanel(with: controller)
        panel.contentViewController = controller
        hostingController = controller
        self.panel = panel

        controller.view.layoutSubtreeIfNeeded()
        let fittingSize = controller.view.fittingSize

        guard let window = anchorView.window,
              let screen = window.screen ?? NSScreen.main else {
            hide()
            return
        }

        let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorRectOnScreen = window.convertToScreen(anchorRectInWindow)

        let spacing: CGFloat = 8
        let visibleFrame = screen.visibleFrame

        let hasSpaceOnRight = anchorRectOnScreen.maxX + spacing + fittingSize.width <= visibleFrame.maxX
        let hasSpaceOnLeft = anchorRectOnScreen.minX - spacing - fittingSize.width >= visibleFrame.minX
        let preferredTrailing = anchorRectOnScreen.midX <= visibleFrame.midX

        let resolvedTrailing: Bool
        switch (hasSpaceOnLeft, hasSpaceOnRight) {
        case (false, true):
            resolvedTrailing = true
        case (true, false):
            resolvedTrailing = false
        case (true, true):
            resolvedTrailing = preferredTrailing
        default:
            resolvedTrailing = trailingEdge
        }

        var origin = CGPoint(
            x: resolvedTrailing ? anchorRectOnScreen.maxX + spacing
                                 : anchorRectOnScreen.minX - fittingSize.width - spacing,
            y: anchorRectOnScreen.maxY - fittingSize.height
        )

        origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - fittingSize.width))
        origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - fittingSize.height))

        let frame = NSRect(origin: origin, size: fittingSize)
        panel.setFrame(frame, display: true)
        panel.orderFront(nil)
    }

    func scheduleHide(after interval: TimeInterval = 0.15) {
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        anchorView = nil
    }

    func forceClose() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        anchorView = nil
    }

    private func makePanel(with controller: NSHostingController<ClipboardItemPopover>) -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered,
                            defer: false)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.contentViewController = controller
        panel.ignoresMouseEvents = false
        return panel
    }
}
