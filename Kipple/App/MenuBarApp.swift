//
//  MenuBarApp.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
import SwiftUI
import Cocoa
import Combine

@MainActor
final class MenuBarApp: NSObject, ObservableObject {
    private var statusBarItem: NSStatusItem?
    private let appSettings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    internal let clipboardService: any ClipboardServiceProtocol
    internal let windowManager = WindowManager()
    internal var hotkeyManager: Any
    private lazy var textRecognitionService: any TextRecognitionServiceProtocol =
        TextRecognitionServiceProvider.resolve()
    lazy var textCaptureCoordinator: TextCaptureCoordinator = {
        TextCaptureCoordinator(
            clipboardService: clipboardService,
            textRecognitionService: textRecognitionService,
            windowManager: windowManager
        )
    }()
    var textCaptureHotkeyManager: TextCaptureHotkeyManager?
    var textCaptureHotkeyObserver: NSObjectProtocol?
    var plainTextPasteController: PlainTextPasteController?
    private var screenRecordingPermissionObserver: NSObjectProtocol?
    private var queuePastePermissionObserver: NSObjectProtocol?
    
    private lazy var terminationController = ApplicationTerminationController(
        save: { [weak self] in
            guard let self else { throw CancellationError() }
            MCPIntegration.shared.stop()
            try await clipboardService.saveBeforeTermination()
        },
        reply: { NSApplication.shared.reply(toApplicationShouldTerminate: $0) },
        onFailure: { [weak self] failure in
            MCPIntegration.shared.restart()
            SystemDiagnostics.failure("terminationCancelled", error: failure)
            DispatchQueue.main.async { self?.showTerminationFailure() }
        }
    )
    
    // Detect whether we are running in a test environment
    private static var isTestEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        NSClassFromString("XCTest") != nil
    }
    
    override init() {
        // Initialize services using providers
        self.clipboardService = ClipboardServiceProvider.resolve()

        // Initialize with SimplifiedHotkeyManager
        self.hotkeyManager = HotkeyManagerProvider.resolveSync()

        super.init()
        windowManager.onTextCaptureRequested = { [weak self] in
            self?.captureTextFromScreen()
        }
        observeLocalizationChanges()

        // Skip heavy initialization when running unit tests
        guard !Self.isTestEnvironment else { return }

        SystemDiagnostics.permissions(
            screenCapture: CGPreflightScreenCaptureAccess(),
            accessibility: AXIsProcessTrusted(),
            clipboard: NSPasteboard.general.accessBehavior
        )
        observePermissionRequests()

        // Set up notification for SimplifiedHotkeyManager
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // SimplifiedHotkeyManager uses notifications
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleHotkeyNotification),
                name: NSNotification.Name("toggleMainWindow"),
                object: nil
            )
        }

        // Set the application delegate synchronously (required)
        NSApplication.shared.delegate = self

        // 初回クリック取りこぼし対策: ステータスバーは同期セットアップ
        self.setupMenuBar()

        // その他は非同期初期化
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setupTextCaptureHotkey()
            self.setupPlainTextPasteHotkey()
            self.startServices()
            DispatchQueue.main.async { [weak self] in
                self?.windowManager.prewarmMainWindow()
            }
        }
    }

    /// タイトルバーの権限バッジから要求された際に、設定画面と該当のシステム設定ペインを開く
    private func observePermissionRequests() {
        screenRecordingPermissionObserver = NotificationCenter.default.addObserver(
            forName: .screenRecordingPermissionRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.windowManager.openSettings(tab: .permission)
                ScreenRecordingPermissionOpener.openSystemSettings()
            }
        }

        queuePastePermissionObserver = NotificationCenter.default.addObserver(
            forName: .queuePastePermissionRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.windowManager.openSettings(tab: .permission)
                let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
                if !AXIsProcessTrustedWithOptions(options) {
                    self.openAccessibilityPreferences()
                }
            }
        }
    }

    private func observeLocalizationChanges() {
        appSettings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshLocalizedStrings()
            }
            .store(in: &cancellables)
    }

    func localizedMenuString(_ key: String) -> String {
        appSettings.localizedString(key)
    }

    private func refreshLocalizedStrings() {
        guard !Self.isTestEnvironment else { return }
        if let button = statusBarItem?.button {
            button.toolTip = nil
            if let image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: localizedMenuString("Kipple")
            ) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            }
        }
    }
    
    private func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusBarItem?.button {
            button.title = "📋"
            
            if let image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: localizedMenuString("Kipple")
            ) {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            }

            button.toolTip = nil
            button.target = self
            button.action = #selector(openMainWindow)
            // 初回はアクティベーション優先のためUpで送出（Downは誤作動の原因になる）
            // 初回はアクティベーション優先のためUpで送出（Downは誤作動の原因になる）
            button.sendAction(on: [.leftMouseUp])
        }

        statusBarItem?.menu = nil
        statusBarItem?.isVisible = true
    }

    func startServices() {
        MCPIntegration.shared.restart()
        Task {
            clipboardService.startMonitoring()
        }

        // HotkeyManager already registers during initialization
    }
    
    @objc func openMainWindow() {
        let animationStyle = UserDefaults.standard.string(forKey: "windowAnimation") ?? "none"
        if !NSApp.isActive {
            // NSApp.activate前に現在の前面アプリを記録（メニューバー起動でも復帰先を保持）
            windowManager.rememberFrontmostAppForRestore()
            if animationStyle != "none" {
                // 旧位置の自動再表示を防ぐため、先に不可視化
                windowManager.prepareForActivationBeforeOpen()
            }
            NSApp.activate(ignoringOtherApps: true)
            if animationStyle == "none" {
                windowManager.openMainWindow()
            } else {
                // アニメーションありは1フレーム遅延で前面化（初回クリック対策）
                DispatchQueue.main.async { [weak self] in
                    self?.windowManager.openMainWindow()
                }
            }
        } else {
            windowManager.openMainWindow()
        }
    }
    
    @MainActor
    private func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func showTerminationFailure() {
        let alert = NSAlert()
        alert.messageText = appSettings.localizedString("Kipple could not finish saving")
        alert.informativeText = appSettings.localizedString(
            "Quitting was cancelled to keep your history. Please try quitting again after saving finishes."
        )
        alert.addButton(withTitle: appSettings.localizedString("OK"))
        alert.runModal()
    }
}

// MARK: - HotkeyManagerDelegate
// HotkeyManagerDelegate removed - using SimplifiedHotkeyManager notifications instead

// MARK: - Hotkey Handling

#if DEBUG
extension MenuBarApp {
    @MainActor
    func test_handleTextCaptureSettingsChange(
        enabled: Bool,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        manager: TextCaptureHotkeyManager = TextCaptureHotkeyManager.shared
    ) {
        handleTextCaptureSettingsChange(
            enabled: enabled,
            keyCode: keyCode,
            modifierFlagsRawValue: UInt(modifiers.rawValue),
            manager: manager
        )
    }
}
#endif

// MARK: - NSApplicationDelegate
extension MenuBarApp: NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationController.requestTermination()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        
        MCPIntegration.shared.stop()
        // The save work should be finished by this point
    }
}
