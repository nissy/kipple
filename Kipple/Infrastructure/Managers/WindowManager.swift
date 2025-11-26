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
    private let referenceScreenshotPixelSize = NSSize(width: 750, height: 1500)
    
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
        cancelPendingAppReactivation()
        isOpening = true
        preventAutoClose = true
        capturePreviousAppForFocusReturn()
        syncTitleBarQueueState()

        if let existingWindow = mainWindow {
            reopenExistingWindow(existingWindow)
            return
        }

        openNewWindow()
    }

    private func reopenExistingWindow(_ window: NSWindow) {
        if window.isMiniaturized { window.deminiaturize(nil) }

        let target = computeOriginAtCursor(for: window)
        if !window.isVisible {
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
                DispatchQueue.main.async { [weak self] in
                    self?.focusOnEditor()
                }
            } else {
                NSApp.activate(ignoringOtherApps: true)
                window.alphaValue = 0
                animateWindowOpen(window)
            }
        } else {
            let style = UserDefaults.standard.string(forKey: "windowAnimation") ?? "none"
            applyAnimationBehavior(style: style, to: window)
            if style == "none" {
                // None: 可視中は隠さず即座に座標だけ反映（完全ノーアニメ）
                var frame = window.frame
                frame.origin = target
                window.setFrame(frame, display: true, animate: false)
                if !window.isKeyWindow {
                    bringWindowToFrontWithoutSystemAnimation(window) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    self?.focusOnEditor()
                }
                completeOpen()
                return
            }
            // アニメあり: 旧位置を見せないため一旦隠し、選択されたスタイルで再表示
            window.orderOut(nil)
            window.setFrameOrigin(target)
            NSApp.activate(ignoringOtherApps: true)
            animateWindowOpen(window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in self?.focusOnEditor() }
        }

        completeOpen()
    }

    private func openNewWindow() {
        let optional = createMainWindow()
        guard let window = optional else { return }
        configureMainWindow(window)
        setupMainWindowObservers(window)
        let target = computeOriginAtCursor(for: window)
        window.setFrameOrigin(target)
        NSApp.activate(ignoringOtherApps: true)
        animateWindowOpen(window)
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
        
        let hostingController = NSHostingController(rootView: contentView)
        hostingController.sizingOptions = []
        mainWindow = NSWindow(contentViewController: hostingController)
        return mainWindow
    }
    
    private func configureMainWindow(_ window: NSWindow) {
        // ウィンドウの基本設定
        window.title = localizedMainWindowTitle()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .fullSizeContentView, .resizable]
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
        attachAlwaysOnTopButton(to: window)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window else { return }
            self?.attachAlwaysOnTopButton(to: window)
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
        let savedHeight = UserDefaults.standard.double(forKey: "windowHeight")
        let savedWidth = UserDefaults.standard.double(forKey: "windowWidth")
        let minimumSize = resolvedMinimumWindowSize(for: window)
        let defaultWidth: CGFloat = minimumSize.width
        let defaultHeight: CGFloat = minimumSize.height
        let resolvedWidth = max(savedWidth > 0 ? CGFloat(savedWidth) : defaultWidth, minimumSize.width)
        let resolvedHeight = max(savedHeight > 0 ? CGFloat(savedHeight) : defaultHeight, minimumSize.height)
        window.setContentSize(NSSize(width: resolvedWidth, height: resolvedHeight))
        window.contentMinSize = minimumSize
        window.minSize = minimumSize
        let maxWidth = max(CGFloat(800), minimumSize.width)
        let maxHeight = max(CGFloat(1200), minimumSize.height)
        window.maxSize = NSSize(width: maxWidth, height: maxHeight)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let minimumSize = resolvedMinimumWindowSize(for: sender)
        var adjustedSize = frameSize
        adjustedSize.width = max(adjustedSize.width, minimumSize.width)
        adjustedSize.height = max(adjustedSize.height, minimumSize.height)
        return adjustedSize
    }

    private func resolvedMinimumWindowSize(for window: NSWindow?) -> NSSize {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        return NSSize(
            width: referenceScreenshotPixelSize.width / scale,
            height: referenceScreenshotPixelSize.height / scale
        )
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
        let screenFrame = targetScreen?.frame ?? NSRect.zero

        var windowOrigin = NSPoint(
            x: mouseLocation.x + 10,
            y: mouseLocation.y - windowSize.height - 10
        )

        if windowOrigin.x + windowSize.width > screenFrame.maxX {
            windowOrigin.x = screenFrame.maxX - windowSize.width - 10
        }
        if windowOrigin.x < screenFrame.minX {
            windowOrigin.x = screenFrame.minX + 10
        }
        if windowOrigin.y < screenFrame.minY {
            windowOrigin.y = screenFrame.minY + 10
        }
        if windowOrigin.y + windowSize.height > screenFrame.maxY {
            windowOrigin.y = mouseLocation.y + 10
        }
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
        if info.pid != 0,
           let running = NSRunningApplication(processIdentifier: info.pid) {
            running.activate(options: [.activateAllWindows])
            return true
        }
        if let bundleId = info.bundleId {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            if let app = apps.first {
                app.activate(options: [.activateAllWindows])
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
            self?.focusOnEditor()
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
            self?.focusOnEditor()
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

            let window = NSWindow(contentViewController: hostingController)
        window.title = localizedSettingsWindowTitle()
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 460, height: 380))
            window.center()
            window.isReleasedWhenClosed = false
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            if #available(macOS 11.0, *) {
                window.toolbarStyle = .preference
            }

            let coordinator = SettingsToolbarController(viewModel: viewModel)
            coordinator.attach(to: window)
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
        
        // ウィンドウ内のNSTextViewを検索してフォーカスを設定
        findAndFocusTextView(in: window.contentView)
    }
    
    private func findAndFocusTextView(in view: NSView?) {
        guard let view = view else { return }
        
        if let textView = view as? NSTextView {
            // テキストビューが見つかった場合、フォーカスを設定
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                // カーソルを末尾に移動
                let range = NSRange(location: textView.string.count, length: 0)
                textView.setSelectedRange(range)
            }
            return
        }
        
        // 再帰的に子ビューを検索
        for subview in view.subviews {
            findAndFocusTextView(in: subview)
        }
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
