import XCTest
import AppKit
@testable import Kipple

@MainActor
final class SettingsToolbarControllerTests: XCTestCase {
    func testToolbarSelectionUpdatesViewModelSequentially() {
        let viewModel = SettingsViewModel()
        let controller = SettingsToolbarController(viewModel: viewModel)
        
        controller.toolbar(NSToolbar(identifier: "test"), didSelect: SettingsViewModel.Tab.editor.toolbarIdentifier)
        XCTAssertEqual(viewModel.selectedTab, .editor)

        controller.toolbar(NSToolbar(identifier: "test"), didSelect: SettingsViewModel.Tab.clipboard.toolbarIdentifier)
        XCTAssertEqual(viewModel.selectedTab, .clipboard)
    }

    func testTabChangeDuringLayoutDefersSizingUntilLayoutCompletes() async {
        let viewModel = SettingsViewModel()
        let controller = SettingsToolbarController(viewModel: viewModel)
        let contentView = LayoutObservingView()
        let window = makeWindow(contentView: contentView)
        defer { window.close() }
        controller.attach(to: window)
        await drainMainQueue()

        contentView.onLayout = {
            contentView.measuredSize = NSSize(width: 500, height: 650)
            viewModel.selectedTab = .editor
        }
        contentView.needsLayout = true
        contentView.layoutSubtreeIfNeeded()

        XCTAssertEqual(contentView.recursiveLayoutRequests, 0)
        await drainMainQueue()
        XCTAssertEqual(contentView.frame.size, contentView.measuredSize)
    }

    func testRapidTabChangesSizeWindowOnceUsingLatestContent() async {
        let viewModel = SettingsViewModel()
        let controller = SettingsToolbarController(viewModel: viewModel)
        let contentView = LayoutObservingView()
        let window = makeWindow(contentView: contentView)
        defer { window.close() }
        controller.attach(to: window)
        await drainMainQueue()
        window.contentSizeRequests.removeAll()

        viewModel.selectedTab = .editor
        viewModel.selectedTab = .clipboard
        contentView.measuredSize = NSSize(width: 520, height: 680)
        XCTAssertTrue(window.contentSizeRequests.isEmpty)

        await drainMainQueue()
        XCTAssertEqual(window.contentSizeRequests, [contentView.measuredSize])
        XCTAssertEqual(contentView.frame.size, contentView.measuredSize)
    }

    func testMatchingContentSizeDoesNotResizeTitledWindow() async {
        let viewModel = SettingsViewModel()
        let controller = SettingsToolbarController(viewModel: viewModel)
        let contentView = LayoutObservingView()
        let window = makeWindow(contentView: contentView)
        defer { window.close() }
        controller.attach(to: window)
        await drainMainQueue()
        window.contentSizeRequests.removeAll()

        viewModel.selectedTab = .editor
        await drainMainQueue()

        XCTAssertTrue(window.contentSizeRequests.isEmpty)
    }

    private func makeWindow(contentView: LayoutObservingView) -> SizeRecordingWindow {
        let window = SizeRecordingWindow(
            contentRect: NSRect(origin: .zero, size: contentView.measuredSize),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = contentView
        return window
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor
private final class LayoutObservingView: NSView {
    var measuredSize = NSSize(width: 480, height: 500)
    var onLayout: (() -> Void)?
    private var isInsideLayout = false
    private(set) var recursiveLayoutRequests = 0

    override var fittingSize: NSSize { measuredSize }

    override func layout() {
        isInsideLayout = true
        defer { isInsideLayout = false }
        let action = onLayout
        onLayout = nil
        action?()
        super.layout()
    }

    override func layoutSubtreeIfNeeded() {
        if isInsideLayout { recursiveLayoutRequests += 1 }
        super.layoutSubtreeIfNeeded()
    }
}

@MainActor
private final class SizeRecordingWindow: NSWindow {
    var contentSizeRequests: [NSSize] = []

    override func setContentSize(_ size: NSSize) {
        contentSizeRequests.append(size)
        super.setContentSize(size)
    }
}
