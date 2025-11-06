//
//  WindowManager.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI
import AppKit
import Combine

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
}

@MainActor
// swiftlint:disable:next type_body_length
final class WindowManager: NSObject, NSWindowDelegate {
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var settingsCoordinator: SettingsToolbarController?
    private var settingsViewModel: SettingsViewModel?
    private var mainViewModel: MainViewModel?
    private let titleBarState = MainWindowTitleBarState()
    private var titleBarLeftHostingView: NSHostingView<MainViewTitleBarAccessory>?
    private var titleBarPinHostingView: NSHostingView<MainViewTitleBarPinButton>?
    private let appSettings = AppSettings.shared
    private var localizationCancellable: AnyCancellable?
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

    override init() {
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
        // Upイベント直後の誤クローズ抑止
        preventAutoClose = true

        // 既存のウィンドウがある場合は再利用
        if let existingWindow = mainWindow {
            // ウィンドウが最小化されている場合は復元
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }

            // 表示状態の判定を先に保持
            let wasVisible = existingWindow.isVisible

            // ウィンドウが画面に表示されていない場合は中央に配置
            if !wasVisible {
                existingWindow.center()
            }

            // カーソル位置に再配置（アニメーションの最終位置を先に決める）
            positionWindowAtCursor(existingWindow)

            // 非表示→再表示のときはアニメーション設定に従って表示
            if !wasVisible {
                // 自動再表示の一瞬のチラつきを防ぐため、必要なら透明化してからアクティブ化
                let animationType = UserDefaults.standard.string(forKey: "windowAnimation") ?? "none"
                if animationType != "none" {
                    existingWindow.alphaValue = 0
                }
                // アプリをこのタイミングでアクティブ化（以前の位置での自動再表示を避ける）
                NSApp.activate(ignoringOtherApps: true)
                animateWindowOpen(existingWindow)
            } else {
                // すでに可視なら通常の前面化のみ
                NSApp.activate(ignoringOtherApps: true)
                existingWindow.makeKeyAndOrderFront(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.focusOnEditor()
                }
            }
            return
        }

        // 新規ウィンドウ作成
        let window = createMainWindow()
        guard let window = window else { return }

        configureMainWindow(window)
        setupMainWindowObservers(window)
        // 位置を決めてからアクティブ化→表示の順にする
        positionWindowAtCursor(window)
        NSApp.activate(ignoringOtherApps: true)
        animateWindowOpen(window)

        // Upイベント完了まで少し待って抑止解除
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.preventAutoClose = false
        }
    }
    
    @MainActor
    private func createMainWindow() -> NSWindow? {
        // MainViewModelを作成または再利用
        if mainViewModel == nil {
            mainViewModel = MainViewModel()
        }
        
        let contentView = MainView(
            titleBarState: titleBarState,
            onClose: { [weak self] in
                self?.mainWindow?.close()
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
        .environmentObject(mainViewModel!)
        
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
    
    private func setPreventAutoClose(_ flag: Bool) {
        preventAutoClose = flag
    }
    
    private func configureWindowSize(_ window: NSWindow) {
        let savedHeight = UserDefaults.standard.double(forKey: "windowHeight")
        let savedWidth = UserDefaults.standard.double(forKey: "windowWidth")
        let initialHeight = savedHeight > 0 ? savedHeight : 600
        let initialWidth = savedWidth > 0 ? savedWidth : 420
        window.setContentSize(NSSize(width: initialWidth, height: initialHeight))
        window.minSize = NSSize(width: 300, height: 300)
        window.maxSize = NSSize(width: 800, height: 1200)
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
        let mouseLocation = NSEvent.mouseLocation
        let windowSize = window.frame.size
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        
        // ウィンドウの左上をカーソル位置に配置（少しオフセットを追加）
        var windowOrigin = NSPoint(
            x: mouseLocation.x + 10,
            y: mouseLocation.y - windowSize.height - 10
        )
        
        // 画面からはみ出ないように調整
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
            // カーソルの上に表示
            windowOrigin.y = mouseLocation.y + 10
        }
        
        window.setFrameOrigin(windowOrigin)
    }
    
    private func animateWindowOpen(_ window: NSWindow) {
        let animationType = UserDefaults.standard.string(forKey: "windowAnimation") ?? "none"
        
        switch animationType {
        case "scale":
            animateScale(window)
        case "slide":
            animateSlide(window)
        case "none":
            window.makeKeyAndOrderFront(nil)
            // アニメーションなしの場合も少し遅延してフォーカス
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.focusOnEditor()
            }
        default: // "fade"
            animateFade(window)
        }
        // 前面化のフォロー（取りこぼし対策）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak window] in
            guard let window else { return }
            if !window.isKeyWindow {
                NSApp.activate(ignoringOtherApps: true)
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    private func animateFade(_ window: NSWindow) {
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1.0
        } completionHandler: { [weak self] in
            self?.focusOnEditor()
        }
    }
    
    private func animateScale(_ window: NSWindow) {
        let targetFrame = window.frame
        var smallerFrame = targetFrame
        smallerFrame.size.width = targetFrame.width * 0.9
        smallerFrame.size.height = targetFrame.height * 0.9
        smallerFrame.origin.x = targetFrame.origin.x + (targetFrame.width - smallerFrame.width) / 2
        smallerFrame.origin.y = targetFrame.origin.y + (targetFrame.height - smallerFrame.height) / 2
        
        window.setFrame(smallerFrame, display: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            self?.focusOnEditor()
        }
    }
    
    private func animateSlide(_ window: NSWindow) {
        let targetFrame = window.frame
        var startFrame = targetFrame
        startFrame.origin.y += 50
        window.setFrame(startFrame, display: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
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
    
    // MARK: - Public Methods
    
    func closeMainWindow() {
        mainWindow?.close()
    }
    
    @MainActor
    func getMainViewModel() -> MainViewModel? {
        if mainViewModel == nil {
            mainViewModel = MainViewModel()
        }
        return mainViewModel
    }
    
    func isWindowAlwaysOnTop() -> Bool {
        return isAlwaysOnTop
    }
    
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
        } else {
            aboutWindow?.title = localizedAboutWindowTitle()
        }
        
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
        NotificationCenter.default.post(name: .mainWindowDidBecomeKey, object: nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === mainWindow else { return }

        #if arch(arm64)
        let architecture = "Apple Silicon (arm64)"
        #else
        let architecture = "Intel (x86_64)"
        #endif

        if !isAlwaysOnTop && !preventAutoClose {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
                guard let self = self,
                      let window = window,
                      !window.isKeyWindow && !self.isAlwaysOnTop && !self.preventAutoClose else {
                    return
                }
                window.close()
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

// swiftlint:enable file_length
