import AppKit
import XCTest
@testable import Kipple

@MainActor
final class ClipboardTextLimitTests: XCTestCase {
    private let boundary = String(repeating: "e\u{301}", count: 40_000)

    func testClipboardHistoryAcceptsEightyThousandCodePointsAndLeavesOversizedCopyIntact() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: board) { .alwaysAllow }
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        write(boundary, to: board)
        await service.checkClipboardForTesting()
        let initial = await service.getHistory()
        XCTAssertEqual(initial.map(\.content), [boundary])

        let warning = expectation(forNotification: .historyTextLimitExceeded, object: service)
        let oversized = boundary + "あ"
        write(oversized, to: board)
        let revision = board.changeCount
        await service.checkClipboardForTesting()
        await fulfillment(of: [warning], timeout: 1)
        let rejected = await service.getHistory()
        XCTAssertEqual(rejected.map(\.content), [boundary])
        XCTAssertEqual(board.string(forType: .string), oversized)
        XCTAssertEqual(board.changeCount, revision)

        write("Next copy", to: board)
        await service.checkClipboardForTesting()
        let next = await service.getHistory()
        XCTAssertEqual(next.map(\.content), ["Next copy", boundary])
    }

    func testManualSaveAndEditReturnAnErrorAndEditorBatchIsAtomic() async throws {
        let service = ModernClipboardService(testRepository: MockClipboardRepository())
        try await service.createHistoryItem(title: nil, content: boundary, categoryChanges: [:])
        let initial = await service.getHistory()
        let item = try XCTUnwrap(initial.first)
        let oversized = boundary + "あ"

        do {
            try await service.createHistoryItem(title: nil, content: oversized, categoryChanges: [:])
            XCTFail("Creation should reject excess text")
        } catch ClipItemEditError.contentTooLong {}

        do {
            try await service.updateDetails(id: item.id, content: oversized)
            XCTFail("Editing should reject excess text")
        } catch ClipItemEditError.contentTooLong {}

        let added = await service.addEditorItems(["One valid line", oversized])
        let final = await service.getHistory()
        XCTAssertTrue(added.isEmpty)
        XCTAssertEqual(final, initial)
    }

    func testExistingOversizedHistoryCanStillBeRenamedAndCopied() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let reader = ClipboardReader(pasteboard: board) { .alwaysAllow }
        let repository = MockClipboardRepository()
        let original = ClipItem(content: boundary + "あ")
        try await repository.applyChanges(inserted: [original], updated: [], removed: [])
        let service = ModernClipboardService(testRepository: repository, clipboardWriter: { item in
            ClipboardRichText.write(item, to: board)
        }, clipboardReader: reader)
        await service.loadHistoryFromRepository()
        try await service.updateDetails(id: original.id, title: "Legacy item")
        await service.recopyFromHistory(original)

        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), [original.content])
        XCTAssertEqual(history.first?.metadata?.title, "Legacy item")
        XCTAssertEqual(board.string(forType: .string), original.content)
    }

    func testComparisonEvaluatesActualCopiedLengthAfterRestoringClipboard() async {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        write("Original", to: board)
        let reader = ClipboardReader(pasteboard: board) { .alwaysAllow }
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        await service.checkClipboardForTesting()
        let stamp = reader.observation
        let input = ClipboardReader.ComparisonInput(text: boundary, bundleID: nil, webPageURL: nil, windowBounds: nil)
        let copied = boundary + "\n"
        let result = await service.performClipboardComparison(at: stamp) {
            await ComparisonClipboardCopy.capture(reader: reader, stamp: stamp, input: input, isCurrent: { true }, sendCopy: {
                self.write(copied, to: board)
                return true
            })
        }

        guard case let .restored(text, _, false) = result else { return XCTFail("Expected restoration before validation") }
        XCTAssertEqual(text, copied)
        XCTAssertTrue(ClipboardTextLimit.allows(input.text))
        XCTAssertFalse(ClipboardTextLimit.allows(text))
        XCTAssertEqual(board.string(forType: .string), "Original")
        await service.checkClipboardForTesting()
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), ["Original"])
    }

    private func write(_ text: String, to board: NSPasteboard) {
        board.clearContents()
        XCTAssertTrue(board.setString(text, forType: .string))
    }
}
