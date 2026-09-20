import AppKit
import ScreenCaptureKit

@MainActor
protocol ScreenImageCapturing {
    func captureImage(from rect: CGRect, on screen: NSScreen) async throws -> CGImage
}

enum ScreenImageCaptureError: Error {
    case invalidSelection
    case displayUnavailable
    case imageUnavailable
}

struct ScreenCaptureRegion {
    let sourceRect: CGRect
    let pixelWidth: Int
    let pixelHeight: Int

    init(selection: CGRect, screenFrame: CGRect, scale: CGFloat) throws {
        guard scale.isFinite, scale > 0,
              [
                selection.minX, selection.minY, selection.width, selection.height,
                screenFrame.minX, screenFrame.minY, screenFrame.width, screenFrame.height
              ].allSatisfy(\.isFinite),
              !selection.isEmpty, !screenFrame.isEmpty else {
            throw ScreenImageCaptureError.invalidSelection
        }
        let clipped = selection.intersection(screenFrame)
        guard !clipped.isNull, !clipped.isEmpty else {
            throw ScreenImageCaptureError.invalidSelection
        }
        // AppKit uses a bottom-left origin; ScreenCaptureKit uses display-local top-left coordinates.
        let pixels = CGRect(
            x: (clipped.minX - screenFrame.minX) * scale,
            y: (screenFrame.maxY - clipped.maxY) * scale,
            width: clipped.width * scale,
            height: clipped.height * scale
        ).integral.intersection(CGRect(
            x: 0, y: 0, width: screenFrame.width * scale, height: screenFrame.height * scale
        ))
        sourceRect = CGRect(
            x: pixels.minX / scale, y: pixels.minY / scale,
            width: pixels.width / scale, height: pixels.height / scale
        )
        pixelWidth = max(1, Int(pixels.width))
        pixelHeight = max(1, Int(pixels.height))
    }
}

@MainActor
final class ScreenImageCaptureService: ScreenImageCapturing {
    func captureImage(from rect: CGRect, on screen: NSScreen) async throws -> CGImage {
        try Task.checkCancellation()
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            throw ScreenImageCaptureError.displayUnavailable
        }
        let screenFrame = screen.frame
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenImageCaptureError.displayUnavailable
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let region = try ScreenCaptureRegion(
            selection: rect, screenFrame: screenFrame, scale: CGFloat(filter.pointPixelScale)
        )
        let configuration = SCScreenshotConfiguration()
        configuration.sourceRect = region.sourceRect
        configuration.width = region.pixelWidth
        configuration.height = region.pixelHeight
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        guard let image = output.sdrImage else {
            throw ScreenImageCaptureError.imageUnavailable
        }
        return image
    }
}
