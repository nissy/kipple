//
//  WindowManager.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI
import AppKit
import Combine
import Darwin

private typealias ScreenUpdateFunction = @convention(c) () -> Void

// swiftlint:disable file_length
private final class MainGlassWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class RoundedMaskContainerView: NSView {
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
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
}

@available(macOS 26.0, *)
private final class MainGlassContentController<Content: View>: NSViewController {
    private let hostingController: NSHostingController<Content>

    init(rootView: Content) {
        hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = []
        super.init(nibName: nil, bundle: nil)
        addChild(hostingController)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = RoundedMaskContainerView(cornerRadius: KippleGlassMetrics.windowCornerRadius)

        let glassView = NSGlassEffectView()
        glassView.style = .regular
        glassView.cornerRadius = KippleGlassMetrics.windowCornerRadius
        glassView.tintColor = nil
        glassView.translatesAutoresizingMaskIntoConstraints = false
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = KippleGlassMetrics.windowCornerRadius
        glassView.layer?.cornerCurve = .continuous
        glassView.layer?.masksToBounds = true

        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.layer?.cornerRadius = KippleGlassMetrics.windowCornerRadius
        hostingController.view.layer?.cornerCurve = .continuous
        hostingController.view.layer?.masksToBounds = true
        glassView.contentView = hostingController.view
        container.addSubview(glassView)
        NSLayoutConstraint.activate([
            glassView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            glassView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            glassView.topAnchor.constraint(equalTo: container.topAnchor),
            glassView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        view = container
    }
}

private final class MainMaterialContentController<Content: View>: NSViewController {
    private let hostingController: NSHostingController<Content>

    init(rootView: Content) {
        hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = []
        super.init(nibName: nil, bundle: nil)
        addChild(hostingController)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = RoundedMaskContainerView(cornerRadius: KippleGlassMetrics.windowCornerRadius)

        let materialView = NSVisualEffectView()
        materialView.blendingMode = .behindWindow
        materialView.material = .popover
        materialView.state = .active
        materialView.translatesAutoresizingMaskIntoConstraints = false
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = KippleGlassMetrics.windowCornerRadius
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true

        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(hostingController.view)
        container.addSubview(materialView)
        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            materialView.topAnchor.constraint(equalTo: container.topAnchor),
            materialView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: materialView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: materialView.bottomAnchor)
        ])

        view = container
    }
}

@MainActor
protocol WindowManaging: AnyObject {
    func openMainWindow()
    func showCopiedNotification()
}

extension Notification.Name {
    static let showCopiedNotification = Notification.Name("showCopiedNotification")
    static let mainWindowDidBecomeKey = Notification.Name("KippleMainWindowDidBecomeKey")
    static let mainWindowDidResignKey = Notification.Name("KippleMainWindowDidResignKey")
    static let mainWindowDidHide = Notification.Name("KippleMainWindowDidHide")
}

@MainActor
// swiftlint:disable:next type_body_length
final class WindowManager: NSObject, NSWindowDelegate {
    private static let rtldDefaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
    private static let disableGlobalScreenUpdates: ScreenUpdateFunction? =
        WindowManager.resolveScreenUpdateFunction(named: "NSDisableScreenUpdates")
    private static let enableGlobalScreenUpdates: ScreenUpdateFunction? =
        WindowManager.resolveScreenUpdateFunction(named: "NSEnableScreenUpdates")

    private static func resolveScreenUpdateFunction(named name: String) -> ScreenUpdateFunction? {
        guard
            let handle = rtldDefaultHandle,
            let symbol = dlsym(handle, name)
        else {
            return nil
        }
        return unsafeBitCast(symbol, to: ScreenUpdateFunction.self)
    }

    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var settingsCoordinator: SettingsToolbarController?
    private var settingsViewModel: SettingsViewModel?
    private var mainViewModel: MainViewModel?
    private let lastActiveAppTracker: LastActiveAppTracking
    private let titleBarState = MainWindowTitleBarState()
    private var titleBarLeftHostingView: NSHostingView<MainViewTitleBarAccessory>?
    private var titleBarPinHostingView: NSHostingView<MainViewTitleBarPinButton>?
    private let appSettings = AppSettings.shared
    private var appToRestoreAfterClose: LastActiveAppTracker.AppInfo?
    private var localizationCancellable: AnyCancellable?
    private var pendingAppReactivation: DispatchWorkItem?
    private let appReactivationDelay: TimeInterval
    private weak var cachedEditorTextView: LiveEditorTextView?
    private let maxFocusedEditorTailSelectionLength = 10_000
    private var isAlwaysOnTop = false {
        didSet {
            if let window = mainWindow {
                window.level = isAlwaysOnTop ? .floating : .normal
                // M2 Mac対応: hidesOnDeactivateも更新
                window.hidesOnDeactivate = !isAlwaysOnTop
            }
            titleBarState.isAlwaysOnTop = isAlwaysOnTop
        }
    }
    private var preventAutoClose = false
    
