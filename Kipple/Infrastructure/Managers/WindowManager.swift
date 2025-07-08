//
//  WindowManager.swift
//  Kipple
//
//  Created by Kipple on 2025/07/02.
//

import SwiftUI
import AppKit

extension Notification.Name {
    static let showCopiedNotification = Notification.Name("showCopiedNotification")
}

final class WindowManager: NSObject {
    private var mainWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    #if DEBUG
    private var developerSettingsWindow: NSWindow?
    #endif
    private var mainViewModel: MainViewModel?
    private var isAlwaysOnTop = false {
        didSet {
            if let window = mainWindow {
                window.level = isAlwaysOnTop ? .floating : .normal
            }
        }
    }
    
    // Observers
    private var windowObserver: NSObjectProtocol?
    private var windowResignObserver: NSObjectProtocol?
    private var windowResizeObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var aboutObserver: NSObjectProtocol?
    #if DEBUG
    private var developerSettingsObserver: NSObjectProtocol?
    #endif
    
    // MARK: - Main Window
    
    func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        
        // 既存のウィンドウがある場合は再利用
        if let existingWindow = mainWindow {
            // ウィンドウが最小化されている場合は復元
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            
            // ウィンドウが画面に表示されていない場合は中央に配置
            if !existingWindow.isVisible {
                existingWindow.center()
            }
            
            // ウィンドウを最前面に表示してフォーカスを当てる
            existingWindow.makeKeyAndOrderFront(nil)
            
            // カーソル位置に再配置
            positionWindowAtCursor(existingWindow)
            return
        }
        
        // 新規ウィンドウ作成
        let window = createMainWindow()
        guard let window = window else { return }
        
        configureMainWindow(window)
        setupMainWindowObservers(window)
        animateWindowOpen(window)
    }
    
    private func createMainWindow() -> NSWindow? {
        // MainViewModelを作成または再利用
        if mainViewModel == nil {
            mainViewModel = MainViewModel()
        }
        
        let contentView = MainView(
            onClose: { [weak self] in
                self?.mainWindow?.close()
            },
            onAlwaysOnTopChanged: { [weak self] isOnTop in
                self?.isAlwaysOnTop = isOnTop
            },
            onOpenSettings: { [weak self] in
                self?.openSettings()
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
        window.title = "Kipple"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .fullSizeContentView, .resizable]
        window.level = .floating
        window.hidesOnDeactivate = false
        
        // ツールバーボタンを無効化（×ボタン以外を非表示）
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        // ウィンドウサイズの設定
        configureWindowSize(window)
        
        // カーソル位置にウィンドウを配置
        positionWindowAtCursor(window)
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
        let animationType = UserDefaults.standard.string(forKey: "windowAnimation") ?? "fade"
        
        switch animationType {
        case "scale":
            animateScale(window)
        case "slide":
            animateSlide(window)
        case "none":
            window.makeKeyAndOrderFront(nil)
        default: // "fade"
            animateFade(window)
        }
    }
    
    private func animateFade(_ window: NSWindow) {
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 1.0
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
        }
    }
    
    private func setupMainWindowObservers(_ window: NSWindow) {
        removeMainWindowObservers()
        
        // ウィンドウサイズ変更を監視
        windowResizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                UserDefaults.standard.set(window.frame.height, forKey: "windowHeight")
                UserDefaults.standard.set(window.frame.width, forKey: "windowWidth")
            }
        }
        
        // ウィンドウが閉じられたときの処理
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.handleMainWindowClose()
        }
        
        // ウィンドウがフォーカスを失ったときに閉じる（常に最前面モードでない場合のみ）
        windowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if !self.isAlwaysOnTop {
                window.close()
            }
        }
    }
    
    private func removeMainWindowObservers() {
        let observers = [windowObserver, windowResignObserver, windowResizeObserver]
        observers.compactMap { $0 }.forEach { NotificationCenter.default.removeObserver($0) }
        windowObserver = nil
        windowResignObserver = nil
        windowResizeObserver = nil
    }
    
    private func handleMainWindowClose() {
        NSApp.setActivationPolicy(.accessory)
        mainWindow = nil
        isAlwaysOnTop = false
        removeMainWindowObservers()
        
        // ウィンドウクローズ時にカテゴリフィルタをリセット
        if let viewModel = mainViewModel {
            viewModel.selectedCategory = nil
            // フィルタ解除後に履歴を再更新
            viewModel.updateFilteredItems(viewModel.clipboardService.history)
        }
    }
    
    // MARK: - Public Methods
    
    func closeMainWindow() {
        mainWindow?.close()
    }
    
    func getMainViewModel() -> MainViewModel? {
        if mainViewModel == nil {
            mainViewModel = MainViewModel()
        }
        return mainViewModel
    }
    
    func isWindowAlwaysOnTop() -> Bool {
        return isAlwaysOnTop
    }
    
    func showCopiedNotification() {
        // MainViewにコピー通知を表示する
        // ウィンドウが開いている場合のみ通知を送信
        if mainWindow != nil {
            NotificationCenter.default.post(name: .showCopiedNotification, object: nil)
        }
    }
    
    // MARK: - Settings Window
    
    func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Kipple Preferences"
            settingsWindow?.styleMask = [.titled, .closable, .miniaturizable]
            settingsWindow?.setContentSize(NSSize(width: 450, height: 400))
            settingsWindow?.center()
            settingsWindow?.isReleasedWhenClosed = false
        }
        
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        
        if let observer = settingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        settingsObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: settingsWindow,
            queue: .main
        ) { _ in
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    // MARK: - About Window
    
    func showAbout() {
        if aboutWindow == nil {
            let aboutView = AboutView()
            let hostingController = NSHostingController(rootView: aboutView)
            
            aboutWindow = NSWindow(contentViewController: hostingController)
            aboutWindow?.title = "About Kipple"
            aboutWindow?.styleMask = [.titled, .closable]
            aboutWindow?.isMovableByWindowBackground = true
            aboutWindow?.setContentSize(NSSize(width: 400, height: 580))
            aboutWindow?.center()
            aboutWindow?.isReleasedWhenClosed = false
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
            NSApp.setActivationPolicy(.accessory)
        }
    }
    
    // MARK: - Developer Settings Window
    
    #if DEBUG
    func openDeveloperSettings() {
        if developerSettingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Developer Settings"
            window.center()
            window.contentView = NSHostingView(rootView: DeveloperSettingsView())
            window.isReleasedWhenClosed = false
            developerSettingsWindow = window
        }
        
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        developerSettingsWindow?.makeKeyAndOrderFront(nil)
        
        if let observer = developerSettingsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        developerSettingsObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: developerSettingsWindow,
            queue: .main
        ) { _ in
            NSApp.setActivationPolicy(.accessory)
        }
    }
    #endif
    
    // MARK: - Cleanup
    
    func cleanup() {
        var observers: [NSObjectProtocol?] = [
            windowObserver,
            windowResignObserver,
            windowResizeObserver,
            settingsObserver,
            aboutObserver
        ]
        #if DEBUG
        observers.append(developerSettingsObserver)
        #endif
        observers.compactMap { $0 }.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    deinit {
        cleanup()
    }
}
