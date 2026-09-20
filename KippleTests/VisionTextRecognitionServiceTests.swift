import XCTest
import AppKit
@testable import Kipple

@MainActor
final class VisionTextRecognitionServiceTests: XCTestCase {
    func testRecognizesRenderedText() async throws {
        let image = try makeImage(table: false)
        let service = VisionTextRecognitionService(recognitionLanguages: ["en"])
        let text = try await service.recognizeText(from: image)
        XCTAssertTrue(text.contains("Shopping List"), "Unexpected OCR result: \(text)")
    }

    func testRecognizesTableAsTSVWithSurroundingParagraphs() async throws {
        let image = try makeImage(table: true)
        let service = VisionTextRecognitionService(recognitionLanguages: ["en"])
        let text = try await service.recognizeText(from: image)
        XCTAssertTrue(text.contains("Product\tQuantity\tPrice"), "Missing table structure: \(text)")
        XCTAssertTrue(text.hasPrefix("Shopping List\n\n"), "Missing heading: \(text)")
        XCTAssertTrue(text.contains("\n\nThank you for shopping."), "Missing footer: \(text)")
        XCTAssertEqual(text.components(separatedBy: "Product").count, 2, "Table header was duplicated")
    }

    func testCancelledRecognitionDoesNotReturnText() async throws {
        let image = try makeImage(table: false)
        let service = VisionTextRecognitionService()
        let task = Task { try await service.recognizeText(from: image) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled OCR must not return a result")
        } catch is CancellationError {
            // Expected cancellation, without running recognition.
        }
    }

    func testPreservesTextBesideRotatedTable() async throws {
        let image = try makeAdversarialImage(rotatedTable: true)
        let service = VisionTextRecognitionService(recognitionLanguages: ["en"])
        let text = try await service.recognizeText(from: image)
        XCTAssertTrue(text.contains("Outside note"), "Text outside the table was lost: \(text)")
        XCTAssertTrue(text.contains("Item\tCount\tPrice\nApple\tThree\t200"), "Missing table: \(text)")
        XCTAssertEqual(text.components(separatedBy: "Item").count, 2, "Table header was duplicated")
    }

    func testBulletAndNumberedListsDoNotBecomeTSV() async throws {
        let image = try makeAdversarialImage(rotatedTable: false)
        let service = VisionTextRecognitionService(recognitionLanguages: ["en"])
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

    private func makeImage(table: Bool) throws -> CGImage {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 700,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 700).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 30), .foregroundColor: NSColor.black
        ]
        ("Shopping List" as NSString).draw(at: NSPoint(x: 50, y: 620), withAttributes: attributes)
        if table {
            drawTable(attributes: attributes)
            ("Thank you for shopping." as NSString).draw(at: NSPoint(x: 50, y: 150), withAttributes: attributes)
        }
        return try XCTUnwrap(bitmap.cgImage)
    }

    private func drawTable(attributes: [NSAttributedString.Key: Any]) {
        let rows = [["Product", "Quantity", "Price"], ["Apples", "Three", "200"], ["Oranges", "Two", "400"]]
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
