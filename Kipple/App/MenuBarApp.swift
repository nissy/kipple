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
    private var screenRecordingPermissionObserver: NSObjectProtocol?
    private var accessibilityPermissionObserver: NSObjectProtocol?
    
    // Properties for asynchronous termination handling
    private var isTerminating = false
    private var terminationWorkItem: DispatchWorkItem?
    
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

        accessibilityPermissionObserver = NotificationCenter.default.addObserver(
            forName: .accessibilityPermissionRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.windowManager.openSettings(tab: .permission)
                self.openAccessibilityPreferences()
            }
        }

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
            self.startServices()
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
            button.toolTip = localizedMenuString("Kipple - Clipboard Manager")
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

            button.toolTip = localizedMenuString("Kipple - Clipboard Manager")
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
        // Perform data migration if needed
        Task {
            await performDataMigrationIfNeeded()

            // Start clipboard monitoring
            clipboardService.startMonitoring()
        }

        // HotkeyManager already registers during initialization
    }

    private func performDataMigrationIfNeeded() async {
        // Migration is no longer needed
    }
    
    @objc func openMainWindow() {
        let animationStyle = UserDefaults.standard.string(forKey: "windowAnimation") ?? "none"
        if !NSApp.isActive {
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
    
    @objc private func openPreferences() {
        windowManager.openSettings()
    }
    
    @objc private func showAbout() {
        windowManager.showAbout()
    }

    @MainActor
    private func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quit() {
        // Calling terminate triggers applicationShouldTerminate
        NSApplication.shared.terminate(nil)
    }
    
    private func performAsyncTermination() {
        
        // Timeout handler (maximum 2 seconds)
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            Logger.shared.error("⚠️ Save operation timed out, forcing quit")
            self?.forceTerminate()
        }
        self.terminationWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: timeoutWorkItem)
        
        // Execute the save work asynchronously
        Task {
            // Flush any debounced saves immediately
            await clipboardService.flushPendingSaves()

            // Cancel the watchdog timeout
            self.terminationWorkItem?.cancel()
            
            // Finish termination on the main thread
            await MainActor.run { [weak self] in
                self?.completeTermination()
            }
        }
    }
    
    private func completeTermination() {
        
        clipboardService.stopMonitoring()
        
        // cleanup method was removed in Swift 6.2 migration
        
        // Allow the application to terminate
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
    }
    
    private func forceTerminate() {
        
        // Force termination when the timeout fires
        DispatchQueue.main.async { [weak self] in
            
            self?.clipboardService.stopMonitoring()
            // cleanup method was removed in Swift 6.2 migration
            
            // Allow the application to terminate immediately
            
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
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
        
        // Allow immediate termination during tests
        if Self.isTestEnvironment {
            return .terminateNow
        }
        
        // If termination is already in progress
        if isTerminating {
            Logger.shared.warning("Already terminating, this should not happen!")
            // Permit immediate termination if previous async work is stuck
            return .terminateNow
        }
        
        // Begin the asynchronous termination flow
        isTerminating = true
        performAsyncTermination()
        
        // Cancel termination for now (will reply later)
        return .terminateCancel
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        
        // The save work should be finished by this point
    }
}
