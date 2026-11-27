import XCTest
import AppKit
import CoreML
import Vision
@testable import Kipple

@MainActor
final class VisionTextRecognitionServiceTests: XCTestCase {
    func testRecognizesRenderedText() async throws {
        let image = try makeImage()
        let service = makeService(recognitionLanguages: ["en"])
        let text = try await service.recognizeText(from: image)
        XCTAssertTrue(text.contains("Shopping List"), "Unexpected OCR result: \(text)")
    }

    func testRecognizesSmallTextInTallSelection() async throws {
        let image = try makeImage(height: 2160, fontSize: 14)
        let service = makeService()

        let text = try await service.recognizeText(from: image)

        XCTAssertEqual(text, "Shopping List")
    }

    func testRecognitionFinishesWithoutWaitingForPrewarm() async throws {
        let image = try makeImage()
        let prewarmStarted = expectation(description: "prewarm started")
        let prewarmCancelled = expectation(description: "prewarm cancellation reported")
        let recognitionFinished = expectation(description: "recognition finished")
        var resumePrewarm: CheckedContinuation<Void, Never>?
        var prewarmWasCancelled = false
        let recordCancellation: (VisionTextRecognitionService.RequestPhase) -> Void = { phase in
            XCTAssertEqual(phase, .prewarm)
            prewarmCancelled.fulfill()
        }
        let service = VisionTextRecognitionService(onCancellation: recordCancellation) { _, requestImage in
            if requestImage !== image {
                await withCheckedContinuation {
                    resumePrewarm = $0
                    prewarmStarted.fulfill()
                }
                prewarmWasCancelled = Task.isCancelled
            }
            return []
        }

        service.prewarm()
        await fulfillment(of: [prewarmStarted], timeout: 2)

        let recognition = Task {
            _ = try await service.recognizeText(from: image)
            recognitionFinished.fulfill()
        }
        await fulfillment(of: [recognitionFinished], timeout: 2)

        try XCTUnwrap(resumePrewarm).resume()
        await fulfillment(of: [prewarmCancelled], timeout: 2)
        try await recognition.value
        XCTAssertTrue(prewarmWasCancelled)
    }

    func testRecognizesTableAsTSVWithSurroundingParagraphs() async throws {
        let image = try makeImage(table: [["Product", "Quantity", "Price"], ["Apples", "Three", "200"], ["Oranges", "Two", "400"]])
        let service = makeService(recognitionLanguages: ["en"])
        let text = try await service.recognizeText(from: image)
        XCTAssertTrue(text.contains("Product\tQuantity\tPrice"), "Missing table structure: \(text)")
        XCTAssertTrue(text.hasPrefix("Shopping List\n\n"), "Missing heading: \(text)")
        XCTAssertTrue(text.contains("\n\nThank you for shopping."), "Missing footer: \(text)")
        XCTAssertEqual(text.components(separatedBy: "Product").count, 2, "Table header was duplicated")
    }

