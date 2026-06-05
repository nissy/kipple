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

        let panel = panel ?? makePanel()
        install(controller, in: panel)
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
        let origin = popoverOrigin(
            anchorRectOnScreen: anchorRectOnScreen,
            fittingSize: fittingSize,
            visibleFrame: screen.visibleFrame,
            spacing: spacing,
            fallbackTrailing: trailingEdge
        )
        let frame = NSRect(origin: origin, size: fittingSize)
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1.0
        panel.invalidateShadow()
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

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered,
                            defer: false)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.alphaValue = 1.0
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.ignoresMouseEvents = false
        return panel
    }

    private final class GlassContainerView: NSView {
        let contentHost = NSView()
        private let cornerRadius: CGFloat

        init(cornerRadius: CGFloat) {
            self.cornerRadius = cornerRadius
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerRadius = cornerRadius
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
            contentHost.translatesAutoresizingMaskIntoConstraints = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            layer?.cornerRadius = cornerRadius
        }
    }

    private func popoverOrigin(
        anchorRectOnScreen: NSRect,
        fittingSize: NSSize,
        visibleFrame: NSRect,
        spacing: CGFloat,
        fallbackTrailing: Bool
    ) -> CGPoint {
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
            resolvedTrailing = fallbackTrailing
        }

        var origin = CGPoint(
            x: resolvedTrailing ? anchorRectOnScreen.maxX + spacing
                                 : anchorRectOnScreen.minX - fittingSize.width - spacing,
            y: anchorRectOnScreen.maxY - fittingSize.height
        )
        origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - fittingSize.width))
        origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - fittingSize.height))
        return origin
    }

    private func install(_ controller: NSHostingController<ClipboardItemPopover>, in panel: NSPanel) {
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.clear.cgColor
        controller.view.layer?.cornerRadius = 18
        controller.view.layer?.cornerCurve = .continuous
        controller.view.layer?.masksToBounds = true
        controller.view.translatesAutoresizingMaskIntoConstraints = false

        if #available(macOS 26.0, *) {
            installGlass(controller, in: panel)
        } else {
            installMaterial(controller, in: panel)
        }
    }

    @available(macOS 26.0, *)
    private func installGlass(_ controller: NSHostingController<ClipboardItemPopover>, in panel: NSPanel) {
        let container = GlassContainerView(cornerRadius: 18)
        let glassView = NSGlassEffectView()
        glassView.style = .clear
        glassView.cornerRadius = 18
        glassView.tintColor = nil
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = 18
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.masksToBounds = true
        glassView.contentView = controller.view
        container.addSubview(glassView)
        pin(glassView, to: container)
        panel.contentView = container
        panel.contentViewController = nil
    }

    private func installMaterial(_ controller: NSHostingController<ClipboardItemPopover>, in panel: NSPanel) {
        let container = GlassContainerView(cornerRadius: 18)
        let materialView = NSVisualEffectView()
        materialView.blendingMode = .behindWindow
        materialView.material = .popover
        materialView.state = .active
        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 18
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true
        materialView.addSubview(controller.view)
        container.addSubview(materialView)
        pin(materialView, to: container)
        pin(controller.view, to: materialView)
        panel.contentView = container
        panel.contentViewController = nil
    }

    private func pin(_ child: NSView, to parent: NSView) {
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }
}
