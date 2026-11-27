import AppKit
import ApplicationServices
import Carbon
import SwiftUI

private final class ComparisonWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == kVK_Escape,
           event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]) {
            performClose(nil)
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class TextComparisonWindow {
    enum Content {
        case comparison(TextComparison)
        case accessibilityRequired
        case clipboardUnavailable
        case noClipboardText
        case noSelection
        case unsupportedSelection
        case textTooLong
    }

    static let shared = TextComparisonWindow()
    var openPermissions: (() -> Void)?

    private var window: NSWindow?
    private var task: Task<Void, Never>?

    func compareCurrentSelection(reader: ClipboardReader = .shared, service: ModernClipboardService = .shared) {
        guard task == nil else { return }
        let app = NSWorkspace.shared.frontmostApplication
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
        let targetID = app.processIdentifier
        task = Task { [weak self] in
            guard let self else { return }
            defer { task = nil }
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
            await showResult(result, clipboard: clipboard, placement: target, reader: reader)
        }
    }

    private func showResult(
        _ result: ComparisonClipboardCopy.Result, clipboard: String, placement: TextComparisonWindowPlacement, reader: ClipboardReader
    ) async {
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
            if reader.observation == stamp {
                show(.comparison(comparison), placement: placement)
            }
        case .clipboardUnavailable:
            show(.clipboardUnavailable, placement: placement)
        case .noSelection:
            show(.noSelection, placement: placement)
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
        window.title = AppSettings.shared.localizedString("Compare Text")
        let controller = NSHostingController(rootView: TextComparisonView(content: content) { [weak self] in
            self?.openPermissions?()
        })
        controller.sizingOptions = []
        let size = window.contentLayoutRect.size
        window.contentViewController = controller
        window.setContentSize(size)
        let screens = NSScreen.screens
        let index = placement.screenIndex(in: screens.map(\.frame))
        if let screen = index.map({ screens[$0] }) ?? NSScreen.main {
            window.setFrame(placement.frame(size: window.frame.size, in: screen.visibleFrame), display: false)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = ComparisonWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentMinSize = NSSize(width: 520, height: 280)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
        window.isReleasedWhenClosed = false
        self.window = window
        return window
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
