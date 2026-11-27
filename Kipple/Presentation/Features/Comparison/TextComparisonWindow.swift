import AppKit
import ApplicationServices
import Carbon
import SwiftUI

private final class ComparisonWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == kVK_Escape,
           event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]) {
            close()
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class TextComparisonWindow: NSObject, NSWindowDelegate {
    enum Content {
        case comparison(TextComparison)
        case accessibilityRequired
        case clipboardUnavailable
        case clipboardBackupUnavailable
        case noClipboardText
        case noSelection
        case selectionCopyFailed
        case unsupportedSelection
        case textTooLong
    }

    static let shared = TextComparisonWindow()
    var openPermissions: (() -> Void)?

    private var window: NSWindow?
    private var task: Task<Void, Never>?
    private var deferredComparison: (() -> Void)?
    private var previousFocus: ComparisonFocusTarget?
    private var restoreFocusTask: Task<Void, Never>?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?

    func compareCurrentSelection(reader: ClipboardReader = .shared, service: ModernClipboardService = .shared) {
        if NSApp.isActive, window?.isKeyWindow == true { return }
        let app = NSWorkspace.shared.frontmostApplication
        if task != nil {
            let requestedProcess = app?.processIdentifier
            deferredComparison = { [weak self] in
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == requestedProcess else { return }
                self?.compareCurrentSelection(reader: reader, service: service)
            }
            return
        }
        let placement = TextComparisonWindowPlacement.capture(for: app)
        guard AXIsProcessTrusted() else {
            show(.accessibilityRequired, placement: placement)
            return
        }
        guard let snapshot = reader.read(retry: reader.readFailed) else {
            show(.clipboardUnavailable, placement: placement)
            return
        }
        guard let clipboard = snapshot.text, !clipboard.isEmpty else {
            show(.noClipboardText, placement: placement)
            return
        }
        guard ClipboardTextLimit.allows(clipboard) else {
            show(.textTooLong, placement: placement)
            return
        }
        guard let app else {
            show(.noSelection, placement: placement)
            return
        }
        let stamp = snapshot.stamp
        task = Task { [weak self] in
            await self?.compare(
                in: app, clipboard: clipboard, stamp: stamp, reader: reader, service: service, placement: placement
            )
        }
    }

    private func compare(
        in app: NSRunningApplication,
        clipboard: String,
        stamp: ClipboardReader.Stamp,
        reader: ClipboardReader,
        service: ModernClipboardService,
        placement: TextComparisonWindowPlacement
    ) async {
        defer { finishComparison() }
        let targetID = app.processIdentifier
        let input = await ClipboardReader.comparisonInput(in: app)
        guard reader.observation == stamp,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetID else { return }
        guard let input else {
            show(.noSelection, placement: placement)
            return
        }
        let result = await service.performClipboardComparison(at: stamp) {
            await ComparisonClipboardCopy.capture(reader: reader, stamp: stamp, input: input, target: targetID)
        }
        let target = placement.withWindowBounds(input.windowBounds)
        await showResult(result, clipboard: clipboard, placement: target, sourceID: targetID, reader: reader)
    }

    private func finishComparison() {
        task = nil
        let next = deferredComparison
        deferredComparison = nil
        next?()
    }

    private func showResult(
        _ result: ComparisonClipboardCopy.Result,
        clipboard: String,
        placement: TextComparisonWindowPlacement,
        sourceID: pid_t,
        reader: ClipboardReader
    ) async {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == sourceID else { return }
        switch result {
        case let .restored(selection, stamp, interrupted):
            guard !interrupted, reader.observation == stamp else { return }
            guard ClipboardTextLimit.allows(selection) else {
                show(.textTooLong, placement: placement)
                return
            }
            let comparison = await Task.detached(priority: .userInitiated) {
                TextComparison(clipboard: clipboard, selection: selection)
            }.value
            if reader.observation == stamp, NSWorkspace.shared.frontmostApplication?.processIdentifier == sourceID {
                show(.comparison(comparison), placement: placement)
            }
        case .clipboardUnavailable:
            show(.clipboardUnavailable, placement: placement)
        case .clipboardBackupUnavailable:
            show(.clipboardBackupUnavailable, placement: placement)
        case .noSelection:
            show(.selectionCopyFailed, placement: placement)
        case .unsupportedSelection:
            show(.unsupportedSelection, placement: placement)
        case .interrupted:
            break
        }
    }

    func show(
        _ content: Content,
        placement: TextComparisonWindowPlacement = .capture(for: NSWorkspace.shared.frontmostApplication)
    ) {
        let window = window ?? makeWindow()
        restoreFocusTask?.cancel()
        if !NSApp.isActive || !window.isKeyWindow {
            previousFocus = ComparisonFocusTarget.capture(excluding: window)
        }
        window.title = AppSettings.shared.localizedString("Compare Text")
        let controller = KippleGlassContentController(rootView: TextComparisonView(content: content) { [weak self] in
            guard let self, let openPermissions else { return }
            previousFocus = nil
            self.window?.close()
            openPermissions()
        } closeAfterCopy: { [weak window] in
            window?.close()
        })
        let size = window.frame.size
        window.contentViewController = controller
        window.setContentSize(size)
        let screens = NSScreen.screens
        let index = placement.screenIndex(in: screens.map(\.frame))
        if let screen = index.map({ screens[$0] }) ?? NSScreen.main {
            window.setFrame(placement.frame(size: window.frame.size, in: screen.visibleFrame), display: false)
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        observeOutsideClicks()
    }

    private func observeOutsideClicks() {
        guard localClickMonitor == nil, globalClickMonitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            if let self, let window, event.window !== window, event.window?.sheetParent !== window {
                dismissAfterOutsideClick()
            }
            return event
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.dismissAfterOutsideClick()
        }
    }

    private func dismissAfterOutsideClick() {
        guard let window, window.isVisible, !window.isMiniaturized else { return }
        window.close()
    }

    private func stopObservingOutsideClicks() {
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        localClickMonitor = nil
        globalClickMonitor = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopObservingOutsideClicks()
        guard let target = previousFocus else { return }
        previousFocus = nil
        restoreFocusTask = Task {
            guard !Task.isCancelled else { return }
            target.restore()
        }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        stopObservingOutsideClicks()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        observeOutsideClicks()
    }

    private func makeWindow() -> NSWindow {
        let window = ComparisonWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 460),
            styleMask: [.borderless, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = NSSize(width: 520, height: 280)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
    }
}

@MainActor
private enum ComparisonFocusTarget {
    case local(NSWindow)
    case external(NSRunningApplication, AXUIElement?)

    static func capture(excluding comparisonWindow: NSWindow) -> Self? {
        if NSApp.isActive {
            guard let window = NSApp.keyWindow, window !== comparisonWindow else { return nil }
            return .local(window)
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        guard AXIsProcessTrusted() else { return .external(app, nil) }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.10)
        let window = ClipboardReader.accessibilityElement(kAXFocusedWindowAttribute, on: application)
        return .external(app, window)
    }

    func restore() {
        switch self {
        case .local(let window):
            guard NSApp.windows.contains(window) else { return }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        case let .external(app, window):
            guard !app.isTerminated else { return }
            if !app.isActive {
                if NSApp.isActive { NSApp.yieldActivation(to: app) }
                app.activate(options: [])
            }
            if let window {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }
        }
    }
}

struct TextComparisonWindowPlacement {
    let sourceFrame: CGRect?
    let pointer: CGPoint

    @MainActor
    static func capture(for app: NSRunningApplication?) -> Self {
        let source = app.flatMap { app in
            app.processIdentifier == ProcessInfo.processInfo.processIdentifier
                ? NSApp.keyWindow?.frame
                : frontWindowBounds(for: app.processIdentifier).flatMap(appKitFrame)
        }
        return Self(sourceFrame: source, pointer: NSEvent.mouseLocation)
    }

    @MainActor
    func withWindowBounds(_ bounds: CGRect?) -> Self {
        guard let frame = bounds.flatMap(Self.appKitFrame) else { return self }
        return Self(sourceFrame: frame, pointer: pointer)
    }

    func screenIndex(in screens: [CGRect]) -> Int? {
        if let sourceFrame {
            let overlapping = screens.indices.filter { screens[$0].intersects(sourceFrame) }
            if let best = overlapping.max(by: { area(screens[$0], sourceFrame) < area(screens[$1], sourceFrame) }) {
                return best
            }
        }
        return screens.firstIndex { $0.contains(pointer) }
    }

    func frame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let center = sourceFrame.flatMap { $0.intersects(visibleFrame) ? $0 : nil } ?? visibleFrame
        let width = min(size.width, visibleFrame.width)
        let height = min(size.height, visibleFrame.height)
        return CGRect(
            x: min(max(center.midX - width / 2, visibleFrame.minX), visibleFrame.maxX - width),
            y: min(max(center.midY - height / 2, visibleFrame.minY), visibleFrame.maxY - height),
            width: width,
            height: height
        )
    }

    private func area(_ screen: CGRect, _ window: CGRect) -> CGFloat {
        let intersection = screen.intersection(window)
        return intersection.width * intersection.height
    }

    @MainActor
    private static func appKitFrame(from bounds: CGRect) -> CGRect? {
        guard let primaryScreenTop = NSScreen.screens.first?.frame.maxY else { return nil }
        // Window Server and Accessibility use the top-left of the primary display as their origin.
        return CGRect(x: bounds.minX, y: primaryScreenTop - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    private static func frontWindowBounds(for pid: pid_t) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for window in windows {
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  !frame.isEmpty else { continue }
            return frame
        }
        return nil
    }
}
