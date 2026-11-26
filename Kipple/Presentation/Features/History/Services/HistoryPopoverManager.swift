//
//  HistoryPopoverManager.swift
//  Kipple
//
//  Created by Codex on 2025/09/26.
//

import SwiftUI
import AppKit
import Combine

@MainActor
final class HistoryPopoverManager {
    static let shared = HistoryPopoverManager()

    private var panel: NSPanel?
    private var hostingController: NSHostingController<ClipboardItemPopover>?
    private weak var anchorView: NSView?
    private var hideWorkItem: DispatchWorkItem?
    private var isPointerOverPanel = false
    private let pointerLocation: () -> CGPoint

    private var observers = Set<AnyCancellable>()

    init(pointerLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.pointerLocation = pointerLocation
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in self?.hide() }
            .store(in: &observers)
    }

    func show(item: ClipItem, from anchorView: NSView, trailingEdge: Bool) {
        guard !isPointerInsidePanel,
              let window = anchorView.window,
              let screen = window.screen ?? NSScreen.main else { return }
        cancelScheduledHide()
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

    func prepareForRowHover(_ anchor: NSView) -> Bool {
        guard panel != nil else { return false }
        if anchorView === anchor {
            cancelScheduledHide()
            return false
        }

        // The pointer can cross another row on its way to the panel. Let the new hover settle first.
        scheduleHide()
        return true
    }

    func scheduleHide(after interval: TimeInterval = 0.35, ifAnchoredTo anchor: NSView? = nil) {
        guard panel != nil, !isPointerInsidePanel, anchor == nil || anchorView === anchor else { return }
        cancelScheduledHide()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isPointerInsidePanel else { return }
            self.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    func hide(ifAnchoredTo anchor: NSView? = nil) {
        guard anchor == nil || anchorView === anchor else { return }
        cancelScheduledHide()
        isPointerOverPanel = false
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        anchorView = nil
    }

    func forceClose() {
        hide()
    }

    private func cancelScheduledHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private var isPointerInsidePanel: Bool {
        guard let panel, panel.isVisible else { return false }
        return isPointerOverPanel || panel.frame.contains(pointerLocation())
    }

    private func updatePanelHover(_ hovering: Bool) {
        isPointerOverPanel = hovering
        if hovering {
            cancelScheduledHide()
        } else {
            scheduleHide()
        }
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
        private let cornerRadius: CGFloat
        private let onHover: (Bool, NSView) -> Void
        private var hoverArea: NSTrackingArea?

        init(cornerRadius: CGFloat, onHover: @escaping (Bool, NSView) -> Void) {
            self.cornerRadius = cornerRadius
            self.onHover = onHover
            super.init(frame: .zero)
            wantsLayer = true
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.cornerRadius = cornerRadius
            layer?.cornerCurve = .continuous
            layer?.masksToBounds = true
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            layer?.cornerRadius = cornerRadius
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(
                rect: .zero,
                options: [.inVisibleRect, .mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            hoverArea = area
        }

        override func mouseEntered(with event: NSEvent) { onHover(true, self) }
        override func mouseExited(with event: NSEvent) { onHover(false, self) }
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
        controller.view.layer?.cornerRadius = HistoryItemPreviewContent.cornerRadius
        controller.view.layer?.cornerCurve = .continuous
        controller.view.layer?.masksToBounds = true
        controller.view.translatesAutoresizingMaskIntoConstraints = false

        installGlass(controller, in: panel)
    }

    private func installGlass(_ controller: NSHostingController<ClipboardItemPopover>, in panel: NSPanel) {
        let cornerRadius = HistoryItemPreviewContent.cornerRadius
        let container = GlassContainerView(cornerRadius: cornerRadius) { [weak self] hovering, source in
            guard let self, self.panel?.contentView === source else { return }
            self.updatePanelHover(hovering)
        }
        let glassView = NSGlassEffectView()
        glassView.style = .regular
        glassView.cornerRadius = cornerRadius
        glassView.tintColor = nil
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = cornerRadius
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.masksToBounds = true
        glassView.contentView = controller.view
        container.addSubview(glassView)
        pin(glassView, to: container)
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
