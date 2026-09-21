import AppKit
import XCTest
@testable import Kipple

@MainActor
final class ClipboardReaderTests: XCTestCase {
    func testDeniedReadIsNotAttemptedAndUnchangedClipboardRecoversAfterGrant() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Allowed later", forType: .string)
        let count = pasteboard.changeCount
        var policy: NSPasteboard.AccessBehavior = .alwaysDeny
        var reads = 0
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { policy }, readText: {
            reads += 1
            return pasteboard.string(forType: .string)
        })
        let repository = MockClipboardRepository()
        let service = ModernClipboardService(testRepository: repository, clipboardReader: reader)
        await service.checkClipboardForTesting()
        await service.checkClipboardForTesting()
        XCTAssertEqual(reads, 0)
        let before = await service.getHistory()
        XCTAssertTrue(before.isEmpty)

        policy = .alwaysAllow
        await service.checkClipboardForTesting()
        let after = await service.getHistory()
        XCTAssertEqual(after.map(\.content), ["Allowed later"])
        XCTAssertEqual(pasteboard.changeCount, count)
        XCTAssertEqual(reads, 1)
    }

    func testFailedReadDoesNotRepeatUntilExplicitRetry() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("Retry me", forType: .string)
        var available = false
        var reads = 0
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .ask }, readText: {
            reads += 1
            return available ? "Retry me" : nil
        })
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        await service.checkClipboardForTesting()
        await service.checkClipboardForTesting()
        XCTAssertTrue(reader.readFailed)
        XCTAssertEqual(reads, 1)
        available = true
        XCTAssertEqual(reader.read(retry: true)?.text, "Retry me")
        await service.checkClipboardForTesting()
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), ["Retry me"])
        XCTAssertEqual(reads, 2)
        XCTAssertFalse(reader.readFailed)
    }

    func testSuccessfulFirstReadSurvivesDefaultPolicyChangingToAsk() async {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("First allowed read", forType: .string)
        var policy: NSPasteboard.AccessBehavior = .default
        var reads = 0
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { policy }, readText: {
            reads += 1
            policy = .ask
            return "First allowed read"
        })
        let service = ModernClipboardService(testRepository: MockClipboardRepository(), clipboardReader: reader)
        await service.checkClipboardForTesting()
        let history = await service.getHistory()
        XCTAssertEqual(history.map(\.content), ["First allowed read"])
        XCTAssertEqual(reader.read()?.text, "First allowed read")
        XCTAssertEqual(reads, 1)
    }

    func testRevocationDropsCachedContentsAndGrantReadsAgain() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("Private", forType: .string)
        var policy: NSPasteboard.AccessBehavior = .alwaysAllow
        let readAccess = { policy }
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: readAccess)
        XCTAssertEqual(reader.read()?.text, "Private")
        policy = .alwaysDeny
        XCTAssertNil(reader.read())
        policy = .alwaysAllow
        XCTAssertEqual(reader.read()?.text, "Private")
    }

    func testCopyDuringReadIsRetriedWithoutReturningMixedContent() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("First", forType: .string)
        var reads = 0
        let reader = ClipboardReader(pasteboard: pasteboard, readAccess: { .alwaysAllow }, readText: {
            reads += 1
            if reads == 1 {
                pasteboard.clearContents()
                pasteboard.setString("Second", forType: .string)
                return "First"
            }
            return pasteboard.string(forType: .string)
        })
        XCTAssertNil(reader.read())
        XCTAssertEqual(reader.read()?.text, "Second")
    }
}