    // Observers
    private var windowObserver: NSObjectProtocol?
    private var windowResignObserver: NSObjectProtocol?
    private var windowResizeObserver: NSObjectProtocol?
    private var appDidResignActiveObserver: NSObjectProtocol?
    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var aboutObserver: NSObjectProtocol?
    var onTextCaptureRequested: (() -> Void)?
    // オープン処理中フラグ（フォーカス喪失時の自動クローズを抑止）
    private var isOpening: Bool = false

    // 現在の前面アプリを後で復帰するために記録（NSApp.activate前にも使用）
    @MainActor
    func rememberFrontmostAppForRestore() {
        if let candidate = preferredRestoreCandidate() {
            appToRestoreAfterClose = candidate
            lastActiveAppTracker.updateLastActiveApp(candidate)
        }
    }

    // メニューバー経路などでアクティベート直前に呼び出し、
    // OSの自動再表示（旧位置一瞬表示）を抑止するための準備
    @MainActor
    func prepareForActivationBeforeOpen() {
        let style = UserDefaults.standard.string(forKey: "windowAnimation") ?? "none"
        guard style != "none" else { return }
        if let window = mainWindow {
            window.orderOut(nil)
        }
    }

    override convenience init() {
        self.init(lastActiveAppTracker: LastActiveAppTracker.shared)
    }

