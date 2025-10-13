//
//  TextCaptureCoordinator.swift
//  Kipple
//
//  Created by Kipple on 2025/10/09.
//

import AppKit
import CoreGraphics

@MainActor
final class TextCaptureCoordinator {
    typealias OverlaySelectionHandler = (_ rect: CGRect, _ screen: NSScreen) -> Void
    typealias OverlayCancelHandler = () -> Void
    typealias ScreenSelectionOverlayFactory = (
        _ onSelection: @escaping OverlaySelectionHandler,
        _ onCancel: @escaping OverlayCancelHandler
    ) -> ScreenSelectionOverlayControlling

    private let clipboardService: any ClipboardServiceProtocol
    private let textRecognitionService: any TextRecognitionServiceProtocol
    private let windowManager: WindowManaging
    private let screenCapturePermission: ScreenCapturePermissionDependencies
    private let overlayFactory: ScreenSelectionOverlayFactory

    private var overlayController: (any ScreenSelectionOverlayControlling)?
    private var permissionMonitoringTask: Task<Void, Never>?
    private var isAwaitingPermission = false
    private var shouldResumeCaptureAfterPermission = false

    init(
        clipboardService: any ClipboardServiceProtocol,
        textRecognitionService: any TextRecognitionServiceProtocol,
        windowManager: WindowManaging,
        screenCapturePermission: ScreenCapturePermissionDependencies = .live,
        overlayFactory: @escaping ScreenSelectionOverlayFactory = { onSelection, onCancel in
            ScreenSelectionOverlayController(onSelection: onSelection, onCancel: onCancel)
        }
    ) {
        self.clipboardService = clipboardService
        self.textRecognitionService = textRecognitionService
        self.windowManager = windowManager
        self.screenCapturePermission = screenCapturePermission
        self.overlayFactory = overlayFactory
    }

    deinit {
        permissionMonitoringTask?.cancel()
    }

    func startCaptureFlow() {
        Logger.shared.info("Starting OCR capture flow.")

        guard screenCapturePermission.preflight() else {
            shouldResumeCaptureAfterPermission = true
            beginPermissionAcquisitionFlow()
            return
        }

        shouldResumeCaptureAfterPermission = false
        presentSelectionOverlay()
    }

    func showPermissionSettings() {
        screenCapturePermission.openPermissionTab()
    }

    private func presentSelectionOverlay() {
        overlayController?.cancel()
        overlayController = nil

        let controller = overlayFactory(
            { [weak self] rect, screen in
                Task { @MainActor [weak self] in
                    self?.handleSelection(rect: rect, screen: screen)
                }
            },
            { [weak self] in
                self?.overlayController = nil
            }
        )

        overlayController = controller
        controller.present()
    }

    private func beginPermissionAcquisitionFlow() {
        guard !isAwaitingPermission else { return }

        isAwaitingPermission = true
        permissionMonitoringTask?.cancel()
        permissionMonitoringTask = Task { [weak self] in
            await self?.monitorPermissionFlow()
        }
    }

