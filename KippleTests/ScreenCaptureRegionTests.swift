import XCTest
@testable import Kipple

final class ScreenCaptureRegionTests: XCTestCase {
    func testRetinaSelectionUsesTopLeftPointCoordinatesAndPixelDimensions() throws {
        let region = try ScreenCaptureRegion(
            selection: CGRect(x: 100, y: 200, width: 300, height: 150),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2
        )
        XCTAssertEqual(region.sourceRect, CGRect(x: 100, y: 550, width: 300, height: 150))
        XCTAssertEqual(region.pixelWidth, 600)
        XCTAssertEqual(region.pixelHeight, 300)
    }

    func testSecondaryDisplayUsesItsOwnOrigin() throws {
        let region = try ScreenCaptureRegion(
            selection: CGRect(x: -1700, y: 1100, width: 400, height: 200),
            screenFrame: CGRect(x: -1920, y: 900, width: 1920, height: 1080), scale: 1
        )
        XCTAssertEqual(region.sourceRect, CGRect(x: 220, y: 680, width: 400, height: 200))
        XCTAssertEqual(region.pixelWidth, 400)
        XCTAssertEqual(region.pixelHeight, 200)
    }

    func testSelectionCrossingDisplayEdgesIsClipped() throws {
        let region = try ScreenCaptureRegion(
            selection: CGRect(x: -50, y: 850, width: 200, height: 100),
            screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2
        )
        XCTAssertEqual(region.sourceRect, CGRect(x: 0, y: 0, width: 150, height: 50))
        XCTAssertEqual(region.pixelWidth, 300)
        XCTAssertEqual(region.pixelHeight, 100)
    }

    func testFractionalSelectionRoundsOutToPixelBoundaries() throws {
        let region = try ScreenCaptureRegion(
            selection: CGRect(x: 10.25, y: 20.25, width: 100.1, height: 50.1),
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), scale: 2
        )
        XCTAssertEqual(region.sourceRect, CGRect(x: 10, y: 729.5, width: 100.5, height: 50.5))
        XCTAssertEqual(region.pixelWidth, 201)
        XCTAssertEqual(region.pixelHeight, 101)
    }

    func testEmptyOrOffscreenSelectionIsRejected() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        for rect in [CGRect.zero, CGRect(x: 1100, y: 10, width: 30, height: 30)] {
            XCTAssertThrowsError(try ScreenCaptureRegion(selection: rect, screenFrame: screen, scale: 2))
        }
        XCTAssertThrowsError(try ScreenCaptureRegion(selection: screen, screenFrame: screen, scale: .nan))
    }
}
