import AppKit
import XCTest
@testable import Kipple

@MainActor
final class ApplicationTerminationControllerTests: XCTestCase {
    func testRepeatedQuitWaitsForOneSaveAndRepliesOnce() async {
        let started = expectation(description: "save started")
        let replied = expectation(description: "termination replied")
        var continuation: CheckedContinuation<Void, Never>?
        var replies: [Bool] = []
        var saveCount = 0
        let controller = ApplicationTerminationController(save: {
            saveCount += 1
            await withCheckedContinuation { continuation = $0; started.fulfill() }
        }, reply: { replies.append($0); replied.fulfill() }, onFailure: { _ in XCTFail("Unexpected failure") })

        XCTAssertEqual(controller.requestTermination(), .terminateLater)
        await fulfillment(of: [started], timeout: 1)
        XCTAssertEqual(controller.requestTermination(), .terminateLater)
        XCTAssertTrue(replies.isEmpty)
        XCTAssertEqual(saveCount, 1)
        continuation?.resume()
        await fulfillment(of: [replied], timeout: 1)
        XCTAssertEqual(replies, [true])
    }

    func testSaveFailureCancelsQuitAndAllowsRetry() async {
        let failed = expectation(description: "failure reported")
        let succeeded = expectation(description: "retry succeeded")
        var replies: [Bool] = []
        var saveCount = 0
        let controller = ApplicationTerminationController(save: {
            saveCount += 1
            if saveCount == 1 { throw CocoaError(.fileWriteOutOfSpace) }
        }, reply: {
            replies.append($0)
            if $0 { succeeded.fulfill() }
        }, onFailure: { failure in
            XCTAssertEqual(failure, .saveFailed)
            failed.fulfill()
        })
        XCTAssertEqual(controller.requestTermination(), .terminateLater)
        await fulfillment(of: [failed], timeout: 1)
        XCTAssertEqual(replies, [false])
        XCTAssertEqual(controller.requestTermination(), .terminateLater)
        await fulfillment(of: [succeeded], timeout: 1)
        XCTAssertEqual(replies, [false, true])
    }

    func testTimeoutCancelsQuitAndIgnoresLateSaveCompletion() async {
        let started = expectation(description: "save started")
        let timedOut = expectation(description: "quit cancelled")
        let completed = expectation(description: "late save completed")
        var continuation: CheckedContinuation<Void, Never>?
        var replies: [Bool] = []
        let controller = ApplicationTerminationController(timeout: .milliseconds(50), save: {
            await withCheckedContinuation { continuation = $0; started.fulfill() }
            completed.fulfill()
        }, reply: { replies.append($0) }, onFailure: {
            XCTAssertEqual($0, .timedOut)
            timedOut.fulfill()
        })
        XCTAssertEqual(controller.requestTermination(), .terminateLater)
        await fulfillment(of: [started, timedOut], timeout: 2)
        XCTAssertEqual(replies, [false])
        XCTAssertEqual(controller.requestTermination(), .terminateCancel)
        continuation?.resume()
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(replies, [false])
    }

    func testPersistenceFailureIsPropagatedAndHistoryCanBeRetried() async throws {
        let repository = MockClipboardRepository()
        let writer: @MainActor @Sendable (ClipItem) -> Int = { _ in 1 }
        let service = ModernClipboardService(testRepository: repository, clipboardWriter: writer)
        let adapter = ModernClipboardServiceAdapter(modernService: service, refreshPeriodically: false)
        adapter.copyToClipboard("Pending history", fromEditor: true)
        await repository.failNextWrites(1)
        do {
            try await adapter.saveBeforeTermination()
            XCTFail("A failed save must not allow termination")
        } catch {
            XCTAssertEqual((error as NSError).code, CocoaError.fileWriteOutOfSpace.rawValue)
        }
        try await adapter.saveBeforeTermination()
        let saved = try await repository.loadAll()
        XCTAssertEqual(saved.map(\.content), ["Pending history"])
    }
}
