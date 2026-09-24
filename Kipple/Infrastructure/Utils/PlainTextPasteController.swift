import AppKit
import ApplicationServices

extension Notification.Name {
    static let clipboardPasteSent = Notification.Name("KippleClipboardPasteSent")
    static let clipboardPasteRequested = Notification.Name("KippleClipboardPasteRequested")
}

@MainActor
protocol PasteQueueCoordinating: AnyObject {
    var pasteQueueEpoch: UInt64 { get }
    func nextQueuedItem() -> ClipItem?
    func didSendQueuedPaste(_ item: ClipItem)
}

@MainActor
final class PlainTextPasteController {
    enum Shortcut {
        case normal
        case alternate
    }

    enum Failure: Error {
        case historyUnavailable
        case clipboardUnavailable
        case deliveryFailed
        case normalPasteUnavailable
    }

    private struct Original {
        let item: ClipItem
        let snapshot: PasteboardSnapshot?
        let changeCount: Int
    }

    private struct PreparedPaste {
        let item: ClipItem
        let changeCount: Int
    }

    private let clipboardService: ModernClipboardServiceAdapter
    private let isTargetActive: (pid_t) -> Bool
    private let sendPaste: (pid_t) -> Bool
    private let normalPasteMonitor: any PasteCommandMonitoring
    private var isNormalPasteMonitorActive = false
    private var isQueuePasteMonitorActive = false
    private var original: Original?
    private var ownershipTimer: Timer?
    private var hadPastePermission = true
    private var shortcutsEnabled = true
    private(set) var swapsPasteFormatting = false
    private var task: Task<Void, Never>?
    var hasPendingPastes: Bool { task != nil }
    private var requestID: UInt64 = 0
    var onPermissionRequired: (() -> Void)?
    var onFailure: ((Failure) -> Void)?
    weak var queue: (any PasteQueueCoordinating)?

    init(
        clipboardService: ModernClipboardServiceAdapter,
        isTargetActive: @escaping (pid_t) -> Bool = {
            AXIsProcessTrusted() && NSWorkspace.shared.frontmostApplication?.processIdentifier == $0
        },
        sendPaste: @escaping (pid_t) -> Bool = { AutoPasteController.sendPasteCommand(to: $0) },
        normalPasteMonitor: any PasteCommandMonitoring = PasteCommandMonitor()
    ) {
        self.clipboardService = clipboardService
        self.isTargetActive = isTargetActive
        self.sendPaste = sendPaste
        self.normalPasteMonitor = normalPasteMonitor
    }

    @discardableResult
    func configureShortcuts(swapsFormatting: Bool, enabled: Bool = true) -> Bool {
        let previous = (swapsPasteFormatting, shortcutsEnabled)
        swapsPasteFormatting = swapsFormatting
        shortcutsEnabled = enabled
        if needsNormalPasteMonitor, !ensureNormalPasteMonitor() {
            (swapsPasteFormatting, shortcutsEnabled) = previous
            return false
        }
        if !needsNormalPasteMonitor { stopNormalPasteMonitor() }
        updateOwnershipObservation()
        return true
    }

    func paste(using shortcut: Shortcut, into target: pid_t? = nil) {
        let removesFormatting = shortcut == .normal ? swapsPasteFormatting : !swapsPasteFormatting
        if let target {
            paste(into: target, removingFormatting: removesFormatting, allowsNonTextPaste: shortcut == .normal)
        } else {
            paste(removingFormatting: removesFormatting, allowsNonTextPaste: shortcut == .normal)
        }
    }

    private func paste(removingFormatting: Bool, allowsNonTextPaste: Bool) {
        discardReplacedOriginal()
        if NSApp.isActive {
            NotificationCenter.default.post(name: .clipboardPasteRequested, object: self)
            let action = removingFormatting ? #selector(NSTextView.pasteAsPlainText(_:)) : #selector(NSTextView.paste(_:))
            NSApp.sendAction(action, to: nil, from: nil)
            return
        }
        guard AXIsProcessTrusted() else {
            stopNormalPasteMonitor()
            onPermissionRequired?()
            return
        }
        guard let target = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        paste(into: target, removingFormatting: removingFormatting, allowsNonTextPaste: allowsNonTextPaste)
    }

