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
    private let windowManager: WindowManager
    private var overlayController: ScreenSelectionOverlayController?

    init(
        clipboardService: any ClipboardServiceProtocol,
        textRecognitionService: any TextRecognitionServiceProtocol,
        windowManager: WindowManager
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
            presentErrorAlert(message: "画面キャプチャに失敗しました。システム環境設定の画面収録権限を確認してください。")
            return
        }

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
                    self?.presentErrorAlert(message: "テキスト抽出に失敗しました。\nもう一度お試しください。")
                }
            }
        }
    }

    private func handleRecognizedText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            Logger.shared.warning("No text recognized from selection.")
            presentErrorAlert(message: "テキストが検出できませんでした。別の範囲でお試しください。")
            return
        }

        clipboardService.copyToClipboard(trimmed, fromEditor: false)
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
        alert.messageText = "画面収録の許可が必要です"
        alert.informativeText = """
        システム設定 > プライバシーとセキュリティ > 画面収録 で Kipple にチェックを入れてください。
        許可後、アプリを再起動する必要があります。
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentErrorAlert(message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "OCRエラー"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
