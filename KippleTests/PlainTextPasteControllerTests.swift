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
        })
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
            }
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

    private func makeController(sendPaste: @escaping (pid_t) -> Bool) -> PlainTextPasteController {
        PlainTextPasteController(clipboardService: makeAdapter(), isTargetActive: { _ in true }, sendPaste: sendPaste)
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
        NSPasteboard.general.writeObjects([item])
        XCTAssertNotNil(ClipboardRichText(pasteboard: .general))
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