    func paste(into target: pid_t, removingFormatting: Bool = true, allowsNonTextPaste: Bool = false) {
        NotificationCenter.default.post(name: .clipboardPasteRequested, object: self)
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
            let pasteboard = NSPasteboard.general
            let hasText = pasteboard.availableType(from: [.string, .rtf, .rtfd, .html]) != nil
                && pasteboard.availableType(from: [.fileURL]) == nil
            let plain = removingFormatting && !(allowsNonTextPaste && !hasText && queue?.nextQueuedItem() == nil)
            await performPaste(into: target, removingFormatting: plain, queueEpoch: queueEpoch)
        }
    }

    /// The queue and formatting recovery share Command+V by transferring the reservation, never competing for it.
    func setQueuePasteMonitorActive(_ active: Bool) {
        isQueuePasteMonitorActive = active
        if active {
            stopNormalPasteMonitor()
        } else {
            discardReplacedOriginal()
            if needsNormalPasteMonitor, !ensureNormalPasteMonitor() { onFailure?(.normalPasteUnavailable) }
        }
    }

    private func performPaste(into target: pid_t, removingFormatting: Bool, queueEpoch: UInt64?) async {
        discardReplacedOriginal()
        let queuedItem = queue?.nextQueuedItem()
        if !removingFormatting, original == nil, queuedItem == nil {
            // A new external copy may be an image or a file. Pass normal paste through unchanged.
            if isTargetActive(target), !sendPaste(target) { onFailure?(.deliveryFailed) }
            return
        }
        let copyEpoch = clipboardService.copyEpoch
        var failure: Failure?
        var sentItem: ClipItem?
        var sentChangeCount: Int?
        let backupAvailable = await clipboardService.performClipboardPaste(of: queuedItem) { item, changeCount in
            let pasteboard = NSPasteboard.general
            self.discardReplacedOriginal()
            let canPaste = {
                !Task.isCancelled && self.isTargetActive(target)
                    && copyEpoch == self.clipboardService.copyEpoch
                    && queueEpoch == self.queue?.pasteQueueEpoch
                    && queuedItem?.id == self.queue?.nextQueuedItem()?.id
                    && pasteboard.changeCount == changeCount
            }
            guard let preparation = self.prepareClipboard(
                item, queuedItem: queuedItem, changeCount: changeCount,
                removingFormatting: removingFormatting, canPaste: canPaste
            ) else { return nil }
            let prepared: PreparedPaste
            switch preparation {
            case .success(let value): prepared = value
            case .failure(let error): failure = error; return nil
            }
            let writtenCount = prepared.changeCount
            if self.sendPaste(target) {
                if pasteboard.changeCount == writtenCount {
                    sentItem = prepared.item
                    sentChangeCount = writtenCount
                }
            } else {
                failure = .deliveryFailed
            }
            // Only the next explicit paste request may switch representations; there is no timed restoration.
            return writtenCount
        }
        discardReplacedOriginal()
        if !needsNormalPasteMonitor { stopNormalPasteMonitor() }
        if let sentItem, sentChangeCount == NSPasteboard.general.changeCount,
           copyEpoch == clipboardService.copyEpoch, queueEpoch == queue?.pasteQueueEpoch {
            if let queuedItem { queue?.didSendQueuedPaste(queuedItem) }
            NotificationCenter.default.post(name: .clipboardPasteSent, object: sentItem.content)
        }
        reportFailure(backupAvailable: backupAvailable, failure: failure)
    }

    private func reportFailure(backupAvailable: Bool, failure: Failure?) {
        if !backupAvailable {
            let reader = ClipboardReader.shared
            onFailure?(reader.accessBehavior == .alwaysDeny || reader.readFailed ? .clipboardUnavailable : .historyUnavailable)
        } else if let failure {
            onFailure?(failure)
        }
    }

    private func prepareClipboard(
        _ item: ClipItem,
        queuedItem: ClipItem?,
        changeCount: Int,
        removingFormatting: Bool,
        canPaste: () -> Bool
    ) -> Result<PreparedPaste, Failure>? {
        guard canPaste() else { return nil }
        let retained = queuedItem == nil ? original : nil
        let source = queuedItem ?? retained?.item ?? item
        var snapshot = retained?.snapshot
        if removingFormatting {
            if queuedItem == nil, snapshot == nil {
                snapshot = PasteboardSnapshot(pasteboard: .general, changeCount: changeCount)
                guard NSPasteboard.general.changeCount == changeCount else { return nil }
                guard snapshot != nil else { return .failure(.clipboardUnavailable) }
            }
            guard ensureNormalPasteMonitor() else { return .failure(.normalPasteUnavailable) }
        }
        let writtenCount = writeClipboard(source, snapshot: snapshot, removingFormatting: removingFormatting, canPaste: canPaste)
        guard writtenCount >= 0 else { return nil }
        if removingFormatting {
            original = Original(item: source, snapshot: snapshot, changeCount: writtenCount)
            updateOwnershipObservation()
        } else {
            clearOriginal()
        }
        return .success(PreparedPaste(item: source, changeCount: writtenCount))
    }

    private func writeClipboard(
        _ source: ClipItem, snapshot: PasteboardSnapshot?, removingFormatting: Bool, canPaste: () -> Bool
    ) -> Int {
        if !removingFormatting, let snapshot { return snapshot.write(to: .general, shouldWrite: canPaste) }
        var output = source
        if removingFormatting { output.richText = nil }
        return ClipboardRichText.write(output, to: .general, shouldWrite: canPaste)
    }

    private func ensureNormalPasteMonitor() -> Bool {
        guard shortcutsEnabled else { return false }
        if isQueuePasteMonitorActive || isNormalPasteMonitorActive { return true }
        isNormalPasteMonitorActive = normalPasteMonitor.start { [weak self] in
            self?.paste(using: .normal)
        }
        return isNormalPasteMonitorActive
    }

    private func stopNormalPasteMonitor() {
        if isNormalPasteMonitorActive { normalPasteMonitor.stop() }
        isNormalPasteMonitorActive = false
    }

    private func discardReplacedOriginal() {
        guard let original else { return }
        if original.changeCount != NSPasteboard.general.changeCount {
            clearOriginal()
        }
    }

    private func clearOriginal() {
        original = nil
        updateOwnershipObservation()
        if !needsNormalPasteMonitor { stopNormalPasteMonitor() }
    }

    private var needsNormalPasteMonitor: Bool {
        shortcutsEnabled && (swapsPasteFormatting || original != nil) && !isQueuePasteMonitorActive
    }

    private func updateOwnershipObservation() {
        guard swapsPasteFormatting || original != nil else {
            ownershipTimer?.invalidate()
            ownershipTimer = nil
            return
        }
        guard ownershipTimer == nil else { return }
        // Observation only releases stale data and the shortcut. It never writes to the clipboard.
        ownershipTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshRecoveryState() }
        }
    }

    func refreshRecoveryState() {
        discardReplacedOriginal()
        guard swapsPasteFormatting || original != nil else { return }
        let permission = normalPasteMonitor.hasPermission
        guard permission != hadPastePermission else { return }
        hadPastePermission = permission
        if permission, needsNormalPasteMonitor {
            if !ensureNormalPasteMonitor() { onFailure?(.normalPasteUnavailable) }
        } else {
            stopNormalPasteMonitor()
        }
    }

    isolated deinit {
        ownershipTimer?.invalidate()
        normalPasteMonitor.stop()
    }

    #if DEBUG
    func waitForPendingPastes() async { await task?.value }
    #endif
}
