import Foundation
import CoreGraphics

enum OCRDocumentFormatter {
    struct Paragraph {
        let text: String
        let bounds: CGRect
        var lineIDs: Set<UUID> = []
    }

    struct Cell {
        let text: String
        let rows: ClosedRange<Int>
        let columns: ClosedRange<Int>
    }

    struct Table {
        let cells: [Cell]
        let bounds: CGRect
        var lineIDs: Set<UUID> = []
    }

    static func text(
        paragraphs: [Paragraph], tables: [Table], listLineIDs: Set<UUID> = [], fallback: String
    ) -> String {
        // Vision may classify the same list as a table. Prefer lists only when they account for all table text.
        let tables = tables.filter { $0.lineIDs.isEmpty || !$0.lineIDs.isSubset(of: listLineIDs) }
        var blocks: [Paragraph] = []
        var emittedTables = Set<Int>()
        // Keep Vision's reading order, replacing table paragraphs with one TSV block.
        for paragraph in paragraphs {
            // Shared recognition IDs prove membership, including for rotated tables and repeated text.
            if let index = tables.firstIndex(where: {
                !paragraph.lineIDs.isEmpty && paragraph.lineIDs.isSubset(of: $0.lineIDs)
            }) {
                if emittedTables.insert(index).inserted {
                    blocks.append(Paragraph(text: tabSeparatedText(tables[index]), bounds: tables[index].bounds))
                }
            } else {
                blocks.append(Paragraph(
                    text: paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines), bounds: paragraph.bounds
                ))
            }
        }
        for (index, table) in tables.enumerated() where !emittedTables.contains(index) {
            let insertion = blocks.firstIndex { $0.bounds.maxY < table.bounds.maxY } ?? blocks.endIndex
            blocks.insert(Paragraph(text: tabSeparatedText(table), bounds: table.bounds), at: insertion)
        }
        let result = blocks.map(\.text)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
        return result.isEmpty ? fallback : result
    }

    static func tabSeparatedText(_ table: Table) -> String {
        guard let lastRow = table.cells.map(\.rows.upperBound).max(),
              let lastColumn = table.cells.map(\.columns.upperBound).max() else { return "" }
        var rows = Array(repeating: Array(repeating: "", count: lastColumn + 1), count: lastRow + 1)
        for cell in table.cells {
            // A merged cell occupies its top-left position; the covered cells remain empty.
            rows[cell.rows.lowerBound][cell.columns.lowerBound] = escapedCell(cell.text)
        }
        return rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    private static func escapedCell(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "\"" }) else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
