import AppKit
import XCTest
@testable import Kipple

@MainActor
final class ComparisonClipboardCopyTests: XCTestCase {
    private let sourceType = NSPasteboard.PasteboardType("org.chromium.source-url")
    private let amazon = URL(string: "https://www.amazon.co.jp/dp/B0DM5V6R8G/")!

    func testCopiesAmazonSelectionWithItsNativeNewlineAndPreservesOriginalFormatsAndHistory() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard) { .alwaysAllow }
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        let title = "Anker Nano USB-C & HDMI ケーブル (4K, 高耐久ナイロン, 140W) 0.9m"
        let subtitle = "4K 60Hz出力, 140W PDパススルー充電, 2in1 iPhone 18 / 17 / 16シリーズ Galaxy iPad Pro MacBook Pro/Air 各種対応"
        let text = title + "\n" + subtitle
        write(text, to: pasteboard)
        XCTAssertTrue(pasteboard.setData(Data("<b>Original rich text</b>".utf8), forType: .html))
        XCTAssertTrue(pasteboard.setString(amazon.absoluteString, forType: sourceType))
        await service.checkClipboardForTesting()
        let history = await service.getHistory()
        let stamp = reader.observation
        let backup = try XCTUnwrap(PasteboardSnapshot(pasteboard: pasteboard, changeCount: stamp.changeCount))
        let input = comparisonInput(title + subtitle, page: amazon)
        let result = await service.performClipboardComparison(at: stamp) {
            await ComparisonClipboardCopy.capture(reader: reader, stamp: stamp, input: input, isCurrent: { true }, sendCopy: {
                self.write(text, to: pasteboard)
                return pasteboard.setString(self.amazon.absoluteString, forType: self.sourceType)
            })
        }

        guard case .restored(let selection, let restored, false) = result else { return XCTFail("Expected a comparison") }
        XCTAssertEqual(selection, text)
        XCTAssertTrue(TextComparison(clipboard: text, selection: selection).changeRows.isEmpty)
        XCTAssertEqual(reader.observation, restored)
        let after = try XCTUnwrap(PasteboardSnapshot(pasteboard: pasteboard, changeCount: restored.changeCount))
        XCTAssertEqual(after.items, backup.items)
        await service.checkClipboardForTesting()
        let finalHistory = await service.getHistory()
        XCTAssertEqual(finalHistory.map(\.id), history.map(\.id))
        XCTAssertEqual(finalHistory.map(\.timestamp), history.map(\.timestamp))
        XCTAssertEqual(finalHistory.map(\.content), [text])
    }

    func testOtherCopyFromTheSamePageTakesPriorityBeforeTheComparisonCopyIsAttributed() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard) { .alwaysAllow }
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        write("Original", to: pasteboard)
        await service.checkClipboardForTesting()
        let stamp = reader.observation
        let input = comparisonInput("Selected", page: amazon)

        let result = await service.performClipboardComparison(at: stamp) {
            await ComparisonClipboardCopy.capture(reader: reader, stamp: stamp, input: input, isCurrent: { true }, sendCopy: {
                self.write("A newer copy", to: pasteboard)
                return pasteboard.setString(self.amazon.absoluteString, forType: self.sourceType)
            })
        }

        guard case .interrupted = result else { return XCTFail("Expected the newer copy to interrupt") }
        XCTAssertEqual(pasteboard.string(forType: .string), "A newer copy")
        await service.checkClipboardForTesting()
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), ["A newer copy", "Original"])
    }

    func testCopyArrivingAfterAnAttributedComparisonCopySurvivesRestorationAndIsRecorded() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readText: {
            let text = pasteboard.string(forType: .string)
            if text == "Selected" {
                Task { @MainActor in self.write("A newer copy", to: pasteboard) }
            }
            return text
        })
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        write("Original", to: pasteboard)
        await service.checkClipboardForTesting()
        let stamp = reader.observation
        let input = comparisonInput("Selected")

        let result = await service.performClipboardComparison(at: stamp) {
            await ComparisonClipboardCopy.capture(reader: reader, stamp: stamp, input: input, isCurrent: { true }, sendCopy: {
                self.write("Selected", to: pasteboard)
                return true
            })
        }

        guard case .interrupted = result else { return XCTFail("Expected the newer copy to interrupt restoration") }
        XCTAssertEqual(pasteboard.string(forType: .string), "A newer copy")
        await service.checkClipboardForTesting()
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), ["A newer copy", "Original"])
    }

    func testClipboardChangeBeforeDispatchCancelsWithoutSendingCopy() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard) { .alwaysAllow }
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        write("Original", to: pasteboard)
        let stamp = reader.observation
        write("A newer copy", to: pasteboard)

        let result = await service.performClipboardComparison(at: stamp) {
            XCTFail("Should not dispatch a copy after the clipboard changes")
            return .noSelection
        }

        guard case .interrupted = result else { return XCTFail("Expected the newer copy to interrupt") }
        XCTAssertEqual(pasteboard.string(forType: .string), "A newer copy")
    }

    func testHistoryPollDuringComparisonSkipsTemporaryTextButKeepsTheNextRegularCopy() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard) { .alwaysAllow }
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        write("Original", to: pasteboard)
        await service.checkClipboardForTesting()
        let stamp = reader.observation
        let input = comparisonInput("Selected")
        var poll: Task<Void, Never>?
        var clipboardRead: Task<String?, Never>?
        let result = await service.performClipboardComparison(at: stamp) {
            await ComparisonClipboardCopy.capture(reader: reader, stamp: stamp, input: input, isCurrent: { true }, sendCopy: {
                self.write("Selected", to: pasteboard)
                poll = Task { await service.checkClipboardForTesting() }
                clipboardRead = Task { await service.getCurrentClipboardContent() }
                return true
            })
        }

        guard case .restored("Selected", _, false) = result else { return XCTFail("Expected a comparison") }
        await poll?.value
        let currentClipboard = await clipboardRead?.value
        XCTAssertEqual(currentClipboard, "Original")
        let afterComparison = await service.getHistory()
        XCTAssertEqual(afterComparison.map(\.content), ["Original"])

        write("Selected", to: pasteboard)
        await service.checkClipboardForTesting()
        let afterCopy = await service.getHistory()
        XCTAssertEqual(afterCopy.map(\.content), ["Selected", "Original"])
    }

    func testComparisonRestoresAnEmptyClipboardAndDoesNotSaveTheSelection() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard) { .alwaysAllow }
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        try await service.createHistoryItem(title: nil, content: "History item", categoryChanges: [:])
        let stamp = reader.observation
        let input = comparisonInput("Selected")
        let result = await service.performClipboardComparison(at: stamp) {
            await ComparisonClipboardCopy.capture(reader: reader, stamp: stamp, input: input, isCurrent: { true }, sendCopy: {
                self.write("Selected", to: pasteboard)
                return true
            })
        }

        guard case .restored("Selected", _, false) = result else { return XCTFail("Expected a comparison") }
        XCTAssertEqual(pasteboard.pasteboardItems?.count, 0)
        await service.checkClipboardForTesting()
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), ["History item"])
    }

    func testComparisonMatchesOnlyProvenListDecorationsFromTheSamePage() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard) { .alwaysAllow }
        let cases: [(input: String, marker: Character)] = [
            ("• 項目 A\n• 項目 B\n• 項目 C", "•"),
            ("項目 A\u{E506}\n\u{E506}項目 B\u{E506}\n\u{E506}項目 C", "\u{E506}")
        ]
        for item in cases {
            var input = comparisonInput(item.input, page: amazon)
            write("項目 A\n\n項目 B\n\n項目 C", to: pasteboard)
            XCTAssertTrue(pasteboard.setString(amazon.absoluteString, forType: sourceType))
            let exact = try XCTUnwrap(reader.read())
            XCTAssertFalse(input.matches(exact))
            input.listMarkers = [item.marker]
            XCTAssertTrue(input.matches(exact))

            write("項目 A\n\n項目 D\n\n項目 C", to: pasteboard)
            XCTAssertTrue(pasteboard.setString(amazon.absoluteString, forType: sourceType))
            XCTAssertFalse(input.matches(try XCTUnwrap(reader.read())))

            write("項目 A\n\n項目 B\n\n項目 C", to: pasteboard)
            XCTAssertTrue(pasteboard.setString("https://example.com/other", forType: sourceType))
            XCTAssertFalse(input.matches(try XCTUnwrap(reader.read())))
        }
    }

    func testEmbeddedObjectSelectionIsRejectedBeforeAnyClipboardWrite() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: pasteboard) { .alwaysAllow }
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        write("Original", to: pasteboard)
        await service.checkClipboardForTesting()
        let stamp = reader.observation
        let input = comparisonInput("Selected \u{FFFC} text")
        let result = await service.performClipboardComparison(at: stamp) {
            await ComparisonClipboardCopy.capture(reader: reader, stamp: stamp, input: input, isCurrent: { true }, sendCopy: {
                XCTFail("Unverified embedded objects must not trigger a clipboard write")
                return false
            })
        }
        guard case .unsupportedSelection = result else { return XCTFail("Expected an unsupported selection") }
        XCTAssertEqual(reader.observation, stamp)
        XCTAssertEqual(pasteboard.string(forType: .string), "Original")
        await service.checkClipboardForTesting()
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), ["Original"])
    }

    private func write(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(text, forType: .string))
    }

    private func comparisonInput(_ selection: String, page: URL? = nil) -> ClipboardReader.ComparisonInput {
        .init(text: selection, bundleID: "com.google.Chrome", webPageURL: page, windowBounds: nil)
    }
}
