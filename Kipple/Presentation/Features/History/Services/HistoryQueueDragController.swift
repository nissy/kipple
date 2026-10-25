import AppKit
import SwiftUI

@MainActor
final class HistoryQueueDragController: ObservableObject {
    @Published private(set) var itemID: UUID?
    @Published private(set) var previewFrame = CGRect.zero
    @Published private(set) var insertionFrame: CGRect?
    weak var surface: NSView?
    var actions: QueueReorderActions?
    var visibleIDs: [UUID] = []

    private let rows = NSMapTable<NSUUID, NSView>.strongToWeakObjects()
    private var session: QueueReorderSession?
    private var target: QueueReorderTarget?
    private var pointerOffset = CGPoint.zero
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var cursorPushed = false
    private weak var scrollView: NSScrollView?

    func register(_ view: NSView, for id: UUID) {
        rows.setObject(view, forKey: id as NSUUID)
    }

    func unregister(_ view: NSView, for id: UUID) {
        if rows.object(forKey: id as NSUUID) === view {
            rows.removeObject(forKey: id as NSUUID)
        }
    }

    func begin(itemID: UUID, translation: CGSize) {
        guard session == nil, NSEvent.pressedMouseButtons & 1 != 0,
              NSEvent.modifierFlags.isDisjoint(with: [.shift, .command, .option, .control]),
              let surface, let window = surface.window, window.isKeyWindow,
              let row = rows.object(forKey: itemID as NSUUID),
              let session = actions?.begin(itemID) else { return }
        self.session = session
        self.itemID = itemID
        scrollView = row.enclosingScrollView
        previewFrame = row.convert(row.bounds, to: surface)
        let point = mousePoint(in: surface)
        let startPoint = CGPoint(x: point.x - translation.width, y: point.y - translation.height)
        pointerOffset = CGPoint(x: startPoint.x - previewFrame.minX, y: startPoint.y - previewFrame.minY)
        HistoryPopoverManager.shared.hide()
        NSCursor.closedHand.push()
        cursorPushed = true
        startMonitoring(window: window)
        updatePosition()
    }

    func cancel() {
        stopMonitoring()
        session = nil
        target = nil
        itemID = nil
        insertionFrame = nil
        scrollView = nil
    }

    private func startMonitoring(window: NSWindow) {
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp, .keyDown, .flagsChanged, .rightMouseDown]
        ) { [weak self] event in
            var result: NSEvent? = event
            MainActor.assumeIsolated {
                if let self { result = self.handle(event) }
            }
            return result
        }
        let center = NotificationCenter.default
        for (name, object) in [
            (NSApplication.didResignActiveNotification, nil),
            (NSWindow.willCloseNotification, window),
            (NSWindow.didResignKeyNotification, window),
            (Notification.Name.clipboardPasteRequested, nil)
        ] as [(Notification.Name, AnyObject?)] {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDragged:
            updatePosition()
        case .leftMouseUp:
            finish()
        case .keyDown:
            let isEscape = event.keyCode == 53
            cancel()
            if isEscape { return nil }
        case .flagsChanged, .rightMouseDown:
            cancel()
        default:
            break
        }
        return event
    }

    private func tick() {
        guard let session, actions?.isValid(session) == true,
              let surface, surface.window?.isVisible == true else {
            cancel()
            return
        }
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            finish()
            return
        }
        let point = mousePoint(in: surface)
        autoscroll(at: point, in: surface.bounds)
        updatePosition()
    }

    private func mousePoint(in view: NSView) -> CGPoint {
        guard let window = view.window else { return .zero }
        return view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }

    private func updatePosition() {
        guard let session, let surface, actions?.isValid(session) == true else {
            cancel()
            return
        }
        let point = mousePoint(in: surface)
        let previewY = point.y - pointerOffset.y
        if previewFrame.origin.y != previewY { previewFrame.origin.y = previewY }
        let frames = visibleIDs.compactMap { id -> HistoryQueueRowFrame? in
            guard let row = rows.object(forKey: id as NSUUID), row.window != nil else {
                return nil
            }
            return HistoryQueueRowFrame(itemID: id, frame: row.convert(row.bounds, to: surface))
        }
        let destination = HistoryQueueDropGeometry.destination(
            at: point, rows: frames, queue: session.queue, orderedIDs: session.filteredIDs, viewport: surface.bounds
        )
        target = destination?.target
        let line = destination?.line
        if insertionFrame != line { insertionFrame = line }
    }

    private func finish() {
        updatePosition()
        let pending = session
        let destination = target
        let commit = actions?.commit
        cancel()
        if let pending, let destination {
            commit?(pending, destination)
        }
    }

    private func autoscroll(at point: CGPoint, in viewport: CGRect) {
        guard viewport.contains(point), let scrollView, let document = scrollView.documentView else { return }
        let delta = HistoryQueueDropGeometry.scrollDelta(at: point.y, viewport: viewport)
        guard delta != 0 else { return }
        let clip = scrollView.contentView
        let maximum = max(document.bounds.minY, document.bounds.maxY - clip.bounds.height)
        let change = document.isFlipped ? delta : -delta
        let newY = min(maximum, max(document.bounds.minY, clip.bounds.minY + change))
        guard newY != clip.bounds.minY else { return }
        clip.scroll(to: CGPoint(x: clip.bounds.minX, y: newY))
        scrollView.reflectScrolledClipView(clip)
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        timer?.invalidate()
        timer = nil
        if cursorPushed { NSCursor.pop() }
        cursorPushed = false
    }

    deinit {
        MainActor.assumeIsolated { stopMonitoring() }
    }
}

