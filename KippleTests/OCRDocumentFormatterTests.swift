import XCTest
@testable import Kipple

final class OCRDocumentFormatterTests: XCTestCase {
    private typealias Paragraph = OCRDocumentFormatter.Paragraph
    private typealias Cell = OCRDocumentFormatter.Cell
    private typealias Table = OCRDocumentFormatter.Table

    func testParagraphsPreserveReadingOrderAndLineBreaks() {
        let paragraphs = [
            Paragraph(text: " First line\nsecond line ", bounds: CGRect(x: 0, y: 0.2, width: 0.4, height: 0.1)),
            Paragraph(text: "Next column", bounds: CGRect(x: 0.5, y: 0.8, width: 0.4, height: 0.1))
        ]
        XCTAssertEqual(
            OCRDocumentFormatter.text(paragraphs: paragraphs, tables: [], fallback: ""),
            "First line\nsecond line\n\nNext column"
        )
    }

    func testTableReplacesCellParagraphsWithoutDuplicatingText() {
        let lineIDs = (0..<4).map { _ in UUID() }
        let table = Table(cells: [
            Cell(text: "Name", rows: 0...0, columns: 0...0),
            Cell(text: "Price", rows: 0...0, columns: 1...1),
            Cell(text: "Apple", rows: 1...1, columns: 0...0),
            Cell(text: "200", rows: 1...1, columns: 1...1)
        ], bounds: CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.4), lineIDs: Set(lineIDs))
        let paragraphs = [
            Paragraph(text: "Shopping", bounds: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.1)),
            Paragraph(text: "Name", bounds: CGRect(x: 0.2, y: 0.6, width: 0.2, height: 0.05), lineIDs: [lineIDs[0]]),
            Paragraph(text: "Price", bounds: CGRect(x: 0.6, y: 0.6, width: 0.2, height: 0.05), lineIDs: [lineIDs[1]]),
            Paragraph(text: "Apple", bounds: CGRect(x: 0.2, y: 0.4, width: 0.2, height: 0.05), lineIDs: [lineIDs[2]]),
            Paragraph(text: "200", bounds: CGRect(x: 0.6, y: 0.4, width: 0.2, height: 0.05), lineIDs: [lineIDs[3]]),
            Paragraph(text: "Thank you", bounds: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1))
        ]
        XCTAssertEqual(
            OCRDocumentFormatter.text(paragraphs: paragraphs, tables: [table], fallback: ""),
            "Shopping\n\nName\tPrice\nApple\t200\n\nThank you"
        )
    }

    func testMergedAndEmptyCellsKeepTheirPositions() {
        let merged = Cell(text: "Heading", rows: 0...0, columns: 0...2)
        let table = Table(cells: [
            merged, merged,
            Cell(text: "Value", rows: 1...2, columns: 1...1),
            Cell(text: "", rows: 1...2, columns: 2...2)
        ], bounds: .zero)
        XCTAssertEqual(OCRDocumentFormatter.tabSeparatedText(table), "Heading\t\t\n\tValue\t\n\t\t")
    }

    func testMultilineAndQuotedCellValuesAreEscapedForTSV() {
        let table = Table(cells: [
            Cell(text: "two\nlines", rows: 0...0, columns: 0...0),
            Cell(text: "a\tb", rows: 0...0, columns: 1...1),
            Cell(text: "say \"hello\"", rows: 1...1, columns: 0...0)
        ], bounds: .zero)
        XCTAssertEqual(
            OCRDocumentFormatter.tabSeparatedText(table), "\"two\nlines\"\t\"a\tb\"\n\"say \"\"hello\"\"\"\t"
        )
    }

    func testTableWithoutCellParagraphsIsInsertedBetweenSurroundingText() {
        let paragraphs = [
            Paragraph(text: "Title", bounds: CGRect(x: 0, y: 0.8, width: 1, height: 0.1)),
            Paragraph(text: "Footer", bounds: CGRect(x: 0, y: 0.1, width: 1, height: 0.1))
        ]
        let table = Table(cells: [Cell(text: "Data", rows: 0...0, columns: 0...0)],
                          bounds: CGRect(x: 0, y: 0.4, width: 1, height: 0.2))
        XCTAssertEqual(
            OCRDocumentFormatter.text(paragraphs: paragraphs, tables: [table], fallback: ""),
            "Title\n\nData\n\nFooter"
        )
    }

    func testMissingStructurePreservesFullTranscript() {
        XCTAssertEqual(OCRDocumentFormatter.text(paragraphs: [], tables: [], fallback: "Original\ntext"), "Original\ntext")
    }

    func testUnrelatedParagraphInsideTableBoundsIsPreservedEvenWithIdenticalText() {
        let tableLineID = UUID()
        let bounds = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.6)
        let paragraphs = [
            Paragraph(text: "Apple", bounds: bounds, lineIDs: [UUID()]),
            Paragraph(text: "Apple", bounds: bounds, lineIDs: [tableLineID])
        ]
        let table = Table(cells: [Cell(text: "Apple", rows: 0...0, columns: 0...0)],
                          bounds: bounds, lineIDs: [tableLineID])
        XCTAssertEqual(
            OCRDocumentFormatter.text(paragraphs: paragraphs, tables: [table], fallback: ""),
            "Apple\n\nApple"
        )
    }

    func testParagraphWithSomeNonTableLinesIsNotDiscarded() {
        let tableLineID = UUID()
        let paragraph = Paragraph(text: "Outside note\nCell", bounds: .zero, lineIDs: [UUID(), tableLineID])
        let table = Table(cells: [Cell(text: "Cell", rows: 0...0, columns: 0...0)],
                          bounds: .zero, lineIDs: [tableLineID])
        let text = OCRDocumentFormatter.text(paragraphs: [paragraph], tables: [table], fallback: "")
        XCTAssertTrue(text.contains("Outside note\nCell"))
    }

    func testTableFullyCoveredByListsPreservesListParagraphs() {
        let bulletLineID = UUID()
        let numberLineID = UUID()
        let paragraphs = [
            Paragraph(text: "• Apples", bounds: .zero, lineIDs: [bulletLineID]),
            Paragraph(text: "1. Pay", bounds: .zero, lineIDs: [numberLineID])
        ]
        let table = Table(cells: [
            Cell(text: "", rows: 0...1, columns: 0...0),
            Cell(text: "• Apples", rows: 0...0, columns: 1...1),
            Cell(text: "1. Pay", rows: 1...1, columns: 1...1)
        ], bounds: .zero, lineIDs: [bulletLineID, numberLineID])
        XCTAssertEqual(
            OCRDocumentFormatter.text(
                paragraphs: paragraphs, tables: [table], listLineIDs: [bulletLineID, numberLineID], fallback: ""
            ),
            "• Apples\n\n1. Pay"
        )
    }

    func testListInsideTableDoesNotDiscardOtherCellsOrEmptyColumns() {
        let headerLineID = UUID()
        let listLineID = UUID()
        let paragraphs = [
            Paragraph(text: "Items", bounds: .zero, lineIDs: [headerLineID]),
            Paragraph(text: "• Apples", bounds: .zero, lineIDs: [listLineID])
        ]
        let table = Table(cells: [
            Cell(text: "", rows: 0...1, columns: 0...0),
            Cell(text: "Items", rows: 0...0, columns: 1...1),
            Cell(text: "• Apples", rows: 1...1, columns: 1...1)
        ], bounds: .zero, lineIDs: [headerLineID, listLineID])
        XCTAssertEqual(
            OCRDocumentFormatter.text(
                paragraphs: paragraphs, tables: [table], listLineIDs: [listLineID], fallback: ""
            ),
            "\tItems\n\t• Apples"
        )
    }

    func testMissingLineIdentityDoesNotRemoveParagraphsBasedOnPosition() {
        let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let paragraph = Paragraph(text: "Outside note", bounds: bounds)
        let table = Table(cells: [Cell(text: "Cell", rows: 0...0, columns: 0...0)], bounds: bounds)
        XCTAssertEqual(
            OCRDocumentFormatter.text(paragraphs: [paragraph], tables: [table], fallback: ""),
            "Outside note\n\nCell"
        )
    }
}
