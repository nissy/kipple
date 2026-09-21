import AppKit
import XCTest
@testable import Kipple

@MainActor
final class PlainTextPasteControllerTests: XCTestCase {
    func testDelayedReceiverStillReadsPlainText() async {
        putStyledText()
        let received = expectation(description: "Receiving application reads after 650ms")
        let controller = makeController { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(650))
                XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Styled text")
                XCTAssertNil(ClipboardRichText(pasteboard: .general))
                received.fulfill()
            }
            return true
        }
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        await fulfillment(of: [received], timeout: 3)
    }

    func testNewCopyAfterPasteRequestIsNeverOverwritten() async {
        putStyledText()
        let controller = makeController { _ in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("New external copy", forType: .string)
            NSPasteboard.general.setString("<b>New external copy</b>", forType: .html)
            return true
        }
        let completions = PasteCompletionRecorder()
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        let newChangeCount = NSPasteboard.general.changeCount
        try? await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "New external copy")
        XCTAssertEqual(NSPasteboard.general.changeCount, newChangeCount)
        XCTAssertNotNil(ClipboardRichText(pasteboard: .general))
        XCTAssertTrue(completions.contents.isEmpty, "A changed clipboard must not advance the paste queue")
    }

    func testNewCopyDuringPreparationCancelsStaleReplacement() async {
        putStyledText()
        let controller = PlainTextPasteController(clipboardService: makeAdapter(), isTargetActive: { _ in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("New external copy", forType: .string)
            NSPasteboard.general.setString("<b>New external copy</b>", forType: .html)
            return true
        }, sendPaste: { _ in
            XCTFail("A stale request must not overwrite or paste the new clipboard")
            return true
        }, normalPasteMonitor: RecoveryPasteMonitor())
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "New external copy")
        XCTAssertNotNil(ClipboardRichText(pasteboard: .general))
    }

    func testRepeatedRequestsAreAllPerformedInOrder() async {
        putStyledText()
        var processIDs: [pid_t] = []
        let controller = makeController { target in
            processIDs.append(target)
            XCTAssertNil(ClipboardRichText(pasteboard: .general))
            return true
        }
        let completions = PasteCompletionRecorder()
        controller.paste(into: 101)
        controller.paste(into: 102)
        controller.paste(into: 103)
        await controller.waitForPendingPastes()
        XCTAssertEqual(processIDs, [101, 102, 103])
        XCTAssertEqual(completions.contents, Array(repeating: "Styled text", count: 3))
        controller.paste(into: 104)
        await controller.waitForPendingPastes()
        XCTAssertEqual(processIDs, [101, 102, 103, 104])
    }

    func testFailedKeyDeliveryReportsFailureWithoutAdvancingQueue() async {
        putStyledText()
        let controller = makeController { _ in false }
        var failureCount = 0
        controller.onFailure = { _ in failureCount += 1 }
        let completions = PasteCompletionRecorder()
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        XCTAssertEqual(failureCount, 1)
        XCTAssertTrue(completions.contents.isEmpty)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Styled text")
        XCTAssertNil(ClipboardRichText(pasteboard: .general))
    }

    func testChangingForegroundAppKeepsClipboardUntouched() async {
        putStyledText()
        let changeCount = NSPasteboard.general.changeCount
        let controller = PlainTextPasteController(
            clipboardService: makeAdapter(), isTargetActive: { _ in false }, sendPaste: { _ in
                XCTFail("Focus changed before replacing the clipboard")
                return true
            }, normalPasteMonitor: RecoveryPasteMonitor()
        )
        let completions = PasteCompletionRecorder()
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        XCTAssertTrue(completions.contents.isEmpty)
        XCTAssertEqual(NSPasteboard.general.changeCount, changeCount)
        XCTAssertNotNil(ClipboardRichText(pasteboard: .general))
    }

    func testNonTextClipboardIsNotClearedOrPasted() async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(Data([1, 2, 3]), forType: .png)
        let changeCount = NSPasteboard.general.changeCount
        let controller = makeController { _ in
            XCTFail("Plain text paste must not send a normal image paste")
            return true
        }
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        XCTAssertEqual(NSPasteboard.general.changeCount, changeCount)
        XCTAssertEqual(NSPasteboard.general.data(forType: .png), Data([1, 2, 3]))
    }

    func testSameCopyAlternatesPlainAndRichUsingOnlyNormalPaste() async throws {
        putStyledText()
        let original = try XCTUnwrap(ClipboardRichText(pasteboard: .general))
        let extraType = NSPasteboard.PasteboardType("com.example.original-representation")
        NSPasteboard.general.setData(Data([4, 5, 6]), forType: extraType)
        let monitor = RecoveryPasteMonitor()
        var receivedBold: [Bool] = []
        let controller = PlainTextPasteController(
            clipboardService: makeAdapter(), isTargetActive: { _ in true }, sendPaste: { _ in
                let receiver = NSTextView()
                receiver.paste(nil)
                XCTAssertEqual(receiver.string, "Styled text")
                let font = receiver.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                receivedBold.append(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false)
                return true
            }, normalPasteMonitor: monitor
        )
        let styles = [true, true, false, false, true, false]
        for plain in styles {
            controller.paste(into: 101, removingFormatting: plain)
            await controller.waitForPendingPastes()
            XCTAssertEqual(ClipboardRichText(pasteboard: .general), plain ? nil : original)
            XCTAssertEqual(NSPasteboard.general.data(forType: extraType), plain ? nil : Data([4, 5, 6]))
            XCTAssertEqual(monitor.isMonitoring, plain)
        }
        XCTAssertEqual(receivedBold, styles.map { !$0 })
    }

    func testCommandVConflictCancelsBeforeRemovingFormatting() async {
        putStyledText()
        let original = ClipboardRichText(pasteboard: .general)
        let count = NSPasteboard.general.changeCount
        let monitor = RecoveryPasteMonitor()
        monitor.canStart = false
        var failures: [PlainTextPasteController.Failure] = []
        let controller = PlainTextPasteController(
            clipboardService: makeAdapter(), isTargetActive: { _ in true },
            sendPaste: { _ in XCTFail("No paste after shortcut reservation failed"); return false },
            normalPasteMonitor: monitor
        )
        controller.onFailure = { failures.append($0) }
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        XCTAssertEqual(failures, [.normalPasteUnavailable])
        XCTAssertEqual(NSPasteboard.general.changeCount, count)
        XCTAssertEqual(ClipboardRichText(pasteboard: .general), original)
    }

    func testNewImageCopyIsPassedThroughInsteadOfRestoringOldText() async {
        putStyledText()
        let monitor = RecoveryPasteMonitor()
        var requests = 0
        let controller = PlainTextPasteController(
            clipboardService: makeAdapter(), isTargetActive: { _ in true },
            sendPaste: { _ in requests += 1; return true }, normalPasteMonitor: monitor
        )
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        XCTAssertTrue(monitor.isMonitoring)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(Data([1, 2, 3]), forType: .png)
        let count = NSPasteboard.general.changeCount
        controller.paste(into: 101, removingFormatting: false)
        await controller.waitForPendingPastes()
        XCTAssertEqual(requests, 2)
        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertEqual(NSPasteboard.general.changeCount, count)
        XCTAssertEqual(NSPasteboard.general.data(forType: .png), Data([1, 2, 3]))
        XCTAssertNil(NSPasteboard.general.string(forType: .string))
    }

    func testSnapshotRechecksOwnershipImmediatelyBeforeRestoring() throws {
        putStyledText()
        let snapshot = try XCTUnwrap(PasteboardSnapshot(
            pasteboard: .general, changeCount: NSPasteboard.general.changeCount
        ))
        let result = snapshot.write(to: .general) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("New copy during preparation", forType: .string)
            return false
        }
        XCTAssertEqual(result, -1)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "New copy during preparation")
    }

    func testRevokingPermissionReleasesCommandVAndRegrantingRestoresRecovery() async {
        putStyledText()
        let original = ClipboardRichText(pasteboard: .general)
        let monitor = RecoveryPasteMonitor()
        let controller = PlainTextPasteController(
            clipboardService: makeAdapter(), isTargetActive: { _ in true }, sendPaste: { _ in true },
            normalPasteMonitor: monitor
        )
        controller.paste(into: 101)
        await controller.waitForPendingPastes()
        let plainCount = NSPasteboard.general.changeCount
        monitor.hasPermission = false
        controller.refreshRecoveryState()
        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertEqual(NSPasteboard.general.changeCount, plainCount, "Permission changes must not restore on a timer")
        monitor.hasPermission = true
        controller.refreshRecoveryState()
        XCTAssertTrue(monitor.isMonitoring)
        controller.paste(into: 101, removingFormatting: false)
        await controller.waitForPendingPastes()
        XCTAssertEqual(ClipboardRichText(pasteboard: .general), original)
    }

    private func makeController(sendPaste: @escaping (pid_t) -> Bool) -> PlainTextPasteController {
        PlainTextPasteController(
            clipboardService: makeAdapter(), isTargetActive: { _ in true }, sendPaste: sendPaste,
            normalPasteMonitor: RecoveryPasteMonitor()
        )
    }

    private func makeAdapter() -> ModernClipboardServiceAdapter {
        ModernClipboardServiceAdapter(
            modernService: ModernClipboardService(testRepository: MockClipboardRepository()),
            refreshPeriodically: false
        )
    }

    private func putStyledText() {
        NSPasteboard.general.clearContents()
        let item = NSPasteboardItem()
        item.setString("Styled text", forType: .string)
        item.setString("<b>Styled text</b>", forType: .html)
        let styled = NSAttributedString(string: "Styled text", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
        let rtf = try? styled.data(
            from: NSRange(location: 0, length: styled.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        XCTAssertNotNil(rtf)
        if let rtf { item.setData(rtf, forType: .rtf) }
        NSPasteboard.general.writeObjects([item])
        XCTAssertNotNil(ClipboardRichText(pasteboard: .general))
    }
}

extension PlainTextPasteControllerTests {
    func testSwappedShortcutsAlternateFormattingWithoutRecopying() async throws {
        putStyledText()
        let original = try XCTUnwrap(ClipboardRichText(pasteboard: .general))
        let monitor = RecoveryPasteMonitor()
        var receivedBold: [Bool] = []
        let controller = PlainTextPasteController(
            clipboardService: makeAdapter(), isTargetActive: { _ in true }, sendPaste: { _ in
                let receiver = NSTextView()
                receiver.paste(nil)
                XCTAssertEqual(receiver.string, "Styled text")
                let font = receiver.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                receivedBold.append(font.map { NSFontManager.shared.traits(of: $0).contains(.boldFontMask) } ?? false)
                return true
            }, normalPasteMonitor: monitor
        )
        let count = NSPasteboard.general.changeCount
        XCTAssertTrue(controller.configureShortcuts(swapsFormatting: true))
        XCTAssertTrue(monitor.isMonitoring, "Swapping must reserve Command+V before any plain paste")
        XCTAssertEqual(NSPasteboard.general.changeCount, count, "Changing the setting must not rewrite the clipboard")
        let shortcuts: [PlainTextPasteController.Shortcut] = [.normal, .normal, .alternate, .normal, .alternate]
        for shortcut in shortcuts {
            controller.paste(using: shortcut, into: 101)
            await controller.waitForPendingPastes()
            XCTAssertEqual(ClipboardRichText(pasteboard: .general), shortcut == .normal ? nil : original)
            XCTAssertTrue(monitor.isMonitoring, "Command+V must remain reserved after rich paste")
        }
        XCTAssertEqual(receivedBold, [false, false, true, false, true])
    }

    func testChangingShortcutRolesKeepsRetainedFormattingUntilNextPaste() async {
        putStyledText()
        let original = ClipboardRichText(pasteboard: .general)
        let monitor = RecoveryPasteMonitor()
        let controller = PlainTextPasteController(
            clipboardService: makeAdapter(), isTargetActive: { _ in true }, sendPaste: { _ in true },
            normalPasteMonitor: monitor
        )
        controller.paste(using: .alternate, into: 101)
        await controller.waitForPendingPastes()
        let count = NSPasteboard.general.changeCount
        XCTAssertTrue(controller.configureShortcuts(swapsFormatting: true))
        XCTAssertTrue(controller.configureShortcuts(swapsFormatting: false))
        XCTAssertEqual(NSPasteboard.general.changeCount, count)
        XCTAssertTrue(monitor.isMonitoring, "Turning swapping off must still allow recovery with Command+V")
        controller.paste(using: .normal, into: 101)
        await controller.waitForPendingPastes()
        XCTAssertEqual(ClipboardRichText(pasteboard: .general), original)
        XCTAssertFalse(monitor.isMonitoring)
    }

    func testSwappedCommandVPreservesNewImagesAndFiles() async {
        putStyledText()
        let monitor = RecoveryPasteMonitor()
        var pastes = 0
        let controller = PlainTextPasteController(
            clipboardService: makeAdapter(), isTargetActive: { _ in true },
            sendPaste: { _ in pastes += 1; return true }, normalPasteMonitor: monitor
        )
        XCTAssertTrue(controller.configureShortcuts(swapsFormatting: true))
        controller.paste(using: .normal, into: 101)
        await controller.waitForPendingPastes()
        for type in [NSPasteboard.PasteboardType.png, .fileURL] {
            NSPasteboard.general.clearContents()
            if type == .fileURL {
                NSPasteboard.general.writeObjects([NSURL(fileURLWithPath: NSTemporaryDirectory())])
                NSPasteboard.general.setString("File name", forType: .string)
            } else {
                NSPasteboard.general.setData(Data([1, 2, 3]), forType: type)
            }
            let data = NSPasteboard.general.data(forType: type)
            XCTAssertNotNil(data)
            let count = NSPasteboard.general.changeCount
            controller.paste(using: .normal, into: 101)
            await controller.waitForPendingPastes()
            XCTAssertEqual(NSPasteboard.general.changeCount, count)
            XCTAssertEqual(NSPasteboard.general.data(forType: type), data)
            XCTAssertTrue(monitor.isMonitoring)
        }
        XCTAssertEqual(pastes, 3)
    }

    func testSwappedShortcutReservationHandlesConflictSuspensionAndPermissionChanges() {
        let monitor = RecoveryPasteMonitor()
        let controller = PlainTextPasteController(clipboardService: makeAdapter(), normalPasteMonitor: monitor)
        monitor.canStart = false
        XCTAssertFalse(controller.configureShortcuts(swapsFormatting: true))
        XCTAssertFalse(controller.swapsPasteFormatting)
        monitor.canStart = true
        XCTAssertTrue(controller.configureShortcuts(swapsFormatting: true))
        XCTAssertTrue(monitor.isMonitoring)
        XCTAssertTrue(controller.configureShortcuts(swapsFormatting: true, enabled: false))
        XCTAssertFalse(monitor.isMonitoring, "Recording a shortcut must release Command+V")
        XCTAssertTrue(controller.configureShortcuts(swapsFormatting: true))
        monitor.hasPermission = false
        controller.refreshRecoveryState()
        XCTAssertFalse(monitor.isMonitoring)
        monitor.hasPermission = true
        controller.refreshRecoveryState()
        XCTAssertTrue(monitor.isMonitoring, "Swapping must resume even before the first clipboard backup")
        XCTAssertTrue(controller.configureShortcuts(swapsFormatting: false))
        XCTAssertFalse(monitor.isMonitoring)
    }
}

@MainActor
private final class PasteCompletionRecorder {
    var contents: [String] = []
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .clipboardPasteSent, object: nil, queue: .main
        ) { [weak self] notification in
            let content = notification.object as? String
            MainActor.assumeIsolated {
                if let content { self?.contents.append(content) }
            }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

@MainActor
final class RecoveryPasteMonitor: PasteCommandMonitoring {
    var hasPermission = true
    var canStart = true
    private(set) var isMonitoring = false
    private(set) var handler: (() -> Void)?

    func start(handler: @escaping () -> Void) -> Bool {
        guard canStart, hasPermission else { return false }
        isMonitoring = true
        self.handler = handler
        return true
    }

    func stop() {
        isMonitoring = false
        handler = nil
    }
}
