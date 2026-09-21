import AppKit
import ApplicationServices

extension Notification.Name {
    static let clipboardPasteSent = Notification.Name("KippleClipboardPasteSent")
}

@MainActor
protocol PasteQueueCoordinating: AnyObject {
    var pasteQueueEpoch: UInt64 { get }
    func nextQueuedItem() -> ClipItem?
    func didSendQueuedPaste(_ item: ClipItem)
}

@MainActor
final class PlainTextPasteController {
    enum Failure {
        case historyUnavailable
        case deliveryFailed
    }

    private let clipboardService: ModernClipboardServiceAdapter
    private let isTargetActive: (pid_t) -> Bool
    private let sendPaste: (pid_t) -> Bool
    private var task: Task<Void, Never>?
    private var requestID: UInt64 = 0
    var onPermissionRequired: (() -> Void)?
    var onFailure: ((Failure) -> Void)?
    weak var queue: (any PasteQueueCoordinating)?

    init(
        clipboardService: ModernClipboardServiceAdapter,
        isTargetActive: @escaping (pid_t) -> Bool = {
            AXIsProcessTrusted() && NSWorkspace.shared.frontmostApplication?.processIdentifier == $0
        },
        sendPaste: @escaping (pid_t) -> Bool = { AutoPasteController.sendPasteCommand(to: $0) }
    ) {
        self.clipboardService = clipboardService
        self.isTargetActive = isTargetActive
        self.sendPaste = sendPaste
    }

    func paste(removingFormatting: Bool = true) {
        if NSApp.isActive {
            let action = removingFormatting ? #selector(NSTextView.pasteAsPlainText(_:)) : #selector(NSTextView.paste(_:))
            NSApp.sendAction(action, to: nil, from: nil)
            return
        }
        guard AXIsProcessTrusted() else {
            onPermissionRequired?()
            return
        }
        guard let target = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        paste(into: target, removingFormatting: removingFormatting)
    }

    func paste(into target: pid_t, removingFormatting: Bool = true) {
        requestID &+= 1
        let currentRequestID = requestID
        let copyEpoch = clipboardService.copyEpoch
        let queueEpoch = queue?.pasteQueueEpoch
        let previous = task
        task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            defer { if requestID == currentRequestID { task = nil } }
            guard copyEpoch == clipboardService.copyEpoch, queueEpoch == queue?.pasteQueueEpoch else { return }
            await performPaste(into: target, removingFormatting: removingFormatting, queueEpoch: queueEpoch)
        }
    }

    private func performPaste(into target: pid_t, removingFormatting: Bool, queueEpoch: UInt64?) async {
        var failed = false
        let queuedItem = queue?.nextQueuedItem()
        let copyEpoch = clipboardService.copyEpoch
        var sentItem: ClipItem?
        var sentChangeCount: Int?
        let backupAvailable = await clipboardService.performClipboardPaste(of: queuedItem) { item, changeCount in
            let pasteboard = NSPasteboard.general
            var output = item
            if removingFormatting { output.richText = nil }
            var writeAuthorized = false
            let writtenChangeCount = ClipboardRichText.write(output, to: pasteboard) {
                writeAuthorized = !Task.isCancelled && self.isTargetActive(target)
                    && queueEpoch == self.queue?.pasteQueueEpoch
                    && queuedItem?.id == self.queue?.nextQueuedItem()?.id
                    && pasteboard.changeCount == changeCount
                return writeAuthorized
            }
            guard writtenChangeCount >= 0 else {
                failed = writeAuthorized
                return writeAuthorized ? pasteboard.changeCount : nil
            }
            if self.sendPaste(target) {
                if pasteboard.changeCount == writtenChangeCount {
                    sentItem = item
                    sentChangeCount = writtenChangeCount
                }
            } else {
                failed = true
            }
            // Leave plain text available even if the receiving app reads it much later.
            return writtenChangeCount
        }
        if let sentItem, sentChangeCount == NSPasteboard.general.changeCount,
           copyEpoch == clipboardService.copyEpoch, queueEpoch == queue?.pasteQueueEpoch {
            // Sending a key is not a receipt. Only advance the logical queue; keep this clipboard intact.
            if let queuedItem { queue?.didSendQueuedPaste(queuedItem) }
            NotificationCenter.default.post(name: .clipboardPasteSent, object: sentItem.content)
        }
        // A modal explanation must not keep clipboard monitoring and new copies waiting.
        if !backupAvailable { onFailure?(.historyUnavailable) } else if failed { onFailure?(.deliveryFailed) }
    }

    #if DEBUG
    func waitForPendingPastes() async { await task?.value }
    #endif
}