    func testRecognizesJapaneseAndEnglishInOneTable() async throws {
        let image = try makeFixtureImage(height: 700, scale: 2) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black
            ]
            ("在庫確認" as NSString).draw(at: NSPoint(x: 50, y: 620), withAttributes: attributes)
            self.drawTable(
                [["品名", "Quantity", "Price"], ["りんご", "Three", "200"], ["Oranges", "Four", "400"]], attributes: attributes
            )
            ("Thank you for shopping." as NSString).draw(at: NSPoint(x: 50, y: 150), withAttributes: attributes)
        }
        let text = try await makeService().recognizeText(from: image)
        XCTAssertEqual(text, "在庫確認\n\n品名\tQuantity\tPrice\nりんご\tThree\t200\nOranges\tFour\t400\n\nThank you for shopping.")
    }

    func testCancelledRecognitionDoesNotReturnText() async throws {
        let image = try makeImage()
        var phases: [VisionTextRecognitionService.RequestPhase] = []
        let recordCancellation: (VisionTextRecognitionService.RequestPhase) -> Void = { phases.append($0) }
        let service = VisionTextRecognitionService(onCancellation: recordCancellation)
        let task = Task { try await service.recognizeText(from: image) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled OCR must not return a result")
        } catch is CancellationError {
            XCTAssertEqual(phases, [.recognition])
        }
    }

    func testReportsCancellationThrownByVisionDuringRecognition() async throws {
        let image = try makeImage()
        var phases: [VisionTextRecognitionService.RequestPhase] = []
        let recordCancellation: (VisionTextRecognitionService.RequestPhase) -> Void = { phases.append($0) }
        let service = VisionTextRecognitionService(onCancellation: recordCancellation) { _, _ in
            throw VisionError.requestCancelled("test cancellation")
        }

        do {
            _ = try await service.recognizeText(from: image)
            XCTFail("Expected Vision cancellation to be propagated")
        } catch VisionError.requestCancelled {
            XCTAssertEqual(phases, [.recognition])
        }
    }

    func testPreservesTextBesideRotatedTable() async throws {
        let image = try makeAdversarialImage(rotatedTable: true)
        let service = makeService(recognitionLanguages: ["en"])
        let text = try await service.recognizeText(from: image)
        XCTAssertTrue(text.contains("Outside note"), "Text outside the table was lost: \(text)")
        XCTAssertTrue(text.contains("Item\tCount\tPrice\nApple\tThree\t200"), "Missing table: \(text)")
        XCTAssertEqual(text.components(separatedBy: "Item").count, 2, "Table header was duplicated")
    }

    func testBulletAndNumberedListsDoNotBecomeTSV() async throws {
        let image = try makeAdversarialImage(rotatedTable: false)
        let service = makeService(recognitionLanguages: ["en"])
        let text = try await service.recognizeText(from: image)
        XCTAssertFalse(text.contains("\t"), "A list was converted into table columns: \(text)")
        for item in ["Shopping List", "• Apples", "• Oranges", "1. Check prices", "2. Pay at checkout"] {
            XCTAssertTrue(text.contains(item), "Missing list content \(item): \(text)")
        }
    }

    private func makeAdversarialImage(rotatedTable: Bool) throws -> CGImage {
        let image = NSImage(size: CGSize(width: 1000, height: 700))
        do {
            image.lockFocus()
            defer { image.unlockFocus() }
            NSColor.white.setFill()
            CGRect(x: 0, y: 0, width: 1000, height: 700).fill()
            if rotatedTable {
                drawAdversarialText("Outside note", x: 220, y: 470)
                let context = try XCTUnwrap(NSGraphicsContext.current?.cgContext)
                context.saveGState()
                context.translateBy(x: 500, y: 350)
                context.rotate(by: .pi / 9)
                drawRotatedTable()
                context.restoreGState()
            } else {
                let lines = ["Shopping List", "• Apples", "• Oranges", "1. Check prices", "2. Pay at checkout"]
                for (index, line) in lines.enumerated() {
                    drawAdversarialText(line, x: 70, y: 600 - index * 100)
                }
            }
        }
        return try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    }

    private func drawAdversarialText(_ text: String, x: Int, y: Int) {
        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 27, weight: .regular), .foregroundColor: NSColor.black
        ])
    }

    private func drawRotatedTable() {
        for (row, cells) in [["Item", "Count", "Price"], ["Apple", "Three", "200"]].enumerated() {
            for (column, text) in cells.enumerated() {
                drawAdversarialText(text, x: -285 + column * 200, y: -65 + (1 - row) * 100)
            }
        }
        NSColor.black.setStroke()
        let grid = NSBezierPath()
        for x in [-300, -100, 100, 300] {
            grid.move(to: CGPoint(x: x, y: -100))
            grid.line(to: CGPoint(x: x, y: 100))
        }
        for y in [-100, 0, 100] {
            grid.move(to: CGPoint(x: -300, y: y))
            grid.line(to: CGPoint(x: 300, y: y))
        }
        grid.stroke()
    }

    private func makeService(recognitionLanguages: [String] = ["ja", "en"]) -> VisionTextRecognitionService {
        guard ProcessInfo.processInfo.environment["KIPPLE_TEST_VISION_CPU_ONLY"] == "1" else {
            return VisionTextRecognitionService(recognitionLanguages: recognitionLanguages)
        }
        let performOnCPU: VisionTextRecognitionService.PerformRequest = { request, image in
            var request = request
            let cpu = try XCTUnwrap(request.supportedComputeStageDevices[.main]?.first { device in
                if case .cpu = device { return true }
                return false
            }, "Vision document recognition must support CPU execution for this test configuration")
            request.setComputeDevice(cpu, for: .main)
            // Use the fixture's configured languages for CPU recognition of mixed-language cells.
            request.textRecognitionOptions.automaticallyDetectLanguage = false
            return try await request.perform(on: image)
        }
        return VisionTextRecognitionService(recognitionLanguages: recognitionLanguages, performRequest: performOnCPU)
    }

    private func makeImage(table: [[String]]? = nil, height: Int = 700, fontSize: CGFloat = 30) throws -> CGImage {
        try makeFixtureImage(height: height) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.black
            ]
            ("Shopping List" as NSString).draw(at: NSPoint(x: 50, y: height - 80), withAttributes: attributes)
            if let table {
                drawTable(table, attributes: attributes)
                ("Thank you for shopping." as NSString).draw(at: NSPoint(x: 50, y: 150), withAttributes: attributes)
            }
        }
    }

    private func makeFixtureImage(height: Int, scale: Int = 1, drawing: () -> Void) throws -> CGImage {
        let width = 1000
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        drawing()
        return try XCTUnwrap(bitmap.cgImage)
    }

    private func drawTable(_ rows: [[String]], attributes: [NSAttributedString.Key: Any]) {
        for (row, cells) in rows.enumerated() {
            for (column, text) in cells.enumerated() {
                (text as NSString).draw(at: NSPoint(x: 65 + column * 280, y: 480 - row * 90), withAttributes: attributes)
            }
        }
        NSColor.black.setStroke()
        let grid = NSBezierPath()
        for x in [50, 330, 610, 890] {
            grid.move(to: NSPoint(x: x, y: 280))
            grid.line(to: NSPoint(x: x, y: 550))
        }
        for y in [280, 370, 460, 550] {
            grid.move(to: NSPoint(x: 50, y: y))
            grid.line(to: NSPoint(x: 890, y: y))
        }
        grid.stroke()
    }
}
