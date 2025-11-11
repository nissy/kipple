//
//  ScreenSelectionOverlayController.swift
//  Kipple
//
//  Created by Kipple on 2025/10/09.
//

import AppKit
import QuartzCore

@MainActor
protocol ScreenSelectionOverlayControlling: AnyObject {
    func present()
    func cancel()
}

@MainActor
final class ScreenSelectionOverlayController: NSObject, ScreenSelectionOverlayControlling {
    typealias SelectionHandler = (_ rect: CGRect, _ screen: NSScreen) -> Void
    typealias CancelHandler = () -> Void

    private var overlayWindows: [SelectionOverlayWindow] = []
    private let onSelection: SelectionHandler
    private let onCancel: CancelHandler
    private var isActive = false
    private var cursorPushed = false

    init(onSelection: @escaping SelectionHandler, onCancel: @escaping CancelHandler) {
        self.onSelection = onSelection
        self.onCancel = onCancel
    }

    func present() {
        guard !isActive else { return }
        isActive = true
        NSApp.activate(ignoringOtherApps: true)

        overlayWindows = NSScreen.screens.map { screen in
            let window = SelectionOverlayWindow(screen: screen)
            window.selectionDelegate = self
            window.orderFrontRegardless()
            return window
        }

        // マウス位置と同じ画面のウィンドウをキーにして即時にカーソルを切り替える
        let mouseLocation = NSEvent.mouseLocation
        let activeWindow = overlayWindows.first { window in
            guard let frame = window.screen?.frame else { return false }
            return frame.contains(mouseLocation)
        }

        if let activeWindow {
            activeWindow.makeKeyAndOrderFront(nil)
            activeWindow.flashCursorHighlight(at: mouseLocation)
        } else if let firstWindow = overlayWindows.first {
            firstWindow.makeKeyAndOrderFront(nil)
        }

        if !cursorPushed {
            NSCursor.crosshair.push()
            cursorPushed = true
        }
        NSCursor.crosshair.set()
    }

    func cancel() {
        guard isActive else { return }
        closeAllWindows()
        onCancel()
    }

    private func closeAllWindows() {
        overlayWindows.forEach { window in
            window.selectionDelegate = nil
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        isActive = false

        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
    }
}

// MARK: - SelectionOverlayWindowDelegate

extension ScreenSelectionOverlayController: SelectionOverlayWindowDelegate {
    fileprivate func selectionOverlayWindow(_ window: SelectionOverlayWindow, didSelect rect: CGRect) {
        guard let screen = window.screen else {
            Logger.shared.error("Selection overlay lost screen reference.")
            cancel()
            return
        }
        closeAllWindows()
        onSelection(rect, screen)
    }

    fileprivate func selectionOverlayWindowDidCancel(_ window: SelectionOverlayWindow) {
        closeAllWindows()
        onCancel()
    }
}

// MARK: - SelectionOverlayWindowDelegate

@MainActor
private protocol SelectionOverlayWindowDelegate: AnyObject {
    func selectionOverlayWindow(_ window: SelectionOverlayWindow, didSelect rect: CGRect)
    func selectionOverlayWindowDidCancel(_ window: SelectionOverlayWindow)
}

// MARK: - SelectionOverlayWindow

private final class SelectionOverlayWindow: NSWindow {
    weak var selectionDelegate: SelectionOverlayWindowDelegate?
    private let overlayView: SelectionOverlayView