    @MainActor
    private func monitorPermissionFlow() async {
        let grantedImmediately = screenCapturePermission.request()

        if grantedImmediately || screenCapturePermission.preflight() {
            permissionGranted()
            return
        }

        screenCapturePermission.openPermissionTab()
        screenCapturePermission.openSystemSettings()

        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: screenCapturePermission.pollingIntervalNanoseconds)
            } catch {
                break
            }

            if screenCapturePermission.preflight() {
                permissionGranted()
                return
            }
        }
    }

    @MainActor
    private func permissionGranted() {
        guard isAwaitingPermission else { return }

        isAwaitingPermission = false
        permissionMonitoringTask?.cancel()
        permissionMonitoringTask = nil

        let resumeCapture = shouldResumeCaptureAfterPermission
        shouldResumeCaptureAfterPermission = false

        guard resumeCapture else { return }
        presentSelectionOverlay()
    }

    private func handleSelection(rect: CGRect, screen: NSScreen) {
        Logger.shared.info("Selection finished. rect: \(rect)")
        overlayController = nil

        guard let image = captureImage(from: rect, on: screen) else {
            Logger.shared.error("Failed to capture image from selection.")
            presentErrorAlert(message: "Failed to capture the screen. Check Screen Recording permissions in System Settings.")
            return
        }

        playShutterSound()

        Task {
            do {
                let text = try await textRecognitionService.recognizeText(from: image)
                try Task.checkCancellation()
                await MainActor.run { [weak self] in
                    self?.handleRecognizedText(text)
                }
            } catch {
                Logger.shared.error("OCR failed with error: \(error.localizedDescription)")
                await MainActor.run { [weak self] in
                    self?.presentErrorAlert(message: "Could not extract text.\nPlease try again.")
                }
            }
        }
    }

    private func handleRecognizedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            Logger.shared.warning("No text recognized from selection.")
            presentErrorAlert(message: "Text could not be detected. Please try another area.")
            return
        }

        clipboardService.copyToClipboard(trimmed, fromEditor: false)
        windowManager.openMainWindow()
        windowManager.showCopiedNotification()
    }

    private func captureImage(from rect: CGRect, on screen: NSScreen) -> CGImage? {
        guard
            let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
            let fullImage = CGDisplayCreateImage(screenNumber)
        else {
            Logger.shared.error("Could not create display image for screen \(screen).")
            return nil
        }

        let scale = screen.backingScaleFactor
        let screenFrame = screen.frame

        var localRect = CGRect(
            x: (rect.origin.x - screenFrame.origin.x) * scale,
            y: (rect.origin.y - screenFrame.origin.y) * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        )

        localRect = localRect.integral

        if localRect.width < 1 { localRect.size.width = 1 }
        if localRect.height < 1 { localRect.size.height = 1 }

        let maxWidth = CGFloat(fullImage.width)
        let maxHeight = CGFloat(fullImage.height)

        localRect.origin.x = max(0, min(localRect.origin.x, maxWidth - 1))
        localRect.size.width = min(localRect.size.width, maxWidth - localRect.origin.x)
        localRect.size.height = min(localRect.size.height, maxHeight - localRect.origin.y)

        let bottomLeftY = localRect.origin.y
        var invertedY = maxHeight - bottomLeftY - localRect.size.height
        if invertedY < 0 {
            invertedY = 0
        }
        if invertedY + localRect.size.height > maxHeight {
            invertedY = max(0, maxHeight - localRect.size.height)
        }
        localRect.origin.y = invertedY

        return fullImage.cropping(to: localRect)
    }

    private func presentErrorAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "OCR Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private lazy var shutterSound: NSSound? = {
        let bundledNames = [
            NSSound.Name("Screen Capture"),
            NSSound.Name("Grab"),
            NSSound.Name("Shutter"),
            NSSound.Name("cameraShutter")
        ]

        for name in bundledNames {
            if let sound = NSSound(named: name) {
                sound.volume = 1.0
                return sound
            }
        }

        let soundDirectoryPath =
            "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system"
        let searchDirectory = URL(fileURLWithPath: soundDirectoryPath, isDirectory: true)

        let fileCandidates = ["Screen Capture.aif", "Grab.aif", "Shutter.aif"]
        for file in fileCandidates {
            let url = searchDirectory.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: url.path),
               let sound = NSSound(contentsOf: url, byReference: true) {
                sound.volume = 1.0
                return sound
            }
        }

        return nil
    }()

    private func playShutterSound() {
        if let sound = shutterSound {
            sound.stop()
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}

// MARK: - Dependencies

@MainActor
extension TextCaptureCoordinator {
    struct ScreenCapturePermissionDependencies {
        var preflight: () -> Bool
        var request: () -> Bool
        var openPermissionTab: () -> Void
        var openSystemSettings: () -> Void
        var pollingIntervalNanoseconds: UInt64

        @MainActor
        static var live: ScreenCapturePermissionDependencies {
            ScreenCapturePermissionDependencies(
                preflight: { CGPreflightScreenCaptureAccess() },
                request: { CGRequestScreenCaptureAccess() },
                openPermissionTab: {
                    NotificationCenter.default.post(
                        name: .screenRecordingPermissionRequested,
                        object: nil,
                        userInfo: nil
                    )
                },
                openSystemSettings: {
                    ScreenRecordingPermissionOpener.openSystemSettings()
                },
                pollingIntervalNanoseconds: 1_000_000_000
            )
        }
    }
}

#if DEBUG
extension TextCaptureCoordinator {
    func test_handleRecognizedText(_ text: String) {
        handleRecognizedText(text)
    }

    func test_isAwaitingPermission() -> Bool {
        isAwaitingPermission
    }
}
#endif
