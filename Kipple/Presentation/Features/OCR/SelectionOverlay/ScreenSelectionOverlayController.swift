//
//  ScreenSelectionOverlayController.swift
//  Kipple
//
//  Created by Kipple on 2025/10/09.
//

import AppKit

@MainActor
final class ScreenSelectionOverlayController: NSObject {
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

        // 最初のウィンドウをキーにしてキーボードイベントを受け付ける
        overlayWindows.first?.makeKeyAndOrderFront(nil)

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
        if let backingScale = screen.backingScaleFactor as CGFloat? {
            contentView?.layer?.contentsScale = backingScale
        }

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

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

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
        selectionRect = rect(from: start, to: currentPoint!)
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
}
