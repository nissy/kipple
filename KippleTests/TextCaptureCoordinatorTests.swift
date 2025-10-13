import XCTest
import CoreGraphics
@testable import Kipple

@MainActor
final class TextCaptureCoordinatorTests: XCTestCase {
    private var clipboardService: MockClipboardService!
    private var textRecognitionService: DummyTextRecognitionService!
    private var windowManager: SpyWindowManager!

    override func setUp() async throws {
        try await super.setUp()
        clipboardService = MockClipboardService()
        textRecognitionService = DummyTextRecognitionService()
        windowManager = SpyWindowManager()
    }

    override func tearDown() async throws {
        windowManager = nil
        textRecognitionService = nil
        clipboardService = nil
        try await super.tearDown()
    }

    func testHandleRecognizedTextOpensMainWindow() {
        let coordinator = TextCaptureCoordinator(
            clipboardService: clipboardService,
            textRecognitionService: textRecognitionService,
            windowManager: windowManager
        )

        coordinator.test_handleRecognizedText("Captured text")

        XCTAssertTrue(clipboardService.copyToClipboardCalled)
        XCTAssertEqual(clipboardService.lastCopiedContent, "Captured text")
        XCTAssertEqual(clipboardService.lastCopiedFromEditor, false)
        XCTAssertTrue(windowManager.openMainWindowCalled)
        XCTAssertTrue(windowManager.showCopiedNotificationCalled)
    }

    func testStartCaptureFlowWhenPermissionGrantedPresentsOverlay() {
        var preflightState = true
        let overlay = StubOverlayController()

        let dependencies = TextCaptureCoordinator.ScreenCapturePermissionDependencies(
            preflight: { preflightState },
            request: {
                XCTFail("request should not be called when permission is already granted")
                return false
            },
            openPermissionTab: { XCTFail("openPermissionTab should not be called") },
            openSystemSettings: { XCTFail("openSystemSettings should not be called") },
            pollingIntervalNanoseconds: 10_000_000
        )

        let coordinator = TextCaptureCoordinator(
            clipboardService: clipboardService,
            textRecognitionService: textRecognitionService,
            windowManager: windowManager,
            screenCapturePermission: dependencies
        ) { selection, cancel in
            overlay.selectionHandler = selection
            overlay.cancelHandler = cancel
            return overlay
        }

        coordinator.startCaptureFlow()

        XCTAssertEqual(overlay.presentCallCount, 1)
        XCTAssertFalse(coordinator.test_isAwaitingPermission())
    }

    func testStartCaptureFlowWhenPermissionMissingRequestsPermissionAndOpensSettings() async throws {
        var preflightState = false
        let requestExpectation = expectation(description: "request called")
        let openPermissionExpectation = expectation(description: "open permission tab")
        let openSystemSettingsExpectation = expectation(description: "open system settings")
        let overlay = StubOverlayController()

        let dependencies = TextCaptureCoordinator.ScreenCapturePermissionDependencies(
            preflight: { preflightState },
            request: {
                requestExpectation.fulfill()
                return false
            },
            openPermissionTab: { openPermissionExpectation.fulfill() },
            openSystemSettings: { openSystemSettingsExpectation.fulfill() },
            pollingIntervalNanoseconds: 10_000_000
        )

        let coordinator = TextCaptureCoordinator(
            clipboardService: clipboardService,
            textRecognitionService: textRecognitionService,
            windowManager: windowManager,
            screenCapturePermission: dependencies
        ) { selection, cancel in
            overlay.selectionHandler = selection
            overlay.cancelHandler = cancel
            return overlay
        }

        coordinator.startCaptureFlow()

        await fulfillment(of: [requestExpectation, openPermissionExpectation, openSystemSettingsExpectation], timeout: 1.0)

        XCTAssertTrue(coordinator.test_isAwaitingPermission())
        XCTAssertEqual(overlay.presentCallCount, 0)

        preflightState = true
        let overlayExpectation = expectation(description: "overlay presented")
        overlay.presentHandler = {
            overlayExpectation.fulfill()
        }

        await fulfillment(of: [overlayExpectation], timeout: 1.0)
        XCTAssertFalse(coordinator.test_isAwaitingPermission())
    }

    func testPermissionGrantedResumesCaptureFlow() async throws {
        var preflightState = false
        let requestExpectation = expectation(description: "request called")
        let overlayExpectation = expectation(description: "overlay presented")
        let overlay = StubOverlayController()
        overlay.presentHandler = {
            overlayExpectation.fulfill()
        }

        let dependencies = TextCaptureCoordinator.ScreenCapturePermissionDependencies(
            preflight: { preflightState },
            request: {
                preflightState = true
                requestExpectation.fulfill()
                return true
            },
            openPermissionTab: { },
            openSystemSettings: { },
            pollingIntervalNanoseconds: 10_000_000
        )

        let coordinator = TextCaptureCoordinator(
            clipboardService: clipboardService,
            textRecognitionService: textRecognitionService,
            windowManager: windowManager,
            screenCapturePermission: dependencies
        ) { selection, cancel in
            overlay.selectionHandler = selection
            overlay.cancelHandler = cancel
            return overlay
        }

        coordinator.startCaptureFlow()

        await fulfillment(of: [requestExpectation, overlayExpectation], timeout: 1.0)

        XCTAssertFalse(coordinator.test_isAwaitingPermission())
        XCTAssertEqual(overlay.presentCallCount, 1)
    }

    func testShowPermissionSettingsOpensPermissionTab() {
        var openPermissionTabCallCount = 0

        let dependencies = TextCaptureCoordinator.ScreenCapturePermissionDependencies(
            preflight: { true },
            request: { false },
            openPermissionTab: { openPermissionTabCallCount += 1 },
            openSystemSettings: { },
            pollingIntervalNanoseconds: 10_000_000
        )

        let coordinator = TextCaptureCoordinator(
            clipboardService: clipboardService,
            textRecognitionService: textRecognitionService,
            windowManager: windowManager,
            screenCapturePermission: dependencies
        )

        coordinator.showPermissionSettings()

        XCTAssertEqual(openPermissionTabCallCount, 1)
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

@MainActor
private final class StubOverlayController: ScreenSelectionOverlayControlling {
    var selectionHandler: TextCaptureCoordinator.OverlaySelectionHandler?
    var cancelHandler: TextCaptureCoordinator.OverlayCancelHandler?
    private(set) var presentCallCount = 0
    private(set) var cancelCallCount = 0
    var presentHandler: (() -> Void)?

    func present() {
        presentCallCount += 1
        presentHandler?()
    }

    func cancel() {
        cancelCallCount += 1
        cancelHandler?()
    }
}
