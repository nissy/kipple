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
    private let clipboardService: any ClipboardServiceProtocol
    private let textRecognitionService: any TextRecognitionServiceProtocol
    private let windowManager: WindowManaging
    private var overlayController: ScreenSelectionOverlayController?

    init(
        clipboardService: any ClipboardServiceProtocol,
        textRecognitionService: any TextRecognitionServiceProtocol,
        windowManager: WindowManaging
    ) {
        self.clipboardService = clipboardService
        self.textRecognitionService = textRecognitionService
        self.windowManager = windowManager
    }

    func startCaptureFlow() {
        Logger.shared.info("Starting OCR capture flow.")

        guard ensureScreenCapturePermission() else {
            presentPermissionAlert()
            return
        }

        if overlayController != nil {
            // 既存セッションを強制的にキャンセルしてから再開
            overlayController?.cancel()
            overlayController = nil
        }

        let controller = ScreenSelectionOverlayController(
            onSelection: { [weak self] rect, screen in
                Task { @MainActor [weak self] in
                    self?.handleSelection(rect: rect, screen: screen)
                }
            },
            onCancel: { [weak self] in
                self?.overlayController = nil
            }
        )

        overlayController = controller
        controller.present()
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

    private func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        Logger.shared.warning("Screen capture access not granted. Requesting permission.")
        return CGRequestScreenCaptureAccess() && CGPreflightScreenCaptureAccess()
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

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
        Enable Kipple in System Settings > Privacy & Security > Screen Recording.
        Restart the app after granting access.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
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

#if DEBUG
extension TextCaptureCoordinator {
    func test_handleRecognizedText(_ text: String) {
        handleRecognizedText(text)
    }
}
#endif