    init(screen: NSScreen) {
        let screenFrame = screen.frame
        overlayView = SelectionOverlayView(frame: NSRect(origin: .zero, size: screenFrame.size))

        super.init(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        setFrame(screenFrame, display: false)
        contentView?.layer?.contentsScale = screen.backingScaleFactor

        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        overlayView.selectionHandler = { [weak self] rect in
            guard let self else { return }
            let windowRect = self.overlayView.convert(rect, to: nil)
            let screenRect = self.convertToScreen(windowRect)
            selectionDelegate?.selectionOverlayWindow(self, didSelect: screenRect)
        }
        overlayView.cancelHandler = { [weak self] in
            guard let self else { return }
            selectionDelegate?.selectionOverlayWindowDidCancel(self)
        }

        contentView = overlayView
        makeFirstResponder(overlayView)
    }

    func flashCursorHighlight(at screenPoint: NSPoint) {
        let screenRect = NSRect(origin: screenPoint, size: .zero)
        let windowRect = convertFromScreen(screenRect)
        let localPoint = overlayView.convert(windowRect.origin, from: nil)
        overlayView.flashCursorHighlight(at: localPoint)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        // ESCキーでキャンセル
        if event.keyCode == 53 {
            selectionDelegate?.selectionOverlayWindowDidCancel(self)
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - SelectionOverlayView

private final class SelectionOverlayView: NSView {
    var selectionHandler: ((NSRect) -> Void)?
    var cancelHandler: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var selectionRect: NSRect? {
        didSet { needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea?

    private let borderColor = NSColor.systemBlue
    private let fillColor = NSColor.systemBlue.withAlphaComponent(0.15)
    private let dimensionBackground = NSColor.systemBlue.withAlphaComponent(0.9)
    private let dimensionTextColor = NSColor.white

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    func flashCursorHighlight(at point: NSPoint) {
        guard let layer else { return }

        let radius: CGFloat = 36
        let clampedPoint = NSPoint(
            x: max(radius, min(bounds.width - radius, point.x)),
            y: max(radius, min(bounds.height - radius, point.y))
        )

        let highlightLayer = CAShapeLayer()
        highlightLayer.frame = CGRect(
            x: clampedPoint.x - radius,
            y: clampedPoint.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        highlightLayer.path = CGPath(
            ellipseIn: CGRect(origin: .zero, size: CGSize(width: radius * 2, height: radius * 2)),
            transform: nil
        )
        highlightLayer.fillColor = borderColor.withAlphaComponent(0.25).cgColor
        highlightLayer.strokeColor = borderColor.cgColor
        highlightLayer.lineWidth = 2
        highlightLayer.opacity = 0
        highlightLayer.contentsScale = layer.contentsScale

        layer.addSublayer(highlightLayer)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            highlightLayer.removeFromSuperlayer()
        }

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 0.85, 0.0]
        fade.keyTimes = [0.0, 0.4, 1.0]
        fade.duration = 0.8

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.6
        scale.toValue = 1.35
        scale.duration = 0.8

        let group = CAAnimationGroup()
        group.animations = [fade, scale]
        group.duration = 0.8
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        highlightLayer.add(group, forKey: "cursorHighlight")

        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .cursorUpdate]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let rect = selectionRect else { return }

        fillColor.setFill()
        let fillPath = NSBezierPath(rect: rect)
        fillPath.fill()

        borderColor.setStroke()
        let borderPath = NSBezierPath(rect: rect)
        borderPath.lineWidth = 2
        borderPath.stroke()

        // サイズ表示（px換算）
        let scale = window?.backingScaleFactor ?? 1
        let width = Int((rect.width * scale).rounded())
        let height = Int((rect.height * scale).rounded())
        let label = "\(width) × \(height)"

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: dimensionTextColor
        ]
        let textSize = label.size(withAttributes: attributes)
        let padding: CGFloat = 8
        let labelRect = NSRect(
            x: rect.minX,
            y: max(rect.minY - textSize.height - padding, 8),
            width: textSize.width + padding * 2,
            height: textSize.height + padding
        )

        dimensionBackground.setFill()
        let labelPath = NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6)
        labelPath.fill()

        let textRect = NSRect(
            x: labelRect.minX + padding,
            y: labelRect.minY + (labelRect.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        label.draw(in: textRect, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        selectionRect = NSRect(origin: startPoint ?? .zero, size: .zero)
        NSCursor.crosshair.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        currentPoint = convert(event.locationInWindow, from: nil)
        guard let currentPoint else { return }
        selectionRect = rect(from: start, to: currentPoint)
        NSCursor.crosshair.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint else { return }
        let end = convert(event.locationInWindow, from: nil)
        let rect = rect(from: start, to: end)
        selectionRect = nil
        startPoint = nil
        currentPoint = nil

        if rect.width < 2 || rect.height < 2 {
            cancelHandler?()
            return
        }
        selectionHandler?(rect)
    }

    override func rightMouseDown(with event: NSEvent) {
        cancelHandler?()
    }

    override func cancelOperation(_ sender: Any?) {
        cancelHandler?()
    }

    private func rect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.masksToBounds = false
    }
}