    init(
        lastActiveAppTracker: LastActiveAppTracking,
        // orderOut が MainActor を ~100ms 占有する間に pasteboard 書き込みが完走するための
        // safety buffer。0 にすると orderOut 直後の MainActor 解放時に reactivate と pasteboard が
        // 競合し、即 paste で古い内容を貼るリスクが出る
        appReactivationDelay: TimeInterval = 0.05
    ) {
        self.lastActiveAppTracker = lastActiveAppTracker
        self.appReactivationDelay = appReactivationDelay
        super.init()
        localizationCancellable = appSettings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateLocalization()
            }
    }
    
    // MARK: - Main Window
    
    @MainActor
    func openMainWindow() {
        let startedAt = PerformanceTrace.nowMicros()
        PerformanceTrace.event("main_window_open_requested")
        cancelPendingAppReactivation()
        isOpening = true
        preventAutoClose = true
        capturePreviousAppForFocusReturn()
        syncTitleBarQueueState()
        NSApp.activate(ignoringOtherApps: true)

        if let existingWindow = mainWindow {
            reopenExistingWindow(existingWindow, requestedAt: startedAt)
            return
        }

        openNewWindow(requestedAt: startedAt)
    }

    private func reopenExistingWindow(_ window: NSWindow, requestedAt: Int64) {
        let startedAt = PerformanceTrace.nowMicros()
        PerformanceTrace.event(
            "main_window_reopen_started",
            details: [
                "isVisible": "\(window.isVisible)",
                "sinceRequestUs": "\(startedAt - requestedAt)"
            ]
        )
        if window.isMiniaturized { window.deminiaturize(nil) }

        let target = computeOriginAtCursor(for: window)
        if !window.isVisible {
            showHiddenExistingWindow(window, at: target, startedAt: startedAt)
        } else {
            if moveVisibleExistingWindow(window, to: target, startedAt: startedAt) {
                completeOpen()
                return
            }
        }

        completeOpen()
    }

    private func showHiddenExistingWindow(_ window: NSWindow, at target: NSPoint, startedAt: Int64) {
        // None: 非表示→表示でも隠し直さず即位置決定
        window.setFrameOrigin(target)
        let style = UserDefaults.standard.string(forKey: "windowAnimation") ?? "none"
        applyAnimationBehavior(style: style, to: window)
        if style == "none" {
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            bringWindowToFrontWithoutSystemAnimation(window) {
                window.alphaValue = 1.0
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
            PerformanceTrace.event(
                "main_window_reopen_visible",
                details: ["durationUs": "\(PerformanceTrace.nowMicros() - startedAt)"]
            )
            DispatchQueue.main.async { [weak self] in
                self?.focusOnEditor()
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.alphaValue = 0
            animateWindowOpen(window)
        }
    }

    @discardableResult
    private func moveVisibleExistingWindow(_ window: NSWindow, to target: NSPoint, startedAt: Int64) -> Bool {
        let style = UserDefaults.standard.string(forKey: "windowAnimation") ?? "none"
        applyAnimationBehavior(style: style, to: window)
        if style == "none" {
            var frame = window.frame
            frame.origin = target
            window.setFrame(frame, display: true, animate: false)
            if !window.isKeyWindow {
                bringWindowToFrontWithoutSystemAnimation(window) {
                    window.orderFrontRegardless()
                    window.makeKeyAndOrderFront(nil)
                }
            }
            PerformanceTrace.event(
                "main_window_repositioned",
                details: ["durationUs": "\(PerformanceTrace.nowMicros() - startedAt)"]
            )
            DispatchQueue.main.async { [weak self] in
                self?.focusOnEditor()
            }
            return true
        }

        // アニメあり: 旧位置を見せないため一旦隠し、選択されたスタイルで再表示
        window.orderOut(nil)
        window.setFrameOrigin(target)
        NSApp.activate(ignoringOtherApps: true)
        animateWindowOpen(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in self?.focusOnEditor() }
        return false
    }

    private func openNewWindow(requestedAt: Int64) {
        let startedAt = PerformanceTrace.nowMicros()
        PerformanceTrace.event(
            "main_window_new_started",
            details: ["sinceRequestUs": "\(startedAt - requestedAt)"]
        )
        let optional = createMainWindow()
        guard let window = optional else { return }
        configureMainWindow(window)
        setupMainWindowObservers(window)
        let target = computeOriginAtCursor(for: window)
        window.setFrameOrigin(target)
        NSApp.activate(ignoringOtherApps: true)
        animateWindowOpen(window)
        PerformanceTrace.event(
            "main_window_new_visible",
            details: ["durationUs": "\(PerformanceTrace.nowMicros() - startedAt)"]
        )
        completeOpen()
    }

    private func completeOpen() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.isOpening = false
            self?.preventAutoClose = false
        }
    }
    
    @MainActor
    private func createMainWindow() -> NSWindow? {
        // MainViewModelを作成または再利用
        let viewModel = mainViewModel ?? MainViewModel()
        mainViewModel = viewModel
        syncTitleBarQueueState()
        
        let contentView = MainView(
            titleBarState: titleBarState,
            onClose: { [weak self] in
                self?.hideMainWindowWithoutDestroying()
            },
            onReactivatePreviousApp: { [weak self] in
                self?.reactivatePreviousAppIfPossible()
            },
            onAlwaysOnTopChanged: { [weak self] isOnTop in
                self?.isAlwaysOnTop = isOnTop
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
            },
            onOpenAbout: { [weak self] in
                self?.showAbout()
            },
            onQuitApplication: {
                NSApplication.shared.terminate(nil)
            },
            onSetPreventAutoClose: { [weak self] flag in
                self?.setPreventAutoClose(flag)
            },
            onStartTextCapture: { [weak self] in
                self?.onTextCaptureRequested?()
            }
        )
        .environmentObject(viewModel)
        
        if #available(macOS 26.0, *) {
            mainWindow = MainGlassWindow(contentViewController: MainGlassContentController(rootView: contentView))
        } else {
            mainWindow = MainGlassWindow(contentViewController: MainMaterialContentController(rootView: contentView))
        }
        return mainWindow
    }
    
    private func configureMainWindow(_ window: NSWindow) {
        // ウィンドウの基本設定
        window.title = localizedMainWindowTitle()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.styleMask = [.borderless, .resizable]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = isAlwaysOnTop ? .floating : .normal
        // M2 Mac対応: hidesOnDeactivateを動的に設定
        window.hidesOnDeactivate = !isAlwaysOnTop
        // 常に現在アクティブなスペースで開くようにする
        if !window.collectionBehavior.contains(.moveToActiveSpace) {
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
        
        // ツールバーボタンを無効化（×ボタン以外を非表示）
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = true
        
        // デリゲートを設定
        window.delegate = self
        
        // ウィンドウサイズの設定
        configureWindowSize(window)
        
        // カーソル位置にウィンドウを配置
        if window.styleMask.contains(.titled) {
            attachAlwaysOnTopButton(to: window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                self?.attachAlwaysOnTopButton(to: window)
            }
        }
        positionWindowAtCursor(window)
    }

    private func hideMainWindowWithoutDestroying() {
        guard let window = mainWindow, window.isVisible else { return }
        exitQueueModeIfNeededBeforeAutoHide()
        window.orderOut(nil)
        HistoryPopoverManager.shared.forceClose()
        NotificationCenter.default.post(name: .mainWindowDidHide, object: nil)
    }

    private func setPreventAutoClose(_ flag: Bool) {
        preventAutoClose = flag
        guard flag else { return }
        capturePreviousAppForFocusReturn()
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }
    
    private func configureWindowSize(_ window: NSWindow) {
        let defaults = UserDefaults.standard
        let savedHeight = defaults.double(forKey: "windowHeight")
        let savedWidth = defaults.double(forKey: "windowWidth")
        let minimumSize = KippleGlassMetrics.mainWindowMinimumSize
        let maximumSize = KippleGlassMetrics.mainWindowMaximumSize
        let defaultSize = KippleGlassMetrics.mainWindowDefaultSize
        let shouldResetSavedSize = shouldResetOversizedMainWindow(
            savedWidth: savedWidth,
            savedHeight: savedHeight,
            defaults: defaults
        )
        let resolvedWidth = clamp(
            savedWidth > 0 && !shouldResetSavedSize ? CGFloat(savedWidth) : defaultSize.width,
            min: minimumSize.width,
            max: maximumSize.width
        )
        let resolvedHeight = clamp(
            savedHeight > 0 && !shouldResetSavedSize ? CGFloat(savedHeight) : defaultSize.height,
            min: minimumSize.height,
            max: maximumSize.height
        )
        window.contentMinSize = minimumSize
        window.contentMaxSize = maximumSize
        window.minSize = minimumSize
        window.maxSize = maximumSize
        window.setContentSize(NSSize(width: resolvedWidth, height: resolvedHeight))
    }

    private func shouldResetOversizedMainWindow(
        savedWidth: Double,
        savedHeight: Double,
        defaults: UserDefaults
    ) -> Bool {
        let migrationKey = "mainWindowOversizedSizeMigrated"
        guard !defaults.bool(forKey: migrationKey) else {
            return false
        }

        let threshold = KippleGlassMetrics.mainWindowOversizedMigrationThreshold
        let isOversized = savedWidth >= threshold.width || savedHeight >= threshold.height
        defaults.set(true, forKey: migrationKey)
        guard isOversized else {
            return false
        }

        let defaultSize = KippleGlassMetrics.mainWindowDefaultSize
        defaults.set(defaultSize.width, forKey: "windowWidth")
        defaults.set(defaultSize.height, forKey: "windowHeight")
        return true
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimumSize = KippleGlassMetrics.mainWindowMinimumSize
        let maximumSize = KippleGlassMetrics.mainWindowMaximumSize
        var adjustedSize = frameSize
        adjustedSize.width = clamp(adjustedSize.width, min: minimumSize.width, max: maximumSize.width)
        adjustedSize.height = clamp(adjustedSize.height, min: minimumSize.height, max: maximumSize.height)
        return adjustedSize
    }

    private func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }
    
    private func attachAlwaysOnTopButton(to window: NSWindow) {
        titleBarLeftHostingView?.removeFromSuperview()
        titleBarPinHostingView?.removeFromSuperview()
        
        guard let titlebarContainer = window.standardWindowButton(.closeButton)?.superview?.superview else {
            Logger.shared.warning("Failed to locate titlebar container for pin button")
            return
        }
        
        let leftView = NSHostingView(rootView: MainViewTitleBarAccessory(state: titleBarState))
        leftView.translatesAutoresizingMaskIntoConstraints = false
        leftView.wantsLayer = true
        leftView.layer?.backgroundColor = NSColor.clear.cgColor
        leftView.layer?.zPosition = 1
        leftView.setContentHuggingPriority(.required, for: .horizontal)
        leftView.setContentCompressionResistancePriority(.required, for: .horizontal)
        leftView.isHidden = false

        titlebarContainer.addSubview(leftView, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            leftView.leadingAnchor.constraint(equalTo: titlebarContainer.leadingAnchor, constant: 6),
            leftView.topAnchor.constraint(equalTo: titlebarContainer.topAnchor, constant: 6),
            leftView.heightAnchor.constraint(equalToConstant: 34)
        ])

        let pinView = NSHostingView(rootView: MainViewTitleBarPinButton(state: titleBarState))
        pinView.translatesAutoresizingMaskIntoConstraints = false
        pinView.wantsLayer = true
        pinView.layer?.backgroundColor = NSColor.clear.cgColor
        pinView.layer?.zPosition = 1
        pinView.setContentHuggingPriority(.required, for: .horizontal)
        pinView.setContentCompressionResistancePriority(.required, for: .horizontal)
        pinView.isHidden = false

        titlebarContainer.addSubview(pinView, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            pinView.trailingAnchor.constraint(equalTo: titlebarContainer.trailingAnchor, constant: -6),
            pinView.topAnchor.constraint(equalTo: titlebarContainer.topAnchor, constant: 6),
            pinView.heightAnchor.constraint(equalToConstant: 34),
            pinView.widthAnchor.constraint(greaterThanOrEqualToConstant: 34)
        ])

        titleBarLeftHostingView = leftView
        titleBarPinHostingView = pinView
    }
    
    private func positionWindowAtCursor(_ window: NSWindow) {
        let origin = computeOriginAtCursor(for: window)
        window.setFrameOrigin(origin)
    }

    private func computeOriginAtCursor(for window: NSWindow) -> NSPoint {
        let mouseLocation = NSEvent.mouseLocation
        let windowSize = window.frame.size
        // カーソルが存在するスクリーンを優先（複数ディスプレイ対応）
        let screens = NSScreen.screens
        let targetScreen = screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        let screenFrame = targetScreen?.visibleFrame ?? targetScreen?.frame ?? NSRect.zero
        return Self.constrainedWindowOrigin(
            mouseLocation: mouseLocation,
            windowSize: windowSize,
            screenFrame: screenFrame
        )
    }

    nonisolated static func constrainedWindowOrigin(
        mouseLocation: NSPoint,
        windowSize: NSSize,
        screenFrame: NSRect
    ) -> NSPoint {
        let padding: CGFloat = 10
        var windowOrigin = NSPoint(
            x: mouseLocation.x + padding,
            y: mouseLocation.y - windowSize.height - padding
        )

        let minX = screenFrame.minX + padding
        let maxX = max(minX, screenFrame.maxX - windowSize.width - padding)
        windowOrigin.x = min(max(windowOrigin.x, minX), maxX)

        let minY = screenFrame.minY + padding
        let maxY = max(minY, screenFrame.maxY - windowSize.height - padding)
        if windowOrigin.y < minY {
            windowOrigin.y = mouseLocation.y + padding
        }
        windowOrigin.y = min(max(windowOrigin.y, minY), maxY)

        return windowOrigin
    }

    private func capturePreviousAppForFocusReturn() {
        if let candidate = preferredRestoreCandidate() {
            appToRestoreAfterClose = candidate
        }
    }

    /// 現在/最後に非Kippleだったアプリのうち復帰候補を決定
    private func preferredRestoreCandidate() -> LastActiveAppTracker.AppInfo? {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return LastActiveAppTracker.AppInfo(
                name: front.localizedName,
                bundleId: front.bundleIdentifier,
                pid: front.processIdentifier
            )
        }

        let candidate = lastActiveAppTracker.getSourceAppInfo()
        let isValidPID = candidate.pid != 0
        let hasBundle = candidate.bundleId != nil
        let isKipple = candidate.bundleId == Bundle.main.bundleIdentifier
        if (isValidPID || hasBundle) && !isKipple {
            return candidate
        }
        return nil
    }

    private func cancelPendingAppReactivation() {
        pendingAppReactivation?.cancel()
        pendingAppReactivation = nil
    }

    private func reactivatePreviousAppIfPossible() {
        guard let target = appToRestoreAfterClose else {
            lastActiveAppTracker.activateLastTrackedAppIfAvailable()
            return
        }
        appToRestoreAfterClose = nil
        pendingAppReactivation?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingAppReactivation = nil
            let didActivate = self.activateAppInfoIfPossible(target)

            if !didActivate {
                self.lastActiveAppTracker.activateLastTrackedAppIfAvailable()
            }
        }
        pendingAppReactivation = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + appReactivationDelay, execute: workItem)
    }

    private func activateAppInfoIfPossible(_ info: LastActiveAppTracker.AppInfo) -> Bool {
        // .activateAllWindows は「全ウインドウを前面」指定で、複数ウインドウアプリだと
        // 期待しない (前回 key じゃない) ウインドウまで前面に出るケースが報告されている。
        // default ([]) なら main/key window のみ復帰され、ユーザーが直前に使っていた
        // ウインドウが key に戻りやすい
        if info.pid != 0,
           let running = NSRunningApplication(processIdentifier: info.pid) {
            running.activate(options: [])
            return true
        }
        if let bundleId = info.bundleId {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if let app = apps.first {
                app.activate(options: [])
                return true
            }
        }
        return false
    }
    
    private func animateWindowOpen(_ window: NSWindow) {
        let animationType = UserDefaults.standard.string(forKey: "windowAnimation") ?? "none"
        applyAnimationBehavior(style: animationType, to: window)

        switch animationType {
        case "slide":
            animateSlide(window)
        case "none":
            bringWindowToFrontWithoutSystemAnimation(window) {
                NSApp.activate(ignoringOtherApps: true)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
            DispatchQueue.main.async { [weak self] in
                self?.focusOnEditor()
            }
        default: // "fade"
            animateFade(window)
        }
        // 前面化のフォロー（取りこぼし対策）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak window] in
            guard let self, let window else { return }
            if !window.isKeyWindow {
                let style = UserDefaults.standard.string(forKey: "windowAnimation") ?? "none"
                if style == "none" {
                    self.bringWindowToFrontWithoutSystemAnimation(window) {
                        NSApp.activate(ignoringOtherApps: true)
                        window.orderFrontRegardless()
                        window.makeKeyAndOrderFront(nil)
                    }
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    window.orderFrontRegardless()
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
    
    private func animateFade(_ window: NSWindow) {
        window.alphaValue = 0
        suppressSystemShowAnimation(on: window) {
            window.makeKeyAndOrderFront(nil)
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            window.animator().alphaValue = 1.0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.focusOnEditor()
            }
        }
    }

    private func applyAnimationBehavior(style: String, to window: NSWindow) {
        if style == "none" {
            window.animationBehavior = .none
        } else {
            window.animationBehavior = .default
        }
    }

    private func bringWindowToFrontWithoutSystemAnimation(_ window: NSWindow, actions: () -> Void) {
        performWithScreenUpdatesSuppressed(actions: actions)
        window.displayIfNeeded()
    }

    private func suppressSystemShowAnimation(on window: NSWindow, actions: () -> Void) {
        performWithScreenUpdatesSuppressed(actions: actions)
        window.displayIfNeeded()
    }

    private func performWithScreenUpdatesSuppressed(actions: () -> Void) {
        if let disable = Self.disableGlobalScreenUpdates, let enable = Self.enableGlobalScreenUpdates {
            disable()
            defer { enable() }
            actions()
        } else {
            actions()
        }
    }

    // scale アニメーションは削除（互換は slide にフォールバック）
    
    private func animateSlide(_ window: NSWindow) {
        let targetFrame = window.frame
        var startFrame = targetFrame
        startFrame.origin.y += 50
        window.setFrame(startFrame, display: false)
        window.alphaValue = 0
        suppressSystemShowAnimation(on: window) {
            window.makeKeyAndOrderFront(nil)
        }
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.focusOnEditor()
            }
        }
    }
    
    private func setupMainWindowObservers(_ window: NSWindow) {
        removeMainWindowObservers()
        windowObserver = addWindowDidBecomeKeyObserver(window)
        windowResignObserver = addWindowDidBecomeMainObserver(window)
        windowResizeObserver = addWindowResizeObserver(window)
        appDidResignActiveObserver = addAppDidResignActiveObserver(window)
        appDidBecomeActiveObserver = addAppDidBecomeActiveObserver()
    }

    private func addWindowDidBecomeKeyObserver(_ window: NSWindow) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { _ in }
    }

    private func addWindowDidBecomeMainObserver(_ window: NSWindow) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: window,
            queue: .main
        ) { _ in }
    }

    private func addWindowResizeObserver(_ window: NSWindow) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                UserDefaults.standard.set(window.frame.height, forKey: "windowHeight")
                UserDefaults.standard.set(window.frame.width, forKey: "windowWidth")
            }
        }
    }

    private func addAppDidResignActiveObserver(_ window: NSWindow) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { _ in }
    }

    private func addAppDidBecomeActiveObserver() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in }
    }
    
    private func removeMainWindowObservers() {
        let observers = [
            windowObserver,
            windowResignObserver,
            windowResizeObserver,
            appDidResignActiveObserver,
            appDidBecomeActiveObserver
        ]
        observers.compactMap { $0 }.forEach { NotificationCenter.default.removeObserver($0) }
        windowObserver = nil
        windowResignObserver = nil
        windowResizeObserver = nil
        appDidResignActiveObserver = nil
        appDidBecomeActiveObserver = nil
    }
    
    private func handleMainWindowClose() {
        NSApp.setActivationPolicy(.accessory)
        HistoryPopoverManager.shared.forceClose()
        appToRestoreAfterClose = nil
        // 余計な参照を明示的に解放して解体順序を安定化
        if let window = mainWindow {
            window.delegate = nil
            window.contentView = nil
            window.contentViewController = nil
        }
        if let viewModel = mainViewModel,
           viewModel.isQueueModeActive,
           viewModel.pasteQueue.isEmpty {
            viewModel.resetPasteQueue()
        }
        mainWindow = nil
        isAlwaysOnTop = false
        removeMainWindowObservers()
    }

    private func exitQueueModeIfNeededBeforeAutoHide() {
        guard let viewModel = mainViewModel,
              viewModel.isQueueModeActive else { return }
        guard viewModel.pasteQueue.isEmpty else { return }
        viewModel.resetPasteQueue()
        titleBarState.isQueueActive = false
    }

    private func syncTitleBarQueueState() {
        guard let viewModel = mainViewModel else {
            titleBarState.isQueueActive = false
            return
        }
        titleBarState.isQueueActive = viewModel.isQueueModeActive
        titleBarState.isQueueEnabled = viewModel.canUsePasteQueue
    }
    
    // MARK: - Public Methods

    @MainActor
    func showCopiedNotification() {
        // MainViewにコピー通知を表示する
        // ウィンドウが開いている場合のみ通知を送信
        if mainWindow != nil {
            NotificationCenter.default.post(name: .showCopiedNotification, object: nil)
        }
    }
    
    // MARK: - Settings Window
    
    func openSettings(tab: SettingsViewModel.Tab = .general) {
        if settingsWindow == nil {
            let viewModel = SettingsViewModel()
            let settingsView = SettingsView(viewModel: viewModel)
            let hostingController = SettingsHostingController(rootView: settingsView)
            let contentController = GlassWindowContentController(
                hostingController: hostingController,
                cornerRadius: KippleGlassMetrics.windowCornerRadius
            )

            let window = NSWindow(contentViewController: contentController)
            window.title = localizedSettingsWindowTitle()
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.setContentSize(KippleGlassMetrics.settingsWindowSize)
            window.center()
            window.isReleasedWhenClosed = false
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.toolbarStyle = .preference

            let coordinator = SettingsToolbarController(viewModel: viewModel)
            coordinator.attach(to: window, contentController: contentController)
            settingsCoordinator = coordinator
            settingsViewModel = viewModel

            settingsWindow = window
            updateLocalization()
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsViewModel?.selectedTab = tab

        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: settingsWindow,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(.accessory)
            if let observer = self?.settingsObserver {
                NotificationCenter.default.removeObserver(observer)
                self?.settingsObserver = nil
            }
            self?.settingsCoordinator = nil
            self?.settingsViewModel = nil
            self?.settingsWindow = nil
        }
    }
    
    // MARK: - About Window
    
    func showAbout() {
        if aboutWindow == nil {
            let aboutView = AboutView()
            let hostingController = NSHostingController(rootView: aboutView)
            
            aboutWindow = NSWindow(contentViewController: hostingController)
            aboutWindow?.title = localizedAboutWindowTitle()
            aboutWindow?.styleMask = [.titled, .closable]
            aboutWindow?.isMovableByWindowBackground = true
            aboutWindow?.setContentSize(NSSize(width: 340, height: 360))
            aboutWindow?.center()
            aboutWindow?.isReleasedWhenClosed = false
            if let window = aboutWindow,
               !window.collectionBehavior.contains(.moveToActiveSpace) {
                // 常に現在のSpaceに追従させ、画面切り替えを防ぐ
                window.collectionBehavior.insert(.moveToActiveSpace)
            }
        } else {
            aboutWindow?.title = localizedAboutWindowTitle()
        }

        if let window = aboutWindow,
           !window.collectionBehavior.contains(.moveToActiveSpace) {
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
        
        centerAboutWindowOnActiveScreen()

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
        
        if let observer = aboutObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        aboutObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: aboutWindow,
            queue: .main
        ) { _ in
            Task { @MainActor in
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func updateLocalization() {
        mainWindow?.title = localizedMainWindowTitle()
        settingsWindow?.title = localizedSettingsWindowTitle()
        settingsCoordinator?.refreshLocalization()
        aboutWindow?.title = localizedAboutWindowTitle()
    }

    private func localizedMainWindowTitle() -> String {
        appSettings.localizedString("MainWindowTitle", comment: "Main window title")
    }

    private func localizedSettingsWindowTitle() -> String {
        appSettings.localizedString("Settings", comment: "Settings window title")
    }

    private func localizedAboutWindowTitle() -> String {
        appSettings.localizedString("AboutWindowTitle", comment: "About window title")
    }
    
    private func centerAboutWindowOnActiveScreen() {
        guard let window = aboutWindow else { return }
        guard let screen = mainWindow?.screen ?? NSScreen.main else {
            window.center()
            return
        }
        var frame = window.frame
        let visibleFrame = screen.visibleFrame
        frame.origin.x = visibleFrame.midX - frame.width / 2
        frame.origin.y = visibleFrame.midY - frame.height / 2
        window.setFrame(frame, display: false, animate: false)
    }

    // MARK: - Focus Management
    
    private func focusOnEditor() {
        guard let window = mainWindow else { return }
        let startedAt = PerformanceTrace.nowMicros()
        PerformanceTrace.event("main_window_focus_editor_started")

        if let textView = cachedEditorTextView, textView.window === window {
            focus(textView, startedAt: startedAt, source: "cached")
            return
        }

        // ウィンドウ内のNSTextViewを検索してフォーカスを設定
        if let textView = findTextView(in: window.contentView) {
            cachedEditorTextView = textView
            focus(textView, startedAt: startedAt, source: "searched")
        } else {
            PerformanceTrace.event(
                "main_window_focus_editor_missing",
                details: ["durationUs": "\(PerformanceTrace.nowMicros() - startedAt)"]
            )
        }
    }
    
    private func findTextView(in view: NSView?) -> LiveEditorTextView? {
        guard let view = view else { return nil }
        
        if let textView = view as? LiveEditorTextView {
            return textView
        }
        
        // 再帰的に子ビューを検索
        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        return nil
    }

    private func focus(_ textView: LiveEditorTextView, startedAt: Int64, source: String) {
        let textLength = textView.textStorage?.length ?? 0
        textView.window?.makeFirstResponder(textView)

        if textLength <= maxFocusedEditorTailSelectionLength {
            textView.setSelectedRange(NSRange(location: textLength, length: 0))
        }

        PerformanceTrace.event(
            "main_window_focus_editor_finished",
            count: textLength,
            details: [
                "durationUs": "\(PerformanceTrace.nowMicros() - startedAt)",
                "source": source,
                "tailSelection": "\(textLength <= maxFocusedEditorTailSelectionLength)"
            ]
        )
    }
    
    // MARK: - NSWindowDelegate (moved to extension below)
}

// MARK: - NSWindowDelegate
extension WindowManager {
    func windowDidBecomeKey(_ notification: Notification) {
        capturePreviousAppForFocusReturn()
        NotificationCenter.default.post(name: .mainWindowDidBecomeKey, object: nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === mainWindow else { return }

        if !isAlwaysOnTop && !preventAutoClose && !isOpening {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
                guard let self = self,
                      let window = window,
                      !window.isKeyWindow && !self.isAlwaysOnTop && !self.preventAutoClose && !self.isOpening else {
                    return
                }
                self.exitQueueModeIfNeededBeforeAutoHide()
                // パネルを破棄せず非表示にして再利用（毎回の再構築コストを回避）
                window.orderOut(nil)
                // 付随のポップオーバーも確実に閉じる
                HistoryPopoverManager.shared.forceClose()
                NotificationCenter.default.post(name: .mainWindowDidHide, object: nil)
            }
        } else {
            // keep window open when always on top
        }
        NotificationCenter.default.post(name: .mainWindowDidResignKey, object: nil)
    }

    func windowWillClose(_ notification: Notification) {
       if notification.object as? NSWindow === mainWindow {
            handleMainWindowClose()
        }
    }
}

extension WindowManager: WindowManaging {}

#if DEBUG
extension WindowManager {
    func setAppToRestoreForTesting(_ app: LastActiveAppTracker.AppInfo?) {
        appToRestoreAfterClose = app
    }

    func triggerReactivationForTesting() {
        reactivatePreviousAppIfPossible()
    }

    func restoreCandidateForTesting() -> LastActiveAppTracker.AppInfo? {
        appToRestoreAfterClose
    }

    func rememberAppForRestoreForTesting(_ info: LastActiveAppTracker.AppInfo) {
        appToRestoreAfterClose = info
        lastActiveAppTracker.updateLastActiveApp(info)
    }
}
#endif

// swiftlint:enable file_length
