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
        XCTAssertEqual(clipboardService.history.first?.metadata?.source, .ocr)
        XCTAssertEqual(clipboardService.lastCopiedFromEditor, false)
        XCTAssertTrue(windowManager.openMainWindowCalled)
        XCTAssertTrue(windowManager.showCopiedNotificationCalled)
    }

    func testCopyPreservesEmptyTableColumns() {
        let coordinator = TextCaptureCoordinator(
            clipboardService: clipboardService,
            textRecognitionService: textRecognitionService,
            windowManager: windowManager
        )
        coordinator.test_handleRecognizedText("\tValue\t\nNext\t\t")
        XCTAssertEqual(clipboardService.lastCopiedContent, "\tValue\t\nNext\t\t")
    }

    func testSelectionWaitsForImageBeforeRecognizingAndCopying() async throws {
        let overlay = StubOverlayController()
        let capture = SuspendedImageCaptureService()
        let coordinator = makeCaptureCoordinator(overlay: overlay, capture: capture)
        let captureRequested = expectation(description: "capture requested")
        capture.onCapture = { captureRequested.fulfill() }
        textRecognitionService.result = "Captured table\tValue"

        coordinator.startCaptureFlow()
        overlay.selectionHandler?(CGRect(x: 0, y: 0, width: 100, height: 100), try XCTUnwrap(NSScreen.main))
        await fulfillment(of: [captureRequested], timeout: 1)
        XCTAssertEqual(textRecognitionService.callCount, 0)
        XCTAssertFalse(clipboardService.copyToClipboardCalled)

        let task = try XCTUnwrap(coordinator.test_captureTask())
        capture.complete(with: try makeCaptureImage())
        await task.value
        XCTAssertEqual(textRecognitionService.callCount, 1)
        XCTAssertEqual(clipboardService.lastCopiedContent, "Captured table\tValue")
        XCTAssertTrue(windowManager.openMainWindowCalled)
    }

    func testRestartDiscardsResultFromCancelledCapture() async throws {
        let overlay = StubOverlayController()
        let capture = SuspendedImageCaptureService()
        let coordinator = makeCaptureCoordinator(overlay: overlay, capture: capture)
        let captureRequested = expectation(description: "capture requested")
        capture.onCapture = { captureRequested.fulfill() }

        coordinator.startCaptureFlow()
        overlay.selectionHandler?(CGRect(x: 0, y: 0, width: 100, height: 100), try XCTUnwrap(NSScreen.main))
        await fulfillment(of: [captureRequested], timeout: 1)
        let task = try XCTUnwrap(coordinator.test_captureTask())
        coordinator.startCaptureFlow()
        capture.complete(with: try makeCaptureImage())
        await task.value

        XCTAssertEqual(textRecognitionService.callCount, 0)
        XCTAssertFalse(clipboardService.copyToClipboardCalled)
        XCTAssertFalse(windowManager.openMainWindowCalled)
        XCTAssertEqual(overlay.presentCallCount, 2)
    }

    private func makeCaptureCoordinator(
        overlay: StubOverlayController, capture: SuspendedImageCaptureService
    ) -> TextCaptureCoordinator {
        TextCaptureCoordinator(
            clipboardService: clipboardService,
            textRecognitionService: textRecognitionService,
            windowManager: windowManager,
            screenCapturePermission: .init(
                preflight: { true }, request: { true }, openPermissionTab: {}, openSystemSettings: {},
                pollingIntervalNanoseconds: 10_000_000
            ),
            imageCaptureService: capture
        ) { selection, cancel in
            overlay.selectionHandler = selection
            overlay.cancelHandler = cancel
            return overlay
        }
    }

    private func makeCaptureImage() throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    func testStartCaptureFlowWhenPermissionGrantedPresentsOverlay() {
        let preflightState = true
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
    var result = ""
    private(set) var callCount = 0

    func recognizeText(from image: CGImage) async throws -> String {
        callCount += 1
        return result
    }
}

@MainActor
private final class SuspendedImageCaptureService: ScreenImageCapturing {
    var onCapture: (() -> Void)?
    private var continuation: CheckedContinuation<CGImage, Never>?

    func captureImage(from rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onCapture?()
        }
    }

    func complete(with image: CGImage) {
        continuation?.resume(returning: image)
        continuation = nil
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
