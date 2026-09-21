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
    private let imageCaptureService: any ScreenImageCapturing
    private let overlayFactory: ScreenSelectionOverlayFactory
    private let errorPresenter: ((String) -> Void)?

    private var overlayController: (any ScreenSelectionOverlayControlling)?
    private var permissionMonitoringTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var isAwaitingPermission = false
    private var shouldResumeCaptureAfterPermission = false

    init(
        errorPresenter: ((String) -> Void)? = nil,
        clipboardService: any ClipboardServiceProtocol,
        textRecognitionService: any TextRecognitionServiceProtocol,
        windowManager: WindowManaging,
        screenCapturePermission: ScreenCapturePermissionDependencies = .live,
        imageCaptureService: any ScreenImageCapturing = ScreenImageCaptureService(),
        overlayFactory: @escaping ScreenSelectionOverlayFactory = { onSelection, onCancel in
            ScreenSelectionOverlayController(onSelection: onSelection, onCancel: onCancel)
        }
    ) {
        self.clipboardService = clipboardService
        self.textRecognitionService = textRecognitionService
        self.windowManager = windowManager
        self.screenCapturePermission = screenCapturePermission
        self.imageCaptureService = imageCaptureService
        self.overlayFactory = overlayFactory
        self.errorPresenter = errorPresenter
    }

    deinit {
        permissionMonitoringTask?.cancel()
        captureTask?.cancel()
    }

    func startCaptureFlow() {
        captureTask?.cancel()
        captureTask = nil

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
        overlayController = nil
        captureTask?.cancel()
        captureTask = Task { [weak self] in
            await self?.captureAndRecognize(rect: rect, screen: screen)
        }
    }

    private func captureAndRecognize(rect: CGRect, screen: NSScreen) async {
        let image: CGImage
        do {
            image = try await imageCaptureService.captureImage(from: rect, on: screen)
            try Task.checkCancellation()
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            Logger.shared.error("Failed to capture image from selection: \(error.localizedDescription)")
            let message = screenCapturePermission.preflight()
                ? NSLocalizedString(
                    "Failed to capture the screen. Please try again.",
                    comment: "Error shown when screen capture fails despite an available permission"
                )
                : NSLocalizedString(
                    "Failed to capture the screen. Check Screen & System Audio Recording in System Settings.",
                    comment: "Error shown when screen recording permission prevents OCR capture"
                )
            presentErrorAlert(message: message)
            return
        }

        playShutterSound()

        do {
            let text = try await textRecognitionService.recognizeText(from: image)
            try Task.checkCancellation()
            await handleRecognizedText(text)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            Logger.shared.error("OCR failed with error: \(error.localizedDescription)")
            presentErrorAlert(
                message: NSLocalizedString(
                    "Could not extract text.\nPlease try again.",
                    comment: "Error shown when OCR fails to extract text"
                )
            )
        }
    }

    private func handleRecognizedText(_ text: String) async {
        guard !Task.isCancelled else { return }
        let trimmed = text.trimmingCharacters(in: .newlines)

        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.shared.warning("No text recognized from selection.")
            presentErrorAlert(
                message: NSLocalizedString(
                    "Text could not be detected. Please try another area.",
                    comment: "Error shown when no text is detected during OCR capture"
                )
            )
            return
        }

        let copied = await clipboardService.copyRecognizedText(trimmed)
        guard !Task.isCancelled else { return }
        guard copied else {
            Logger.shared.error("Failed to copy recognized text to the clipboard.")
            presentErrorAlert(message: NSLocalizedString(
                "Could not copy the recognized text. Please try again.",
                comment: "Error shown when OCR text cannot be copied"
            ))
            return
        }
        windowManager.openMainWindow()
        windowManager.showCopiedNotification()
    }

    private func presentErrorAlert(message: String) {
        if let errorPresenter {
            errorPresenter(message)
            return
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("OCR Error", comment: "Alert title for OCR failures")
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button title"))
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
                preflight: {
                    let granted = CGPreflightScreenCaptureAccess()
                    SystemDiagnostics.permissions(
                        screenCapture: granted,
                        accessibility: AXIsProcessTrusted(),
                        clipboard: NSPasteboard.general.accessBehavior
                    )
                    return granted
                },
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
    func test_handleRecognizedText(_ text: String) async {
        await handleRecognizedText(text)
    }

    func test_isAwaitingPermission() -> Bool {
        isAwaitingPermission
    }

    func test_captureTask() -> Task<Void, Never>? {
        captureTask
    }
}
#endif
