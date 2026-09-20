//
//  VisionTextRecognitionService.swift
//  Kipple
//
//  Created by Kipple on 2025/10/09.
//

import Foundation
import Vision
import CoreGraphics

@MainActor
final class VisionTextRecognitionService: TextRecognitionServiceProtocol {
    private let recognitionLanguages: [String]
    private let minimumTextHeight: Float

    init(recognitionLanguages: [String] = ["ja", "en"], minimumTextHeight: Float = 0.015) {
        self.recognitionLanguages = recognitionLanguages
        self.minimumTextHeight = minimumTextHeight
    }

    func recognizeText(from image: CGImage) async throws -> String {
        try Task.checkCancellation()

        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.recognitionLanguages = recognitionLanguages.map { Locale.Language(identifier: $0) }
        request.textRecognitionOptions.minimumTextHeightFraction = minimumTextHeight
        request.textRecognitionOptions.useLanguageCorrection = true
        request.barcodeDetectionOptions.enabled = false

        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        return observations.map { observation in
            let document = observation.document
            let paragraphs = document.paragraphs.map {
                OCRDocumentFormatter.Paragraph(
                    text: $0.transcript, bounds: $0.boundingRegion.boundingBox.cgRect,
                    lineIDs: Set($0.lines.map(\.uuid))
                )
            }
            let tables = document.tables.map { table in
                OCRDocumentFormatter.Table(
                    cells: table.rows.flatMap { row in
                        row.map {
                            OCRDocumentFormatter.Cell(
                                text: $0.content.text.transcript, rows: $0.rowRange, columns: $0.columnRange
                            )
                        }
                    },
                    bounds: table.boundingRegion.boundingBox.cgRect,
                    lineIDs: Set(table.rows.flatMap { $0 }.flatMap { $0.content.text.lines.map(\.uuid) })
                )
            }
            let listLineIDs = Set(document.lists.flatMap { $0.items }.flatMap { $0.content.text.lines.map(\.uuid) })
            return OCRDocumentFormatter.text(
                paragraphs: paragraphs, tables: tables, listLineIDs: listLineIDs, fallback: document.text.transcript
            )
        }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")
    }
}
