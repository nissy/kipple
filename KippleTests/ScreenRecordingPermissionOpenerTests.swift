@testable import Kipple
import XCTest

@MainActor
final class ScreenRecordingPermissionOpenerTests: XCTestCase {
    func testOpenUsesFirstCandidateOnSuccess() {
        var attemptedURLs: [URL] = []
        var showedManualInstructions = false

        let dependencies = ScreenRecordingPermissionOpener.Dependencies(
            openURL: { url in
                attemptedURLs.append(url)
                return attemptedURLs.count == 1
            },
            showManualInstructions: { showedManualInstructions = true }
        )

        ScreenRecordingPermissionOpener.openSystemSettings(
            dependencies: dependencies
        )

        XCTAssertEqual(attemptedURLs.count, 1)
        XCTAssertTrue(attemptedURLs.first?.absoluteString.contains("Privacy_ScreenCapture") ?? false)
        XCTAssertFalse(showedManualInstructions)
    }

    func testOpenStopsAfterFallbackURLSucceeds() {
        var attemptedURLs: [URL] = []
        var showedManualInstructions = false
        let dependencies = ScreenRecordingPermissionOpener.Dependencies(
            openURL: { url in
                attemptedURLs.append(url)
                return attemptedURLs.count == 2
            },
            showManualInstructions: { showedManualInstructions = true }
        )

        ScreenRecordingPermissionOpener.openSystemSettings(dependencies: dependencies)

        XCTAssertEqual(attemptedURLs.count, 2)
        XCTAssertEqual(attemptedURLs.last?.query, "Privacy_ScreenRecording")
        XCTAssertFalse(showedManualInstructions)
    }

    func testOpenShowsManualInstructionsWhenAllURLsFail() {
        var attemptedURLs: [URL] = []
        var manualInstructionCount = 0

        let dependencies = ScreenRecordingPermissionOpener.Dependencies(
            openURL: { url in
                attemptedURLs.append(url)
                return false
            },
            showManualInstructions: { manualInstructionCount += 1 }
        )

        ScreenRecordingPermissionOpener.openSystemSettings(
            dependencies: dependencies
        )

        XCTAssertEqual(
            attemptedURLs.compactMap(\.query),
            ["Privacy_ScreenCapture", "Privacy_ScreenRecording", "Privacy"]
        )
        XCTAssertEqual(manualInstructionCount, 1)
    }
}
