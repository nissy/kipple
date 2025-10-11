import XCTest
import CoreGraphics
@testable import Kipple

@MainActor
final class TextCaptureCoordinatorTests: XCTestCase {
    private var clipboardService: MockClipboardService!
    private var textRecognitionService: DummyTextRecognitionService!
    private var windowManager: SpyWindowManager!
    private var coordinator: TextCaptureCoordinator!

    override func setUp() async throws {
        try await super.setUp()
        clipboardService = MockClipboardService()
        textRecognitionService = DummyTextRecognitionService()
        windowManager = SpyWindowManager()
        coordinator = TextCaptureCoordinator(
            clipboardService: clipboardService,
            textRecognitionService: textRecognitionService,
            windowManager: windowManager
        )
    }

    override func tearDown() async throws {
        coordinator = nil
        windowManager = nil
        textRecognitionService = nil
        clipboardService = nil
        try await super.tearDown()
    }

    func testHandleRecognizedTextOpensMainWindow() {
        coordinator.test_handleRecognizedText("Captured text")

        XCTAssertTrue(clipboardService.copyToClipboardCalled)
        XCTAssertEqual(clipboardService.lastCopiedContent, "Captured text")
        XCTAssertEqual(clipboardService.lastCopiedFromEditor, false)
        XCTAssertTrue(windowManager.openMainWindowCalled)
        XCTAssertTrue(windowManager.showCopiedNotificationCalled)
    }
}

// MARK: - Test Doubles

@MainActor
private final class DummyTextRecognitionService: TextRecognitionServiceProtocol {
    func recognizeText(from image: CGImage) async throws -> String {
        ""
    }
}

@MainActor
private final class SpyWindowManager: WindowManaging {
    private(set) var openMainWindowCalled = false
    private(set) var showCopiedNotificationCalled = false

    func openMainWindow() {
        openMainWindowCalled = true
    }

    func showCopiedNotification() {
        showCopiedNotificationCalled = true
    }
}