struct HistoryQueueRowFrame {
    let itemID: UUID
    let frame: CGRect
}

enum HistoryQueueDropGeometry {
    struct Destination {
        let target: QueueReorderTarget
        let line: CGRect
    }

    static func destination(
        at point: CGPoint, rows: [HistoryQueueRowFrame], queue: [UUID], orderedIDs: [UUID], viewport: CGRect
    ) -> Destination? {
        guard viewport.contains(point) else { return nil }
        let visible = rows.filter { $0.frame.intersects(viewport) }.sorted { $0.frame.minY < $1.frame.minY }
        guard let firstVisible = visible.first else { return nil }
        let queued = Set(queue)
        let queueRows = visible.filter { queued.contains($0.itemID) }
        guard let first = queueRows.first, let last = queueRows.last else {
            if let lastQueuedIndex = orderedIDs.lastIndex(where: { queued.contains($0) }) {
                guard let firstVisibleIndex = orderedIDs.firstIndex(of: firstVisible.itemID),
                      firstVisibleIndex > lastQueuedIndex else { return nil }
            }
            return Destination(
                target: .end,
                line: insertionLine(at: firstVisible.frame.minY, row: firstVisible.frame, viewport: viewport)
            )
        }
        if last.itemID == orderedIDs.last(where: { queued.contains($0) }), point.y >= last.frame.midY {
            return Destination(
                target: .end,
                line: insertionLine(at: last.frame.maxY, row: last.frame, viewport: viewport)
            )
        }
        guard point.y >= first.frame.minY - 4, point.y <= last.frame.maxY + 4 else { return nil }
        guard let row = queueRows.min(by: {
            abs($0.frame.midY - point.y) < abs($1.frame.midY - point.y)
        }) else { return nil }
        let after = point.y >= row.frame.midY
        return Destination(
            target: QueueReorderTarget(itemID: row.itemID, insertAfter: after),
            line: insertionLine(at: after ? row.frame.maxY : row.frame.minY, row: row.frame, viewport: viewport)
        )
    }

    private static func insertionLine(at position: CGFloat, row: CGRect, viewport: CGRect) -> CGRect {
        let height = min(2, viewport.height)
        let position = min(max(viewport.minY, position - 1), viewport.maxY - height)
        return CGRect(x: row.minX, y: position, width: row.width, height: height)
    }

    static func scrollDelta(at position: CGFloat, viewport: CGRect) -> CGFloat {
        let edge: CGFloat = min(24, viewport.height / 3)
        if position < viewport.minY + edge { return -(viewport.minY + edge - position) * 0.5 }
        if position > viewport.maxY - edge { return (position - viewport.maxY + edge) * 0.5 }
        return 0
    }
}
