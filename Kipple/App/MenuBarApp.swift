//
//  MenuBarApp.swift
//  Kipple
//
//  Created by Kipple on 2025/06/28.
import SwiftUI
import Cocoa

@MainActor
final class MenuBarApp: NSObject, ObservableObject {
    private var statusBarItem: NSStatusItem?
    internal let clipboardService: any ClipboardServiceProtocol
    internal let windowManager = WindowManager()
    internal var hotkeyManager: Any
    let openKippleMenuTitle = "Open Kipple"
    let openKippleMenuItem = NSMenuItem(
        title: "Open Kipple",
        action: #selector(openMainWindow),
        keyEquivalent: ""
    )
    let screenTextCaptureMenuTitle = "Screen Text Capture"
    let screenTextCaptureMenuItem = NSMenuItem(
        title: "Screen Text Capture",
        action: #selector(captureTextFromScreen),
        keyEquivalent: ""
    )
    let screenCaptureStatusItem = NSMenuItem()
    let accessibilityStatusItem = NSMenuItem()
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
    private var openKippleHotkeyObserver: NSObjectProtocol?
    private var screenRecordingPermissionObserver: NSObjectProtocol?
    
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

        // Skip heavy initialization when running unit tests
        guard !Self.isTestEnvironment else { return }

        screenRecordingPermissionObserver = NotificationCenter.default.addObserver(
            forName: .screenRecordingPermissionRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.windowManager.openSettings(tab: .permission)
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

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setupMenuBar()
            self.setupTextCaptureHotkey()
            self.startServices()
        }
    }
    
    private func setupMenuBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem?.button {
            button.title = "📋"
            
            if let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Kipple") {
                image.size = NSSize(width: 18, height: 18)
                image.isTemplate = true
                button.image = image
                button.imagePosition = .imageOnly
            }
            
            button.toolTip = "Kipple - Clipboard Manager"
        }
        
        let menu = createMenu()
        statusBarItem?.menu = menu
        statusBarItem?.isVisible = true

        observeOpenKippleHotkeyChanges()
    }

    private func observeOpenKippleHotkeyChanges() {
        if let observer = openKippleHotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
            openKippleHotkeyObserver = nil
        }

        openKippleHotkeyObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HotkeySettingsChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateOpenKippleMenuItemShortcut()
        }
    }
    
    private func createMenu() -> NSMenu {
        let menu = NSMenu(); menu.delegate = self
        
        menu.addItem(NSMenuItem(title: "About", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(openKippleMenuEntry())
        menu.addItem(screenTextCaptureMenuEntry())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(screenCaptureMenuItem())
        menu.addItem(accessibilityMenuItem())
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Kipple", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }

        updateScreenCaptureMenuItem()
        updateAccessibilityMenuItem()
        updateOpenKippleMenuItemShortcut()
        updateScreenTextCaptureMenuItemShortcut()
        return menu
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
        Task { @MainActor in
            windowManager.openMainWindow()
        }
    }
    
    @objc private func openPreferences() {
        windowManager.openSettings()
    }
    
    @objc private func showAbout() {
        windowManager.showAbout()
    }

    @objc private func quit() {
        Logger.shared.log("=== QUIT MENU CLICKED ===")
        // Calling terminate triggers applicationShouldTerminate
        NSApplication.shared.terminate(nil)
    }
    
    private func performAsyncTermination() {
        Logger.shared.log("=== ASYNC APP QUIT SEQUENCE STARTED ===")
        Logger.shared.log("Current history count: \(clipboardService.history.count)")
        
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
            Logger.shared.log("Flushing pending saves...")
            await clipboardService.flushPendingSaves()

            Logger.shared.log("✅ Successfully saved data before quit")
            
            // Cancel the watchdog timeout
            self.terminationWorkItem?.cancel()
            Logger.shared.log("Save operation completed, cancelling timeout")
            
            // Finish termination on the main thread
            await MainActor.run { [weak self] in
                Logger.shared.log("Calling completeTermination on main thread")
                self?.completeTermination()
            }
        }
    }
    
    private func completeTermination() {
        Logger.shared.log("completeTermination called on thread: \(Thread.current)")
        
        Logger.shared.log("Stopping clipboard monitoring...")
        clipboardService.stopMonitoring()
        
        Logger.shared.log("Cleaning up windows...")
        // cleanup method was removed in Swift 6.2 migration
        
        Logger.shared.log("=== APP QUIT SEQUENCE COMPLETED ===")
        
        // Allow the application to terminate
        Logger.shared.log("Calling reply(toApplicationShouldTerminate: true)")
        NSApplication.shared.reply(toApplicationShouldTerminate: true)
        Logger.shared.log("reply(toApplicationShouldTerminate: true) called successfully")
    }
    
    private func forceTerminate() {
        Logger.shared.log("forceTerminate called - timeout occurred")
        
        // Force termination when the timeout fires
        DispatchQueue.main.async { [weak self] in
            Logger.shared.log("forceTerminate on main thread")
            self?.clipboardService.stopMonitoring()
            // cleanup method was removed in Swift 6.2 migration
            
            // Allow the application to terminate immediately
            Logger.shared.log("Calling reply(toApplicationShouldTerminate: true) from forceTerminate")
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
            Logger.shared.log("forceTerminate completed")
        }
    }
}

// MARK: - HotkeyManagerDelegate
// HotkeyManagerDelegate removed - using SimplifiedHotkeyManager notifications instead

// MARK: - Hotkey Handling

extension MenuBarApp: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        updateScreenCaptureMenuItem()
        updateAccessibilityMenuItem()
        updateOpenKippleMenuItemShortcut()
        updateScreenTextCaptureMenuItemShortcut()
    }
}

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
        Logger.shared.log("=== applicationShouldTerminate called ===")
        Logger.shared.log("isTerminating flag: \(isTerminating)")
        Logger.shared.log("Sender: \(sender)")
        Logger.shared.log("Current thread: \(Thread.current)")
        
        // Allow immediate termination during tests
        if Self.isTestEnvironment {
            return .terminateNow
        }
        
        // If termination is already in progress
        if isTerminating {
            Logger.shared.log("WARNING: Already terminating, this should not happen!")
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
        Logger.shared.log("=== applicationWillTerminate called ===")
        // The save work should be finished by this point
    }
}
